<#
.SYNOPSIS
  Starts a GUI program, presses buttons by their captions, saves a picture of the window.

.DESCRIPTION
  The script is for the checks and for the pictures of the guide. It finds the buttons
  as Win32 child windows of the class Button and sends the message BM_CLICK.

.EXAMPLE
  .\gui-shot.ps1 -Exe D:\work\fb5\remote\EmployeeRemote.exe -Click Connect -Png D:\shot.png
#>
param(
    [Parameter(Mandatory = $true)][string]$Exe,
    [Parameter(Mandatory = $true)][string]$Png,
    [string[]]$Click = @(),
    [int]$WaitSeconds = 4,
    [switch]$KeepRunning
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class GuiShot {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT r);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    public delegate bool EnumProc(IntPtr hwnd, IntPtr lp);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent, EnumProc cb, IntPtr lp);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder sb, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder sb, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, StringBuilder l);
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    public static List<string> Children(IntPtr parent) {
        var list = new List<string>();
        EnumChildWindows(parent, (h, l) => {
            var c = new StringBuilder(256); GetClassName(h, c, 256);
            var t = new StringBuilder(4096); SendMessage(h, 0x000D, (IntPtr)4096, t);   // WM_GETTEXT
            list.Add(h.ToInt64() + "|" + c + "|" + t.ToString().Replace("\r\n", " ")); return true; }, IntPtr.Zero);
        return list;
    }
}
'@

# Without this call the picture is cut on a display with scaling.
[GuiShot]::SetProcessDPIAware() | Out-Null

$folder = Split-Path $Exe -Parent
$p = Start-Process -FilePath $Exe -WorkingDirectory $folder -PassThru
foreach ($i in 1..60) { $p.Refresh(); if ($p.MainWindowHandle -ne 0) { break }; Start-Sleep -Milliseconds 250 }
if ($p.MainWindowHandle -eq 0) { Stop-Process -Id $p.Id -Force; throw "No main window: $Exe" }
Write-Host "window: $($p.MainWindowTitle)"

foreach ($caption in $Click) {
    $button = [GuiShot]::Children($p.MainWindowHandle) | Where-Object { $_ -like "*|Button|$caption" } | Select-Object -First 1
    if (-not $button) { Stop-Process -Id $p.Id -Force; throw "Button '$caption' is not found" }
    [GuiShot]::PostMessage([IntPtr][long]$button.Split('|')[0], 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null   # BM_CLICK
    Start-Sleep -Seconds $WaitSeconds
}

# Text of the edit controls: the message line of the application is one of them.
[GuiShot]::Children($p.MainWindowHandle) | Where-Object { $_ -like '*|Edit|*' } | ForEach-Object {
    $text = $_.Split('|', 3)[2]
    if ($text.Length -gt 0) { Write-Host "edit: $text" }
}

$r = New-Object GuiShot+RECT
[GuiShot]::GetWindowRect($p.MainWindowHandle, [ref]$r) | Out-Null
$bmp = New-Object System.Drawing.Bitmap(($r.R - $r.L), ($r.B - $r.T))
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
[GuiShot]::PrintWindow($p.MainWindowHandle, $hdc, 2) | Out-Null
$g.ReleaseHdc($hdc); $g.Dispose()
$bmp.Save($Png, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
Write-Host "picture: $Png"

if (-not $KeepRunning) { Stop-Process -Id $p.Id -Force }

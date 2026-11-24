<#
.SYNOPSIS
  Makes the pictures of the guide: the application, the key provider, the Prompt window.

.DESCRIPTION
  The script needs the server of the chosen version and the programs in work\build
  (scripts 01-30). It writes PNG files to doc\ru\images\closed-gui.

.EXAMPLE
  .\make-screenshots.ps1 -Version 5
#>
param(
    [ValidateSet('3', '4', '5')][string]$Version = '5',
    [string]$WorkDir = "",
    [string]$OutDir = ""
)
$deploy = Join-Path (Split-Path $PSScriptRoot -Parent) "deploy"
. (Join-Path $deploy "common.ps1")
$d = Get-Deploy $Version $WorkDir
if ($OutDir -eq "") { $OutDir = Join-Path (Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent) "doc\ru\images\closed-gui" }

Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class Shot {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT r);
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hwnd, int attr, out RECT r, int size);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
    delegate bool EnumProc(IntPtr hwnd, IntPtr lp);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr lp);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent, EnumProc cb, IntPtr lp);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder sb, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder sb, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, string l);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    // First visible top-level window whose title starts with the text.
    public static IntPtr Find(string titleStart) {
        IntPtr found = IntPtr.Zero;
        EnumWindows((h, l) => {
            if (!IsWindowVisible(h)) return true;
            var t = new StringBuilder(256); GetWindowText(h, t, 256);
            if (t.ToString().StartsWith(titleStart)) { found = h; return false; }
            return true; }, IntPtr.Zero);
        return found;
    }
    static IntPtr Child(IntPtr win, string cls, string text) {
        IntPtr found = IntPtr.Zero;
        EnumChildWindows(win, (h, l) => {
            var c = new StringBuilder(64); GetClassName(h, c, 64);
            var t = new StringBuilder(256); GetWindowText(h, t, 256);
            if (c.ToString() == cls && (text == null || t.ToString() == text) && found == IntPtr.Zero) found = h;
            return true; }, IntPtr.Zero);
        return found;
    }
    public static bool Click(IntPtr win, string button) {
        IntPtr b = Child(win, "Button", button);
        if (b == IntPtr.Zero) return false;
        PostMessage(b, 0x00F5, IntPtr.Zero, IntPtr.Zero);   // BM_CLICK
        return true;
    }
    public static bool Type(IntPtr win, string text) {
        IntPtr e = Child(win, "Edit", null);
        if (e == IntPtr.Zero) return false;
        SendMessage(e, 0x000C, IntPtr.Zero, text);          // WM_SETTEXT
        return true;
    }
}
'@
[Shot]::SetProcessDPIAware() | Out-Null

function Wait-Window([string]$title, [int]$seconds = 15) {
    $deadline = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $deadline) {
        $h = [Shot]::Find($title)
        if ($h -ne [IntPtr]::Zero) { return $h }
        Start-Sleep -Milliseconds 200
    }
    return [IntPtr]::Zero
}

function Save-Window([IntPtr]$h, [string]$name) {
    $r = New-Object Shot+RECT
    [Shot]::GetWindowRect($h, [ref]$r) | Out-Null
    $bmp = New-Object System.Drawing.Bitmap(($r.R - $r.L), ($r.B - $r.T))
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc()
    [Shot]::PrintWindow($h, $hdc, 2) | Out-Null
    $g.ReleaseHdc($hdc); $g.Dispose()
    # The window rectangle has invisible borders for resizing. Cut the picture to the visible frame.
    $f = New-Object Shot+RECT
    if (([Shot]::DwmGetWindowAttribute($h, 9, [ref]$f, 16) -eq 0) -and ($f.R -gt $f.L)) {
        $crop = New-Object System.Drawing.Rectangle(($f.L - $r.L), ($f.T - $r.T), ($f.R - $f.L), ($f.B - $f.T))
        $cut = $bmp.Clone($crop, $bmp.PixelFormat)
        $bmp.Dispose()
        $bmp = $cut
    }
    $file = Join-Path $OutDir $name
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
    Write-Host "picture: $file"
}

function Stop-Programs {
    Get-Process KeyProvider, EmployeeRemote, EmployeeEmbedded -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -like (Join-Path $d.WorkDir "*") } | Stop-Process -Force
}

function Start-App([string]$folder, [string]$exe) {
    $p = Start-Process -FilePath (Join-Path $folder $exe) -WorkingDirectory $folder -PassThru
    $h = Wait-Window "Employee"
    if ($h -eq [IntPtr]::Zero) { Fail "The window of $exe is not found." }
    return $h
}

Remove-Item Env:FIREBIRD -ErrorAction SilentlyContinue
if ($Version -eq '3') { $env:FIREBIRD_LOCK = Join-Path $d.Root "lock" }
if (-not (Test-Port $d.Fb.Port)) { & (Join-Path $deploy "11-start-server.ps1") -Version $Version -WorkDir $d.WorkDir *> $null }
$keyText = ((Get-Content $d.KeysFile | Where-Object { $_ -match '^\s*Key\s*=\s*Red\s' } | Select-Object -First 1) -replace '^\s*Key\s*=\s*Red\s+', '').Trim()
$remote = Join-Path $d.Root "remote"
$embedded = Join-Path $d.Root "embedded"
Stop-Programs

# ---- the application, network connection and embedded, variant A
& (Join-Path $deploy "40-deploy-remote.ps1") -Version $Version -WorkDir $d.WorkDir -KeySource a *> $null
$h = Start-App $remote "EmployeeRemote.exe"
[Shot]::Click($h, "Connect") | Out-Null
Start-Sleep -Seconds 3
Save-Window $h "app-remote.png"
Stop-Programs

& (Join-Path $deploy "41-deploy-embedded.ps1") -Version $Version -WorkDir $d.WorkDir -KeySource a *> $null
$h = Start-App $embedded "EmployeeEmbedded.exe"
[Shot]::Click($h, "Connect") | Out-Null
Start-Sleep -Seconds 3
Save-Window $h "app-embedded.png"
Stop-Programs

# ---- the key provider, variant C
& (Join-Path $deploy "40-deploy-remote.ps1") -Version $Version -WorkDir $d.WorkDir -KeySource c *> $null
# A fixed pipe name: the default name contains the Windows user name, and it would be in the picture.
Add-Content -Path (Join-Path $remote "KeySource.ini") -Value "Pipe=FbKeyProvider-demo" -Encoding ASCII
Add-Content -Path (Join-Path $d.Root "keyprovider\KeyProvider.ini") -Value "Pipe=FbKeyProvider-demo" -Encoding ASCII
Start-Process -FilePath (Join-Path $d.Root "keyprovider\KeyProvider.exe") -ArgumentList "/show" | Out-Null
$provider = Wait-Window "Key Provider"
$h = Start-App $remote "EmployeeRemote.exe"
[Shot]::Click($h, "Connect") | Out-Null
$ask = Wait-Window "Key Provider - enter the key"
if ($ask -eq [IntPtr]::Zero) { Stop-Programs; Fail "The window of the key provider is not found." }
Start-Sleep -Milliseconds 800
Save-Window $ask "provider-ask.png"
[Shot]::Type($ask, $keyText) | Out-Null
[Shot]::Click($ask, "OK") | Out-Null
Start-Sleep -Seconds 3
Save-Window $provider "provider-window.png"
Stop-Programs

# ---- the Prompt parameter: no KeySource.dll, the KeyHolder plugin asks for the key
foreach ($mode in "remote", "embedded") {
    if ($mode -eq "remote") {
        & (Join-Path $deploy "40-deploy-remote.ps1") -Version $Version -WorkDir $d.WorkDir -KeySource a -Folder "remote-prompt" *> $null
        $exe = "EmployeeRemote.exe"
    } else {
        & (Join-Path $deploy "41-deploy-embedded.ps1") -Version $Version -WorkDir $d.WorkDir -KeySource a -Folder "embedded-prompt" *> $null
        $exe = "EmployeeEmbedded.exe"
    }
    $folder = Join-Path $d.Root "$mode-prompt"
    Remove-Item (Join-Path $folder "KeySource.dll")
    Set-Content -Path (Join-Path $folder "plugins\KeyHolder.conf") -Encoding ASCII -Value "Prompt = Enter key %k for database %d"
    $h = Start-App $folder $exe
    [Shot]::Click($h, "Connect") | Out-Null
    $ask = Wait-Window "Enter key" 8
    if ($ask -eq [IntPtr]::Zero) {
        Write-Host "Prompt, ${mode}: NO input window"
    } else {
        Write-Host "Prompt, ${mode}: the input window is shown"
        Start-Sleep -Milliseconds 500
        if ($mode -eq "remote") { Save-Window $ask "prompt.png" }
    }
    Stop-Programs
}
Remove-Item Env:FIREBIRD_LOCK -ErrorAction SilentlyContinue

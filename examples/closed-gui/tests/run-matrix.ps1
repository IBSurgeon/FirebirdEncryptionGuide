<#
.SYNOPSIS
  Checks the example: Firebird versions x connection modes x KeySource variants.

.DESCRIPTION
  For each combination the script makes the application folder (scripts 40 and 41) and runs:

    isql   reads the table CUSTOMER through fbclient.dll and KeySource.dll of the folder
    app    EmployeeRemote.exe or EmployeeEmbedded.exe with the switch /selftest:
           connect, change a row, connect again, read the row

  Variant c: the script starts no key provider. KeySource.dll starts it, the script types
  the test key into its window. The window must appear once for a combination.
  Variant d: the script starts the demo key service and counts its requests.

  -Negative   also run the checks that must end with an error (first version, network mode)
  -Load       also run 1000 connections and 8 threads for each variant (first version, network mode)

  Run the scripts 01-30 before this script.

.EXAMPLE
  .\run-matrix.ps1
.EXAMPLE
  .\run-matrix.ps1 -Version 5 -Mode remote -KeySource c,d -Negative
#>
param(
    [ValidateSet('3', '4', '5')][string[]]$Version = @('3', '4', '5'),
    [ValidateSet('remote', 'embedded')][string[]]$Mode = @('remote', 'embedded'),
    [ValidateSet('a', 'b', 'c', 'd')][string[]]$KeySource = @('a', 'b', 'c', 'd'),
    [string]$WorkDir = "",
    [switch]$Negative,
    [switch]$Load
)
$deploy = Join-Path (Split-Path $PSScriptRoot -Parent) "deploy"
. (Join-Path $deploy "common.ps1")
$ErrorActionPreference = "Stop"

Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class KeyDialog {
    delegate bool EnumProc(IntPtr hwnd, IntPtr lp);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr FindWindow(string cls, string title);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent, EnumProc cb, IntPtr lp);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder sb, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder sb, int n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, string l);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    // Types the text into the window of the key provider and presses the button. False: no window.
    public static bool Fill(string text, string button) {
        IntPtr win = FindWindow(null, "Key Provider - enter the key");
        if (win == IntPtr.Zero) return false;
        IntPtr edit = IntPtr.Zero, press = IntPtr.Zero;
        EnumChildWindows(win, (h, l) => {
            var c = new StringBuilder(64); GetClassName(h, c, 64);
            var t = new StringBuilder(64); GetWindowText(h, t, 64);
            if (c.ToString() == "Edit" && edit == IntPtr.Zero) edit = h;
            if (c.ToString() == "Button" && t.ToString() == button) press = h;
            return true; }, IntPtr.Zero);
        if (edit == IntPtr.Zero || press == IntPtr.Zero) return false;
        SendMessage(edit, 0x000C, IntPtr.Zero, text);                  // WM_SETTEXT
        PostMessage(press, 0x00F5, IntPtr.Zero, IntPtr.Zero);          // BM_CLICK
        return true;
    }
}
'@

$script:dialogs = 0
$script:dialogButton = "OK"
$keysFile = (Get-Deploy '5' $WorkDir).KeysFile
$redKey = ((Get-Content $keysFile | Where-Object { $_ -match '^\s*Key\s*=\s*Red\s' } | Select-Object -First 1) -replace '^\s*Key\s*=\s*Red\s+', '').Trim()
$greenKey = ((Get-Content $keysFile | Where-Object { $_ -match '^\s*Key\s*=\s*Green\s' } | Select-Object -First 1) -replace '^\s*Key\s*=\s*Green\s+', '').Trim()
$script:typedKey = $redKey

# Runs a program of the application folder. While it works, types the key into the
# window of the key provider if the window appears.
function Invoke-InFolder([string]$folder, [string]$exe, [string[]]$arguments, [int]$seconds = 90) {
    $out = Join-Path $folder "test.out"
    $err = Join-Path $folder "test.err"
    $p = Start-Process -FilePath (Join-Path $folder $exe) -ArgumentList $arguments -WorkingDirectory $folder `
        -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    $null = $p.Handle   # without this line PowerShell does not keep the exit code
    $deadline = (Get-Date).AddSeconds($seconds)
    while ((-not $p.HasExited) -and ((Get-Date) -lt $deadline)) {
        if ([KeyDialog]::Fill($script:typedKey, $script:dialogButton)) {
            $script:dialogs++
            Start-Sleep -Milliseconds 700
        }
        Start-Sleep -Milliseconds 150
    }
    if (-not $p.HasExited) {
        Stop-Process -Id $p.Id -Force
        return [pscustomobject]@{ Code = -1; Text = "TIMEOUT after $seconds seconds" }
    }
    $p.WaitForExit()
    $text = ((Get-Content $out, $err -ErrorAction SilentlyContinue) | Where-Object { $_.Trim() }) -join " | "
    return [pscustomobject]@{ Code = $p.ExitCode; Text = $text }
}

function Stop-Helpers($d) {
    # Only the programs from the work folder of the example.
    Get-Process KeyProvider -ErrorAction SilentlyContinue | Where-Object { $_.Path -like (Join-Path $d.WorkDir "*") } |
        Stop-Process -Force
    if ($script:keyServer) {
        if (-not $script:keyServer.HasExited) { Stop-Process -Id $script:keyServer.Id -Force }
        $script:keyServer = $null
    }
}

function Start-KeyServer($d, [string]$token = "test-token") {
    if (Test-Port 8085) { Fail "Port 8085 is in use. The demo key service cannot start." }
    $script:keyServerLog = Join-Path $d.Root "key-server.log"
    Remove-Item $script:keyServerLog -ErrorAction SilentlyContinue
    $server = Join-Path (Split-Path $PSScriptRoot -Parent) "restserver\key-server.ps1"
    $script:keyServer = Start-Process powershell -WindowStyle Hidden -PassThru -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$server`"", "-Token", $token, "-LogFile", "`"$script:keyServerLog`"")
    foreach ($i in 1..50) { if (Test-Port 8085) { return }; Start-Sleep -Milliseconds 200 }
    Fail "The demo key service does not start."
}

function Get-KeyServerRequests {
    if (Test-Path $script:keyServerLog) { return @(Get-Content $script:keyServerLog).Count }
    return 0
}

function Set-VersionEnv($d) {
    Remove-Item Env:FIREBIRD -ErrorAction SilentlyContinue
    if ($d.Version -eq '3') { $env:FIREBIRD_LOCK = Join-Path $d.Root "lock" }
    else { Remove-Item Env:FIREBIRD_LOCK -ErrorAction SilentlyContinue }
}

# Makes the folder and returns: folder, database string for isql, name of the application.
function New-Folder($d, [string]$mode, [string]$variant) {
    if ($mode -eq 'remote') {
        & (Join-Path $deploy "40-deploy-remote.ps1") -Version $d.Version -WorkDir $d.WorkDir -KeySource $variant *> $null
        $folder = Join-Path $d.Root "remote"
        return [pscustomobject]@{ Folder = $folder; Db = "localhost/$($d.Fb.Port):crypt_employee"; App = "EmployeeRemote.exe" }
    }
    & (Join-Path $deploy "41-deploy-embedded.ps1") -Version $d.Version -WorkDir $d.WorkDir -KeySource $variant *> $null
    $folder = Join-Path $d.Root "embedded"
    return [pscustomobject]@{ Folder = $folder; Db = (Join-Path $folder "EMPLOYEE.FDB"); App = "EmployeeEmbedded.exe" }
}

function Invoke-Isql2($f) {
    $sql = Join-Path $f.Folder "test.sql"
    Set-Content -Path $sql -Value "set list on; select count(*) as customers from customer;" -Encoding ASCII
    return Invoke-InFolder $f.Folder "isql.exe" @("-q", "-user", "SYSDBA", "-password", "masterkey", "-i", "`"$sql`"", "`"$($f.Db)`"")
}

$results = @()
$failed = 0
$started = @()

foreach ($v in $Version) {
    $d = Get-Deploy $v $WorkDir
    Set-VersionEnv $d
    if (-not (Test-Port $d.Fb.Port)) {
        & (Join-Path $deploy "11-start-server.ps1") -Version $v -WorkDir $d.WorkDir *> $null
        $started += $v
    }
    foreach ($m in $Mode) {
        foreach ($k in $KeySource) {
            Stop-Helpers $d
            $script:dialogs = 0
            $f = New-Folder $d $m $k
            if ($k -eq 'd') { Start-KeyServer $d }

            $isql = Invoke-Isql2 $f
            $isqlOk = ($isql.Code -eq 0) -and ($isql.Text -match 'CUSTOMERS\s+15') -and ($isql.Text -notmatch 'SQLSTATE')
            Remove-Item (Join-Path $f.Folder "selftest.log") -ErrorAction SilentlyContinue
            $app = Invoke-InFolder $f.Folder $f.App @("/selftest")
            $appLog = (Get-Content (Join-Path $f.Folder "selftest.log") -ErrorAction SilentlyContinue | Select-Object -Last 1)
            $appOk = ($app.Code -eq 0) -and ($appLog -eq 'RESULT: OK')

            $note = ""
            if ($k -eq 'c') {
                $note = "key windows: $($script:dialogs)"
                if ($script:dialogs -ne 1) { $appOk = $false }
            }
            if ($k -eq 'd') {
                # isql is one process, the application is another: one request for each process.
                $requests = Get-KeyServerRequests
                $note = "requests to the key service: $requests"
                if ($requests -ne 2) { $appOk = $false }
            }
            if (-not $isqlOk) { $note += " isql: $($isql.Text)" }
            if (-not $appOk) { $note += " app: $appLog" }
            if (-not ($isqlOk -and $appOk)) { $failed++ }
            $row = [pscustomobject]@{
                Firebird = $v; Mode = $m; KeySource = $k
                Isql = $(if ($isqlOk) { 'OK' } else { 'FAIL' })
                App = $(if ($appOk) { 'OK' } else { 'FAIL' })
                Note = $note.Trim()
            }
            $results += $row
            Write-Host ("{0} {1,-8} {2}  isql {3,-4} app {4,-4} {5}" -f $v, $m, $k, $row.Isql, $row.App, $row.Note)
            Stop-Helpers $d
        }
    }
}

# ------------------------------------------------------------------ checks that must fail
if ($Negative) {
    $d = Get-Deploy $Version[0] $WorkDir
    Set-VersionEnv $d
    Write-Host ""
    Write-Host "== Checks that must end with an error (Firebird $($d.Version), network connection)"

    function Test-Refused([string]$name, $f, [string]$logPattern) {
        $r = Invoke-Isql2 $f
        $refused = ($r.Text -match 'SQLSTATE') -and ($r.Text -notmatch 'CUSTOMERS\s+15')
        $logOk = $true
        if ($logPattern -ne "") {
            $log = (Get-Content (Join-Path $f.Folder "KeySource.log") -ErrorAction SilentlyContinue) -join "`n"
            $logOk = $log -match $logPattern
        }
        $ok = $refused -and $logOk
        if (-not $ok) { $script:failed++ }
        $short = $r.Text
        if ($short.Length -gt 110) { $short = $short.Substring(0, 110) }
        Write-Host ("{0,-4} {1,-44} {2}" -f $(if ($ok) { 'OK' } else { 'FAIL' }), $name, $short)
    }
    $script:failed = $failed

    Stop-Helpers $d
    $f = New-Folder $d 'remote' 'a'
    Remove-Item (Join-Path $f.Folder "KeySource.dll")
    Test-Refused "no KeySource.dll" $f ""

    $f = New-Folder $d 'remote' 'b'
    $keyFile = Join-Path $d.Root "keyfile\employee.key"
    Set-Content -Path $keyFile -Value "Key=Red $greenKey" -Encoding ASCII
    Test-Refused "b: wrong key in the file" $f "keys from the file"
    Set-Content -Path $keyFile -Value "Key=Red" -Encoding ASCII
    Test-Refused "b: line of the key without a value" $f "keys from the file"
    Remove-Item $keyFile
    Test-Refused "b: no file of keys" $f "cannot read the file of keys"

    $f = New-Folder $d 'remote' 'c'
    $script:dialogButton = "Cancel"
    Test-Refused "c: the user cancels the input" $f "did not enter the key"
    $script:dialogButton = "OK"
    Stop-Helpers $d
    $script:typedKey = $greenKey
    Test-Refused "c: the user types a wrong key" $f "keys from the key provider"
    $script:typedKey = $redKey
    Stop-Helpers $d
    Add-Content -Path (Join-Path $f.Folder "KeySource.ini") -Value "ProviderExe=$(Join-Path $d.Root 'keyprovider\missing.exe')" -Encoding ASCII
    (Get-Content (Join-Path $f.Folder "KeySource.ini")) | Where-Object { $_ -notmatch 'KeyProvider\.exe' } |
        Set-Content -Path (Join-Path $f.Folder "KeySource.ini") -Encoding ASCII
    Test-Refused "c: the key provider cannot start" $f "cannot start the key provider"

    $f = New-Folder $d 'remote' 'd'
    Test-Refused "d: the key service is not running" $f "does not answer"
    Start-KeyServer $d "other-token"
    Test-Refused "d: wrong token" $f "status 401"
    Stop-Helpers $d
    $failed = $script:failed
}

# ------------------------------------------------------------------ load
if ($Load) {
    $d = Get-Deploy $Version[0] $WorkDir
    Set-VersionEnv $d
    Write-Host ""
    Write-Host "== Load: 1000 connections, then 8 threads x 125 connections (Firebird $($d.Version), network connection)"
    $loop = Join-Path $PSScriptRoot "connect_loop.py"
    foreach ($k in $KeySource) {
        Stop-Helpers $d
        $f = New-Folder $d 'remote' $k
        if ($k -eq 'd') { Start-KeyServer $d }
        if ($k -eq 'c') {
            # Give the key to the key provider before the load.
            $script:dialogs = 0
            Invoke-Isql2 $f | Out-Null
        }
        foreach ($threads in 1, 8) {
            $count = 1000 / $threads
            $out = (& python $loop --client $f.Folder --dsn $f.Db --count $count --threads $threads 2>&1 | Out-String).Trim() -replace "\r?\n", " | "
            if ($LASTEXITCODE -ne 0) { $failed++ }
            Write-Host ("{0} threads={1}: {2}" -f $k, $threads, $out)
        }
        if ($k -eq 'd') {
            $requests = Get-KeyServerRequests
            Write-Host "d: requests to the key service for 2 processes: $requests"
            if ($requests -ne 2) { $failed++ }
        }
        Stop-Helpers $d
    }
}

foreach ($v in $started) { & (Join-Path $deploy "12-stop-server.ps1") -Version $v -WorkDir (Get-Deploy $v $WorkDir).WorkDir *> $null }
Remove-Item Env:FIREBIRD_LOCK -ErrorAction SilentlyContinue

Write-Host ""
if ($failed -eq 0) { Write-Host "ALL CHECKS PASSED: $($results.Count) combinations" -ForegroundColor Green; exit 0 }
Write-Host "FAILED CHECKS: $failed" -ForegroundColor Red
exit 1

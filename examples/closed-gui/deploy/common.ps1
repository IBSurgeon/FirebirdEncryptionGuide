# Common functions of the deployment scripts. Each script dot-sources this file.
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Fail([string]$msg) {
    Write-Host "ERROR: $msg" -ForegroundColor Red
    exit 1
}

function Step([string]$msg) {
    Write-Host "== $msg"
}

# Returns the paths and settings for one Firebird version.
function Get-Deploy([string]$Version, [string]$WorkDir) {
    $all = Import-PowerShellDataFile (Join-Path $PSScriptRoot "versions.psd1")
    if ($WorkDir -eq "") { $WorkDir = Join-Path (Split-Path $PSScriptRoot -Parent) "work" }
    $fb = $all.Firebird[$Version]
    $plugin = $all.Plugin[$Version]
    $downloads = Join-Path $WorkDir "downloads"
    $root = Join-Path $WorkDir "fb$Version"
    return [pscustomobject]@{
        Version     = $Version
        Fb          = $fb
        Plugin      = $plugin
        WorkDir     = $WorkDir
        Downloads   = $downloads
        FirebirdZip = Join-Path $downloads (Split-Path $fb.Url -Leaf)
        PluginZip   = Join-Path $downloads (Split-Path $plugin.Url -Leaf)
        Root        = $root
        License     = Join-Path $root "license\DbCrypt.conf"
        PluginDir   = Join-Path $root "plugin"
        Server      = Join-Path $root "server"
        Db          = Join-Path $root "db"
        Tmp         = Join-Path $root "tmp"
        PidFile     = Join-Path $root "server.pid"
        KeysFile    = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "common\test-keys.conf"
    }
}

function Get-Sha256([string]$file) {
    return (Get-FileHash -Path $file -Algorithm SHA256).Hash.ToLower()
}

# Downloads a file. A file that is already in the folder is not downloaded again.
function Get-File([string]$url, [string]$file, [switch]$Force) {
    if ((Test-Path $file) -and (-not $Force)) {
        Write-Host "   found: $file"
        return
    }
    New-Item -ItemType Directory -Force (Split-Path $file -Parent) | Out-Null
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $part = "$file.part"
    Write-Host "   download: $url"
    Invoke-WebRequest -Uri $url -OutFile $part -UseBasicParsing
    Move-Item $part $file -Force
}

function Test-Port([int]$port) {
    $c = New-Object System.Net.Sockets.TcpClient
    try { $c.Connect("127.0.0.1", $port); return $true } catch { return $false } finally { $c.Close() }
}

# The Firebird tools of the example must not read the settings of another Firebird.
function Set-FirebirdEnv($d) {
    Remove-Item Env:FIREBIRD -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force $d.Tmp | Out-Null
    $env:FIREBIRD_TMP = $d.Tmp
    if ($d.Version -eq '3') {
        # Firebird 3.0 only: a private lock folder. Without it the server of the example cannot work
        # when a Firebird 3.0 service runs on the same computer (error "MappingIpc: Cannot initialize
        # the shared memory region"). Do not do this for 4.0 and 5.0: there it breaks the logins.
        $lock = Join-Path $d.Root "lock"
        New-Item -ItemType Directory -Force $lock | Out-Null
        $env:FIREBIRD_LOCK = $lock
    } else {
        Remove-Item Env:FIREBIRD_LOCK -ErrorAction SilentlyContinue
    }
}

# Runs SQL statements with isql from the server folder. isql works in embedded mode.
function Invoke-Isql($d, [string[]]$statements) {
    Set-FirebirdEnv $d
    $sqlFile = Join-Path $d.Tmp ("deploy-{0}.sql" -f ([guid]::NewGuid().ToString("N").Substring(0, 8)))
    Set-Content -Path $sqlFile -Value $statements -Encoding ASCII
    $env:ISC_USER = "SYSDBA"
    $env:ISC_PASSWORD = "masterkey"
    $isql = Join-Path $d.Server "isql.exe"
    $out = cmd /c "`"$isql`" -q -m -i `"$sqlFile`" 2>&1" | Out-String
    Remove-Item Env:ISC_USER, Env:ISC_PASSWORD
    Remove-Item $sqlFile -Force
    return $out
}

# Reads the fields of a license file DbCrypt.conf.
function Get-LicenseInfo([string]$file) {
    $info = @{}
    foreach ($line in Get-Content $file) {
        if ($line -match '^\s*(\w+)\s*=\s*(.*)$') { $info[$Matches[1]] = $Matches[2].Trim() }
    }
    $expire = $null
    if ($info.ContainsKey("ExpireDate")) {
        $expire = [DateTimeOffset]::FromUnixTimeSeconds([long]$info["ExpireDate"]).LocalDateTime
    }
    return [pscustomobject]@{ RegName = $info["RegName"]; Expire = $expire }
}

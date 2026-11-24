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
        Build       = Join-Path $WorkDir "build"
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
    $part = "$file.part"
    Write-Host "   download: $url"
    # cc.ib-aid.com needs TLS 1.3. Windows PowerShell 5.1 uses it only when it is turned on here.
    $protocols = [Net.SecurityProtocolType]::Tls12
    if ([enum]::GetNames([Net.SecurityProtocolType]) -contains 'Tls13') {
        $protocols = $protocols -bor [Net.SecurityProtocolType]::Tls13
    }
    [Net.ServicePointManager]::SecurityProtocol = $protocols
    try {
        Invoke-WebRequest -Uri $url -OutFile $part -UseBasicParsing
    } catch {
        # Second way: curl.exe is a part of Windows 10 and 11.
        $curl = Join-Path $env:SystemRoot "System32\curl.exe"
        if (-not (Test-Path $curl)) { throw }
        Write-Host "   Invoke-WebRequest failed ($($_.Exception.Message)); trying curl.exe"
        & $curl -sS -L --fail -o $part $url
        if ($LASTEXITCODE -ne 0) { Fail "Cannot download $url" }
    }
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

$script:KeySourceFolders = @{ a = "a-static"; b = "b-file"; c = "c-provider"; d = "d-rest"; probe = "probe" }

# Copies one KeySource library to an application folder and writes its settings.
function Install-KeySource($d, [string]$target, [string]$variant) {
    $dll = Join-Path $d.Build "keysource\$($script:KeySourceFolders[$variant])\KeySource.dll"
    if (-not (Test-Path $dll)) { Fail "$dll is not found. Run 30-build.ps1 first." }
    # The KeyHolder plugin looks for the library with the name KeySource next to fbclient.dll.
    Copy-Item $dll (Join-Path $target "KeySource.dll") -Force
    $ini = @("[KeySource]", "Log=1")

    if ($variant -eq "b") {
        # The folder "keyfile" plays the role of a removable disk with the key.
        $keyDir = Join-Path $d.Root "keyfile"
        New-Item -ItemType Directory -Force $keyDir | Out-Null
        $keyLine = Get-Content $d.KeysFile | Where-Object { $_ -match '^\s*Key\s*=\s*Red\s' } | Select-Object -First 1
        Set-Content -Path (Join-Path $keyDir "employee.key") -Value $keyLine -Encoding ASCII
        $ini += "KeyFile=$(Join-Path $keyDir 'employee.key')"
    }
    if ($variant -eq "c") {
        $provider = Join-Path $d.Build "KeyProvider.exe"
        if (-not (Test-Path $provider)) { Fail "$provider is not found. Run 30-build.ps1 first." }
        $providerDir = Join-Path $d.Root "keyprovider"
        New-Item -ItemType Directory -Force $providerDir | Out-Null
        Copy-Item $provider $providerDir -Force
        Set-Content -Path (Join-Path $providerDir "KeyProvider.ini") -Encoding ASCII -Value @(
            "[KeyProvider]", "KeyName=Red", "KeepMinutes=0")
        $ini += "ProviderExe=$(Join-Path $providerDir 'KeyProvider.exe')"
        $ini += "TimeoutMs=120000"
    }
    if ($variant -eq "d") {
        $ini += "Url=http://localhost:8085/keys/Red"
        $ini += "Token=test-token"
        $ini += "TimeoutMs=5000"
        $ini += "CacheSeconds=300"
    }
    Set-Content -Path (Join-Path $target "KeySource.ini") -Value $ini -Encoding ASCII
}

# Copies the example application to its folder and writes its connection settings.
function Install-App($d, [string]$target, [string]$mode) {
    if ($mode -eq "remote") {
        $exe = "EmployeeRemote.exe"
        # The password in the file is for the demonstration only.
        $ini = @("[Connection]", "Host=localhost", "Port=$($d.Fb.Port)", "Database=crypt_employee",
                 "User=SYSDBA", "Password=masterkey")
    } else {
        $exe = "EmployeeEmbedded.exe"
        $ini = @("[Connection]", "Database=EMPLOYEE.FDB", "User=SYSDBA")
    }
    $source = Join-Path $d.Build $exe
    if (-not (Test-Path $source)) { Fail "$source is not found. Run 30-build.ps1 first." }
    Copy-Item $source $target -Force
    Set-Content -Path (Join-Path $target "EmployeeApp.ini") -Value $ini -Encoding ASCII

    if (($mode -eq "embedded") -and ($d.Version -eq '3')) {
        # Firebird 3.0: the embedded engine and the server of the example must use the same lock folder
        # when they work at the same time.
        Set-Content -Path (Join-Path $target "EmployeeEmbedded.cmd") -Encoding ASCII -Value @(
            "@echo off",
            "rem Firebird 3.0: the same lock folder as the server of the example.",
            "set FIREBIRD_LOCK=$(Join-Path $d.Root 'lock')",
            "start `"`" `"%~dp0EmployeeEmbedded.exe`" %*")
    }
}

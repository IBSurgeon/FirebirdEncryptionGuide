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
        # The key line of the encrypted database. The script 20 writes it, the scripts 40 and 41 read it.
        DbKey       = Join-Path $root "db-key.conf"
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

# Writes a text file in UTF-8 without the byte order mark. A pass phrase can have national letters.
function Write-Utf8([string]$file, [string[]]$lines) {
    [IO.File]::WriteAllLines($file, $lines, (New-Object Text.UTF8Encoding($false)))
}

# Checks a pass phrase. The plugin reads the line of the key as a Firebird configuration file,
# so some characters change the phrase or break the line.
function Test-Passphrase([string]$phrase) {
    if ($phrase -eq "") { Fail "The pass phrase is empty." }
    if ($phrase -ne $phrase.Trim()) { Fail "The pass phrase must not start or end with a space." }
    # Braces: the plugin takes no key and reports no error. The database stays not encrypted.
    if ($phrase -match '[#"{}]' -or $phrase.Contains('$(')) {
        Fail 'The pass phrase must not contain the characters  #  "  {  }  and the pair $(.'
    }
    if ($phrase -match '[\x00-\x1F]') { Fail "The pass phrase must not contain control characters." }
    if ($phrase.Length -lt 12) { Write-Host "   WARNING: the pass phrase is short. A short phrase can be guessed." -ForegroundColor Yellow }
}

# Returns the key of the encrypted database of the example:
#   Line   "Key=<name> 0x..," or "Password=<name> <phrase>"
#   Kind   Key or Password
#   Name   name of the key
#   Value  bytes of the key or the pass phrase: the text that a person types into a key window
function Get-DbKey($d) {
    if (-not (Test-Path $d.DbKey)) { Fail "$($d.DbKey) is not found. Run 20-encrypt-database.ps1 first." }
    foreach ($line in [IO.File]::ReadAllLines($d.DbKey, [Text.Encoding]::UTF8)) {
        if ($line -match '^\s*(Key|Password)\s*=\s*(\S+)\s+(.*\S)\s*$') {
            return [pscustomobject]@{ Line = $line.Trim(); Kind = $Matches[1]; Name = $Matches[2]; Value = $Matches[3] }
        }
    }
    Fail "No line 'Key=' or 'Password=' in $($d.DbKey)."
}

# True: the database is encrypted with the public test key Red. The library of the variant "a" has this key in its code.
function Test-RedKey($d) {
    $red = (Get-Content $d.KeysFile | Where-Object { $_ -match '^\s*Key\s*=\s*Red\s' } | Select-Object -First 1) -replace '^\s*Key\s*=\s*Red\s+', ''
    $key = Get-DbKey $d
    return ($key.Kind -eq 'Key') -and ($key.Name -eq 'Red') -and ($key.Value -eq $red.Trim())
}

$script:KeySourceFolders = @{ a = "a-static"; b = "b-file"; c = "c-provider"; d = "d-rest"; probe = "probe" }

# Copies one KeySource library to an application folder and writes its settings.
function Install-KeySource($d, [string]$target, [string]$variant) {
    $dll = Join-Path $d.Build "keysource\$($script:KeySourceFolders[$variant])\KeySource.dll"
    if (-not (Test-Path $dll)) { Fail "$dll is not found. Run 30-build.ps1 first." }
    $key = Get-DbKey $d
    if (($variant -eq "a") -and (-not (Test-RedKey $d))) {
        Fail ("The library of the variant 'a' has the test key Red in its code, but the database uses another key. " +
              "Use -KeySource b, c or d. Or write your line of the key to keysource\a-static\KeySource.lpr and build the library.")
    }
    # The KeyHolder plugin looks for the library with the name KeySource next to fbclient.dll.
    Copy-Item $dll (Join-Path $target "KeySource.dll") -Force
    $ini = @("[KeySource]", "Log=1")

    if ($variant -eq "b") {
        # The folder "keyfile" plays the role of a removable disk with the key.
        $keyDir = Join-Path $d.Root "keyfile"
        New-Item -ItemType Directory -Force $keyDir | Out-Null
        Write-Utf8 (Join-Path $keyDir "employee.key") @($key.Line)
        $ini += "KeyFile=$(Join-Path $keyDir 'employee.key')"
    }
    if ($variant -eq "c") {
        $provider = Join-Path $d.Build "KeyProvider.exe"
        if (-not (Test-Path $provider)) { Fail "$provider is not found. Run 30-build.ps1 first." }
        $providerDir = Join-Path $d.Root "keyprovider"
        New-Item -ItemType Directory -Force $providerDir | Out-Null
        Copy-Item $provider $providerDir -Force
        # The key provider knows only the name of the key. A person types the key or the pass phrase.
        Set-Content -Path (Join-Path $providerDir "KeyProvider.ini") -Encoding ASCII -Value @(
            "[KeyProvider]", "KeyName=$($key.Name)", "KeepMinutes=0")
        $ini += "ProviderExe=$(Join-Path $providerDir 'KeyProvider.exe')"
        $ini += "TimeoutMs=120000"
    }
    if ($variant -eq "d") {
        $ini += "Url=http://localhost:8085/keys/$($key.Name)"
        $ini += "Token=test-token"
        $ini += "TimeoutMs=5000"
        $ini += "CacheSeconds=300"
    }
    if ($variant -eq "probe") {
        # The diagnostic library returns the key of the database.
        $ini += "KeysFile=$($d.DbKey)"
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

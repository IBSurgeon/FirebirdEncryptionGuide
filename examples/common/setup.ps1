<#
.SYNOPSIS
  Creates a private Firebird test server with encrypted databases for the examples.

.DESCRIPTION
  The script copies a Firebird server with the IBSurgeon encryption plugin to a work
  folder, creates three databases and starts the server on its own port.
  Installed Firebird services are not changed.

    crypt_red    encrypted with the key Red
    crypt_green  encrypted with the key Green
    plain        not encrypted
    work         not encrypted; the examples encrypt and decrypt it

  After the setup the server has NO keys. Each connection must send the key.

.EXAMPLE
  .\setup.ps1 -FirebirdDir C:\HQbird\Firebird50 -LicenseFile C:\lic\DbCrypt.conf

.EXAMPLE
  .\setup.ps1 -FirebirdDir C:\HQbird\Firebird50 -LicenseFile C:\lic\DbCrypt.conf -ClientDir32 C:\FB50x32
#>
param(
    [Parameter(Mandatory = $true)][string]$FirebirdDir,
    [Parameter(Mandatory = $true)][string]$LicenseFile,
    [string]$OpenSslDll = "",
    # Folder with libcrypto-*.dll for the client folder. Default: the files in $FirebirdDir.
    [string]$OpenSslDir = "",
    # Folder with the 32-bit client files (fbclient.dll, fbcrypt.dll, plugins\).
    # The script makes the folder client32 and the variable FBCRYPT_CLIENT32.
    [string]$ClientDir32 = "",
    [string]$OpenSslDir32 = "",
    [string]$WorkDir = (Join-Path $env:TEMP "fbcrypt-examples"),
    [int]$Port = 3070
)

$ErrorActionPreference = "Stop"

function Fail([string]$msg) {
    Write-Host "ERROR: $msg" -ForegroundColor Red
    exit 1
}

function Step([string]$msg) {
    Write-Host "== $msg"
}

# Machine type of a PE file: 0x8664 for x64, 0x14c for x86.
function Get-PeMachine([string]$file) {
    $bytes = [System.IO.File]::ReadAllBytes($file)
    $peOffset = [System.BitConverter]::ToInt32($bytes, 0x3c)
    return [System.BitConverter]::ToUInt16($bytes, $peOffset + 4)
}

# Names of the OpenSSL libraries that fbcrypt.dll loads by name. The names are in the library itself.
function Get-FbCryptOpenSslNames([string]$library) {
    $text = [System.Text.Encoding]::GetEncoding(28591).GetString([System.IO.File]::ReadAllBytes($library))
    $names = @()
    foreach ($m in [regex]::Matches($text, 'libcrypto-[0-9A-Za-z_-]+\.dll')) {
        if ($names -notcontains $m.Value) { $names += $m.Value }
    }
    return ,$names
}

# fbcrypt.dll loads OpenSSL by name, and the name depends on the Firebird version and on
# the bitness. A server folder can have the same OpenSSL under another name
# (libcrypto-1_1.dll instead of libcrypto-1_1-x64.dll). Returns a table
# "name that fbcrypt.dll loads" -> "file to copy from". The table is empty when $source
# already has a library with a needed name.
function Find-ClientOpenSsl([string]$source, [string]$openSslDir) {
    $plan = @{}
    $wanted = Get-FbCryptOpenSslNames (Join-Path $source "fbcrypt.dll")
    if ($wanted.Count -eq 0) { return $plan }
    $inSource = @(Get-ChildItem -Path $source -Filter "libcrypto-*.dll" | ForEach-Object { $_.Name })
    foreach ($name in $wanted) {
        if ($inSource -contains $name) { return $plan }
    }
    # The same version of OpenSSL under another name: look in -OpenSslDir, or in the folder itself.
    # The library in -OpenSslDir can have the needed name too.
    $libDir = $source
    if ($openSslDir -ne "") { $libDir = (Resolve-Path $openSslDir).Path }
    $machine = Get-PeMachine (Join-Path $source "fbclient.dll")
    foreach ($name in $wanted) {
        if ($name -notmatch 'libcrypto-(\d+(?:_\d+)?)') { continue }
        $same = @(Get-ChildItem -Path $libDir -Filter "libcrypto-$($matches[1])*.dll")
        foreach ($lib in $same) {
            if ((Get-PeMachine $lib.FullName) -ne $machine) {
                Fail "$($lib.FullName) is not for the same bitness as fbclient.dll in $source."
            }
            $plan[$name] = $lib.FullName
            break
        }
    }
    if ($plan.Count -eq 0) {
        Fail "No OpenSSL library for fbcrypt.dll from $source. fbcrypt.dll looks for: $($wanted -join ', '). Use -OpenSslDir <folder with libcrypto-*.dll of the same bitness>."
    }
    return $plan
}

# ---------------------------------------------------------------- checks
$FirebirdDir = (Resolve-Path $FirebirdDir).Path
$required = @(
    "firebird.exe", "isql.exe", "gstat.exe", "gbak.exe", "fbclient.dll", "fbcrypt.dll",
    "plugins\dbcrypt.dll", "plugins\keyholder.dll", "plugins\keyholderstdin.dll"
)
foreach ($f in $required) {
    if (-not (Test-Path (Join-Path $FirebirdDir $f))) {
        Fail "File '$f' is not found in $FirebirdDir. Use a Firebird folder with the encryption plugin."
    }
}
if (-not (Test-Path $LicenseFile)) { Fail "License file is not found: $LicenseFile" }

$sslInDir = @(Get-ChildItem -Path $FirebirdDir -Filter "libcrypto-*.dll")
if (($sslInDir.Count -eq 0) -and ($OpenSslDll -eq "")) {
    Fail "No libcrypto-*.dll in $FirebirdDir. Use -OpenSslDll <path to libcrypto dll>."
}
if (($OpenSslDll -ne "") -and (-not (Test-Path $OpenSslDll))) { Fail "OpenSSL library is not found: $OpenSslDll" }
if (($OpenSslDir -ne "") -and (-not (Test-Path $OpenSslDir))) { Fail "Folder is not found: $OpenSslDir" }
if (($OpenSslDir32 -ne "") -and (-not (Test-Path $OpenSslDir32))) { Fail "Folder is not found: $OpenSslDir32" }
$client32 = ""
if ($ClientDir32 -ne "") {
    $ClientDir32 = (Resolve-Path $ClientDir32).Path
    $client32 = Join-Path $WorkDir "client32"
    foreach ($f in @("fbclient.dll", "fbcrypt.dll")) {
        if (-not (Test-Path (Join-Path $ClientDir32 $f))) { Fail "File '$f' is not found in $ClientDir32." }
    }
    if ((Get-PeMachine (Join-Path $ClientDir32 "fbclient.dll")) -ne 0x14c) {
        Fail "fbclient.dll in $ClientDir32 is not 32-bit. Use a folder with the 32-bit client files."
    }
}
# OpenSSL for the client folders: check before the server is copied and the databases are created.
$openSsl = Find-ClientOpenSsl $FirebirdDir $OpenSslDir
$openSsl32 = @{}
if ($ClientDir32 -ne "") { $openSsl32 = Find-ClientOpenSsl $ClientDir32 $OpenSslDir32 }

$server = Join-Path $WorkDir "server"
$client = Join-Path $WorkDir "client"
$dbDir = Join-Path $WorkDir "db"
$tmpDir = Join-Path $WorkDir "tmp"
if (Test-Path $server) { Fail "Folder $server exists. Run cleanup.ps1 first." }

$keysFile = Join-Path $PSScriptRoot "test-keys.conf"
$keyLines = @(Get-Content $keysFile | Where-Object { $_ -match '^\s*Key\s*=' })

# ---------------------------------------------------------------- server copy
Step "Copy the server to $server"
New-Item -ItemType Directory -Force $WorkDir, $dbDir, $tmpDir | Out-Null
& robocopy $FirebirdDir $server /E /XF *.pdb /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { Fail "robocopy failed with code $LASTEXITCODE" }
Copy-Item $LicenseFile (Join-Path $server "plugins\DbCrypt.conf") -Force

# Major version of Firebird: gbak of Firebird 3.0 has other switches than 4.0 and 5.0.
$fbMajor = [System.Diagnostics.FileVersionInfo]::GetVersionInfo((Join-Path $server "fbclient.dll")).FileMajorPart
if ($fbMajor -ge 5) {
    # Firebird 5.0: write logins with individual client keys to firebird.log (example clientkeygen).
    Add-Content -Path (Join-Path $server "plugins\DbCrypt.conf") -Value @("", "Logger = true") -Encoding ASCII
}
if ($OpenSslDll -ne "") { Copy-Item $OpenSslDll $server -Force }

$conf = @(
    "RemoteServicePort = $Port",
    "RemoteAuxPort = 0",
    "IpcName = FBCRYPT_EXAMPLES_$Port",
    "ServerMode = Super",
    "KeyHolderPlugin = KeyHolder",
    "WireCrypt = Required",
    "AuthServer = Srp256, Srp",
    "UserManager = Srp"
)
Set-Content -Path (Join-Path $server "firebird.conf") -Value $conf -Encoding ASCII

$aliases = @(
    "",
    "crypt_red = $dbDir\crypt_red.fdb",
    "crypt_green = $dbDir\crypt_green.fdb",
    "plain = $dbDir\plain.fdb",
    "work = $dbDir\work.fdb"
)
Add-Content -Path (Join-Path $server "databases.conf") -Value $aliases -Encoding ASCII

# Keys are on the server only while the databases are created.
Set-Content -Path (Join-Path $server "plugins\KeyHolder.conf") -Value $keyLines -Encoding ASCII

# ---------------------------------------------------------------- embedded isql
$script:sqlNo = 0
function Invoke-Isql([string[]]$statements) {
    # isql runs in embedded mode and reads the statements from a script file.
    $script:sqlNo++
    $sqlFile = Join-Path $tmpDir "setup-$($script:sqlNo).sql"
    Set-Content -Path $sqlFile -Value $statements -Encoding ASCII
    $env:ISC_USER = "SYSDBA"
    $env:ISC_PASSWORD = "masterkey"
    $env:FIREBIRD_TMP = $tmpDir
    $isql = Join-Path $server "isql.exe"
    $out = cmd /c "`"$isql`" -q -m -i `"$sqlFile`" 2>&1" | Out-String
    Remove-Item Env:ISC_USER, Env:ISC_PASSWORD
    return $out
}

# The encryption thread works only while a connection is open.
# This block keeps the connection open until MON$CRYPT_PAGE returns to 0 (60 seconds at most).
$waitForCrypt = @(
    "set term ^;",
    "execute block as",
    "  declare t0 timestamp;",
    "  declare pg bigint;",
    "begin",
    "  t0 = cast('now' as timestamp);",
    "  while (datediff(second from t0 to cast('now' as timestamp)) < 60) do",
    "  begin",
    "    in autonomous transaction do",
    "      select mon`$crypt_page from mon`$database into :pg;",
    "    if (pg = 0 and datediff(second from t0 to cast('now' as timestamp)) >= 2) then leave;",
    "  end",
    "end^",
    "set term ;^"
)

function Test-Encrypted([string]$dbFile) {
    $env:FIREBIRD_TMP = $tmpDir
    $gstat = Join-Path $server "gstat.exe"
    $out = cmd /c "`"$gstat`" -h `"$dbFile`" 2>&1" | Out-String
    $attr = ($out -split "`n" | Where-Object { $_ -match 'Attributes' }) -join " "
    return (($attr -match 'encrypted') -and ($attr -notmatch 'crypt process'))
}

Step "Create the user SYSDBA"
$out = Invoke-Isql @(
    "connect 'security.db';",
    "create or alter user SYSDBA password 'masterkey' using plugin Srp;",
    "commit;"
)
if ($out -match 'SQLSTATE') { Fail "Cannot create SYSDBA:`n$out" }

function New-TestDb([string]$name, [string]$key) {
    $file = Join-Path $dbDir "$name.fdb"
    $sql = @(
        "create database '$file' page_size 8192 default character set UTF8;",
        "create table demo (id integer not null primary key, note varchar(60));",
        "insert into demo values (1, 'Hello from $name');",
        "commit;"
    )
    if ($key -ne "") {
        $sql += "alter database encrypt with ""DbCrypt"" key $key;"
        $sql += "commit;"
        $sql += $waitForCrypt
    }
    $out = Invoke-Isql $sql
    if ($out -match 'SQLSTATE') { Fail "Cannot create $name`:`n$out" }
    if ($key -ne "") {
        if (-not (Test-Encrypted $file)) { Fail "Database $name is not encrypted. Output of isql:`n$out" }
        Write-Host "   $name`: encrypted with the key $key"
    } else {
        Write-Host "   $name`: not encrypted"
    }
}

Step "Create the databases"
New-TestDb "crypt_red" "Red"
New-TestDb "crypt_green" "Green"
New-TestDb "plain" ""
New-TestDb "work" ""

# The server keeps no keys. UnsafeClient lets Java, .NET and Python send the key as a static value.
Set-Content -Path (Join-Path $server "plugins\KeyHolder.conf") -Value @("UnsafeClient = true") -Encoding ASCII

# ---------------------------------------------------------------- client folders
# Copies the client libraries, the tools and the key holder plugins from a server folder
# or from a folder with the 32-bit client files. OpenSSL is copied under the name
# that fbcrypt.dll loads (the table comes from Find-ClientOpenSsl).
function New-ClientFolder([string]$source, [string]$target, [hashtable]$openSsl) {
    New-Item -ItemType Directory -Force $target, (Join-Path $target "plugins") | Out-Null
    $clientFiles = @(
        "fbclient.dll", "fbcrypt.dll", "firebird.msg", "ib_util.dll", "zlib1.dll",
        "msvcp*.dll", "vcruntime*.dll", "libcrypto-*.dll", "icu*.dll", "icudt*.dat",
        "gbak.exe", "isql.exe", "gfix.exe", "gstat.exe", "nbackup.exe"
    )
    foreach ($pattern in $clientFiles) {
        Get-ChildItem -Path $source -Filter $pattern | Copy-Item -Destination $target -Force
    }
    $clientPlugins = @("keyholder.dll", "keyholderstdin.dll", "dbcrypt.dll", "DbCrypt.conf", "chacha.dll")
    foreach ($f in $clientPlugins) {
        $src = Join-Path $source "plugins\$f"
        if (Test-Path $src) { Copy-Item $src (Join-Path $target "plugins") -Force }
    }
    # Client configuration: no KeyHolderPlugin (new-keysource-client.ps1 makes a folder with it).
    # "Providers = Remote": the client does not try other Firebird servers of this computer,
    # so an error message always comes from the test server.
    Set-Content -Path (Join-Path $target "firebird.conf") -Value @("Providers = Remote") -Encoding ASCII

    foreach ($name in @($openSsl.Keys)) {
        $libName = Split-Path $openSsl[$name] -Leaf
        Copy-Item $openSsl[$name] (Join-Path $target $name)
        if ($libName -eq $name) {
            Write-Host "   OpenSSL: $name is copied from $(Split-Path $openSsl[$name] -Parent)."
        } else {
            Write-Host "   OpenSSL: $libName is copied as $name. fbcrypt.dll loads the library by this name."
        }
    }
}

Step "Create the client folder $client"
New-ClientFolder $server $client $openSsl

if ($ClientDir32 -ne "") {
    Step "Create the 32-bit client folder $client32"
    New-ClientFolder $ClientDir32 $client32 $openSsl32
    # The license file is the same for the 32-bit and the 64-bit plugins.
    $conf = Join-Path $client32 "plugins\DbCrypt.conf"
    if (-not (Test-Path $conf)) { Copy-Item (Join-Path $server "plugins\DbCrypt.conf") $conf }
}

# ---------------------------------------------------------------- environment file
$envFile = Join-Path $WorkDir "test-env.ps1"
$envLines = @(
    "# Dot-source this file before you run an example:  . `"$envFile`"",
    "`$env:FBCRYPT_HOST = 'localhost'",
    "`$env:FBCRYPT_PORT = '$Port'",
    "`$env:FBCRYPT_USER = 'SYSDBA'",
    "`$env:FBCRYPT_PASSWORD = 'masterkey'",
    "`$env:FBCRYPT_CLIENT = '$client'",
    "`$env:FBCRYPT_CLIENT32 = '$client32'",
    "`$env:FBCRYPT_KEYS = '$keysFile'",
    "`$env:FBCRYPT_WORK = '$WorkDir'",
    "`$env:FBCRYPT_FB_MAJOR = '$fbMajor'"
)
Set-Content -Path $envFile -Value $envLines -Encoding ASCII

# ---------------------------------------------------------------- start
& (Join-Path $PSScriptRoot "start-server.ps1") -WorkDir $WorkDir -Port $Port
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host ""
Write-Host "Done. Databases: localhost/$Port`:crypt_red, crypt_green, plain, work"
if ($client32 -ne "") { Write-Host "32-bit client folder (FBCRYPT_CLIENT32): $client32" }
Write-Host "Next step:  . `"$envFile`""

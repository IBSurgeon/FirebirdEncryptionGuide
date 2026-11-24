<#
.SYNOPSIS
  Makes two encrypted copies of the database employee: one for the server, one for embedded.

.DESCRIPTION
  Stop the server before you run the script. The script works in embedded mode.

    1. Copies employee.fdb from the Firebird examples to work\fb<N>\db\EMPLOYEE.FDB.
    2. Writes the line of the key to a temporary file plugins\KeyHolder.conf of the server folder.
    3. Encrypts the database and waits until the encryption is complete.
    4. Deletes plugins\KeyHolder.conf. The server keeps no keys.
    5. Copies the encrypted file to EMPLOYEE-EMBEDDED.FDB.
    6. Adds the alias crypt_employee to databases.conf.
    7. Writes the line of the key to work\fb<N>\db-key.conf for the scripts 40 and 41.

  The key:

    no parameters          the public test key Red from examples\common\test-keys.conf
    -Passphrase "<text>"   a pass phrase. The plugin computes the key from the phrase
    -AskPassphrase         the script asks for the pass phrase; the phrase is not shown
    -KeyName <name>        name of the key (default: Red)

  The file db-key.conf is a part of the example: it lets the scripts set up the variants
  of KeySource. With real data keep the key or the pass phrase only in your key storage.

.EXAMPLE
  .\20-encrypt-database.ps1 -Version 5
.EXAMPLE
  .\20-encrypt-database.ps1 -Version 5 -KeyName Main -Passphrase "my long pass phrase 2026"
.EXAMPLE
  .\20-encrypt-database.ps1 -Version 5 -AskPassphrase
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet('3', '4', '5')][string]$Version,
    [string]$WorkDir = "",
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_]*$')][string]$KeyName = "Red",
    [string]$Passphrase = "",
    [switch]$AskPassphrase
)
. (Join-Path $PSScriptRoot "common.ps1")
$d = Get-Deploy $Version $WorkDir

if (-not (Test-Path (Join-Path $d.Server "isql.exe"))) { Fail "$($d.Server) is not found. Run 10-install-server.ps1 first." }
if (Test-Port $d.Fb.Port) {
    Fail "Port $($d.Fb.Port) is in use. Stop the server of the example (12-stop-server.ps1). If another program uses the port, change the port in versions.psd1."
}

$db = Join-Path $d.Db "EMPLOYEE.FDB"
$dbEmbedded = Join-Path $d.Db "EMPLOYEE-EMBEDDED.FDB"
if (Test-Path $db) { Fail "$db exists. Run cleanup.ps1 first." }

if ($AskPassphrase) {
    $secure = Read-Host "Pass phrase for the key $KeyName" -AsSecureString
    $Passphrase = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
}
if ($AskPassphrase -or ($Passphrase -ne "")) {
    Test-Passphrase $Passphrase
    $keyLine = "Password=$KeyName $Passphrase"
    $keyKind = "a pass phrase"
} else {
    $keyLine = Get-Content $d.KeysFile | Where-Object { $_ -match "^\s*Key\s*=\s*$KeyName\s" } | Select-Object -First 1
    if ($null -eq $keyLine) { Fail "Key '$KeyName' is not found in $($d.KeysFile)." }
    $keyLine = $keyLine.Trim()
    $keyKind = "the test key from $($d.KeysFile)"
}

Step "Copy employee.fdb to $db"
$source = Get-ChildItem (Join-Path $d.Server "examples\empbuild") -Filter "employee.fdb" | Select-Object -First 1
Copy-Item $source.FullName $db

# The server folder has no KeyHolder.conf. The file lives only while the script encrypts the database.
$holderConf = Join-Path $d.Server "plugins\KeyHolder.conf"
if (Test-Path $holderConf) { Fail "$holderConf exists. The server of the example must have no such file. Delete it and run the script again." }
$encrypted = $false
try {
    Step "Encrypt the database: key name $KeyName, $keyKind"
    Write-Utf8 $holderConf @($keyLine)
    # The encryption thread works only while a connection is open.
    # The block keeps the connection open until MON$CRYPT_PAGE returns to 0 (120 seconds at most).
    $out = Invoke-Isql $d @(
        "connect '$db';",
        "alter database encrypt with ""DbCrypt"" key $KeyName;",
        "commit;",
        "set term ^;",
        "execute block as",
        "  declare t0 timestamp;",
        "  declare pg bigint;",
        "begin",
        "  t0 = cast('now' as timestamp);",
        "  while (datediff(second from t0 to cast('now' as timestamp)) < 120) do",
        "  begin",
        "    in autonomous transaction do",
        "      select mon`$crypt_page from mon`$database into :pg;",
        "    if (pg = 0 and datediff(second from t0 to cast('now' as timestamp)) >= 2) then leave;",
        "  end",
        "end^",
        "set term ;^"
    )
    if ($out -match 'SQLSTATE') { Fail "Cannot encrypt the database:`n$out" }

    Set-FirebirdEnv $d
    $gstat = Join-Path $d.Server "gstat.exe"
    $header = cmd /c "`"$gstat`" -h `"$db`" 2>&1" | Out-String
    $attr = ($header -split "`n" | Where-Object { $_ -match 'Attributes' }) -join " "
    if (($attr -notmatch 'encrypted') -or ($attr -match 'crypt process')) {
        Fail "The database is not encrypted. Header attributes: $attr`n$out"
    }
    Write-Host "   $($attr.Trim())"
    $encrypted = $true
} finally {
    # Remove the key from the server.
    Remove-Item $holderConf -Force -ErrorAction SilentlyContinue
    # After an error remove the copy that is not encrypted. The script can run again.
    if (-not $encrypted) { Remove-Item $db -Force -ErrorAction SilentlyContinue }
}

Step "Copy the encrypted database to $dbEmbedded"
Copy-Item $db $dbEmbedded

$aliases = Join-Path $d.Server "databases.conf"
if (-not (Select-String -Path $aliases -Pattern '^\s*crypt_employee\s*=' -Quiet)) {
    Add-Content -Path $aliases -Encoding ASCII -Value @("", "crypt_employee = $db")
}

# The scripts 40 and 41 read this file. See the description of the script.
Write-Utf8 $d.DbKey @(
    "# The key of the encrypted database of the example. Written by 20-encrypt-database.ps1.",
    "# With real data do not keep this line next to the server.",
    $keyLine
)
Write-Host "Done. Server database: localhost/$($d.Fb.Port):crypt_employee   key line: $($d.DbKey)"

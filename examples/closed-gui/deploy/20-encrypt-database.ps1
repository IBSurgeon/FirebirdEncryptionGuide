<#
.SYNOPSIS
  Makes two encrypted copies of the database employee: one for the server, one for embedded.

.DESCRIPTION
  Stop the server before you run the script. The script works in embedded mode.

    1. Copies employee.fdb from the Firebird examples to work\fb<N>\db\EMPLOYEE.FDB.
    2. Writes the test key Red to plugins\KeyHolder.conf of the server folder.
    3. Encrypts the database and waits until the encryption is complete.
    4. Removes the key from KeyHolder.conf. The server keeps no keys.
    5. Copies the encrypted file to EMPLOYEE-EMBEDDED.FDB.
    6. Adds the alias crypt_employee to databases.conf.

  The key Red is a public test key. Do not use it for real data.

.EXAMPLE
  .\20-encrypt-database.ps1 -Version 5
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet('3', '4', '5')][string]$Version,
    [string]$WorkDir = "",
    [string]$KeyName = "Red"
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

$keyLine = Get-Content $d.KeysFile | Where-Object { $_ -match "^\s*Key\s*=\s*$KeyName\s" } | Select-Object -First 1
if ($null -eq $keyLine) { Fail "Key '$KeyName' is not found in $($d.KeysFile)." }

Step "Copy employee.fdb to $db"
$source = Get-ChildItem (Join-Path $d.Server "examples\empbuild") -Filter "employee.fdb" | Select-Object -First 1
Copy-Item $source.FullName $db

$holderConf = Join-Path $d.Server "plugins\KeyHolder.conf"
$holderSaved = Get-Content $holderConf
try {
    Step "Encrypt the database with the key $KeyName"
    Set-Content -Path $holderConf -Value $keyLine -Encoding ASCII
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
} finally {
    # Remove the key from the server.
    Set-Content -Path $holderConf -Value $holderSaved -Encoding ASCII
}

Step "Copy the encrypted database to $dbEmbedded"
Copy-Item $db $dbEmbedded

$aliases = Join-Path $d.Server "databases.conf"
if (-not (Select-String -Path $aliases -Pattern '^\s*crypt_employee\s*=' -Quiet)) {
    Add-Content -Path $aliases -Encoding ASCII -Value @("", "crypt_employee = $db")
}
Write-Host "Done. Server database: localhost/$($d.Fb.Port):crypt_employee"

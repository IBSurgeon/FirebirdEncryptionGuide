<#
.SYNOPSIS
  Makes an encrypted backup of the encrypted database and checks it with a test restore.

.DESCRIPTION
  The server of the example must be running (11-start-server.ps1).

    1. Makes the folder work\fb<N>\backup-tools: gbak and the client files of the plugin archive,
       the plugins KeyHolder and DbCrypt, the license and one of the KeySource libraries.
       gbak encrypts the backup file itself, so its folder needs DbCrypt and the license.
    2. Runs gbak -b. The file goes to work\fb<N>\backup\employee-<date>-<time>.fbk.
         Firebird 4.0, 5.0:  gbak -b -KEYHOLDER KeyHolder ...   without the switch the file is NOT encrypted
         Firebird 3.0:       gbak -b ...                        KeyHolderPlugin in firebird.conf is enough
    3. Checks that the file has no readable names of tables.
    4. Restores the file to work\fb<N>\db\RESTORE-TEST.FDB, checks that the new database is
       encrypted and reads a table. -NoRestore skips this step.

  The key comes from KeySource.dll, the same way as for the application. No key is in the command line.
  -KeySource a, b, c or d selects the library (default: b, the key in a file).

.EXAMPLE
  .\50-backup.ps1 -Version 5
.EXAMPLE
  .\50-backup.ps1 -Version 3 -KeySource c -NoRestore
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet('3', '4', '5')][string]$Version,
    [ValidateSet('a', 'b', 'c', 'd')][string]$KeySource = 'b',
    [string]$WorkDir = "",
    [switch]$NoRestore
)
. (Join-Path $PSScriptRoot "common.ps1")
$d = Get-Deploy $Version $WorkDir
$client = Join-Path $d.PluginDir "$($d.Plugin.Folder)\Client\64bit"
$tools = Join-Path $d.Root "backup-tools"
$backupDir = Join-Path $d.Root "backup"
$backup = Join-Path $backupDir ("employee-{0:yyyyMMdd-HHmmss}.fbk" -f (Get-Date))
$database = "localhost/$($d.Fb.Port):crypt_employee"

if (-not (Test-Path $client)) { Fail "$client is not found. Run 10-install-server.ps1 first." }
if (-not (Test-Port $d.Fb.Port)) { Fail "The server of the example is not running. Run: .\11-start-server.ps1 -Version $Version" }

# Runs a tool of the backup folder. The user name and the password go through the environment.
function Invoke-Tool([string]$exe, [string]$arguments) {
    Remove-Item Env:FIREBIRD -ErrorAction SilentlyContinue
    $env:ISC_USER = "SYSDBA"
    $env:ISC_PASSWORD = "masterkey"
    $text = cmd /c "`"$(Join-Path $tools $exe)`" $arguments 2>&1" | Out-String
    $code = $LASTEXITCODE
    Remove-Item Env:ISC_USER, Env:ISC_PASSWORD
    return [pscustomobject]@{ Code = $code; Text = $text.Trim() }
}

Step "Make the folder of the backup tools $tools"
if (Test-Path $tools) { Remove-Item $tools -Recurse -Force }
New-Item -ItemType Directory -Force $tools, (Join-Path $tools "plugins"), $backupDir | Out-Null
Get-ChildItem $client -File | Copy-Item -Destination $tools
# KeyHolder gives the key. DbCrypt with the license encrypts the backup file inside gbak.
Copy-Item (Join-Path $client "plugins\keyholder.dll"), (Join-Path $client "plugins\dbcrypt.dll") (Join-Path $tools "plugins")
Copy-Item $d.License (Join-Path $tools "plugins\DbCrypt.conf")
Install-KeySource $d $tools $KeySource
Set-Content -Path (Join-Path $tools "firebird.conf") -Encoding ASCII -Value @(
    "Providers = Remote",
    "KeyHolderPlugin = KeyHolder"
)

# Firebird 4.0 and 5.0: only this switch turns on the encryption of the backup file.
$keySwitch = ""
if ($Version -ne '3') { $keySwitch = "-KEYHOLDER KeyHolder" }

Step "Backup: gbak -b $keySwitch $database"
$r = Invoke-Tool "gbak.exe" "-b $keySwitch $database `"$backup`""
if (($r.Code -ne 0) -or (-not (Test-Path $backup))) { Fail "gbak failed:`n$($r.Text)" }

# A backup that is not encrypted has the names of the tables as plain text.
$stream = [IO.File]::OpenRead($backup)
$buffer = New-Object byte[] ([Math]::Min($stream.Length, 4MB))
$null = $stream.Read($buffer, 0, $buffer.Length)
$stream.Close()
if ([Text.Encoding]::ASCII.GetString($buffer).Contains("CUSTOMER")) {
    Fail "The backup file $backup is NOT encrypted: the names of the tables are readable."
}
Write-Host ("   {0}: {1} bytes, no readable names of tables" -f $backup, (Get-Item $backup).Length)

if (-not $NoRestore) {
    $restored = Join-Path $d.Db "RESTORE-TEST.FDB"
    Step "Test restore: gbak -rep $keySwitch to $restored"
    $r = Invoke-Tool "gbak.exe" "-rep $keySwitch `"$backup`" `"localhost/$($d.Fb.Port):$restored`""
    if ($r.Code -ne 0) { Fail "The restore failed:`n$($r.Text)" }

    Set-FirebirdEnv $d
    $header = cmd /c "`"$(Join-Path $d.Server 'gstat.exe')`" -h `"$restored`" 2>&1" | Out-String
    $attr = (($header -split "`n" | Where-Object { $_ -match 'Attributes' }) -join " ").Trim()
    if ($attr -notmatch 'encrypted') { Fail "The restored database is not encrypted. Header attributes: $attr" }
    Write-Host "   $($attr -replace '\s+', ' ')"

    $sql = Join-Path $tools "check.sql"
    Set-Content -Path $sql -Encoding ASCII -Value "set list on; select count(*) as customers from customer;"
    $r = Invoke-Tool "isql.exe" "-q -i `"$sql`" `"localhost/$($d.Fb.Port):$restored`""
    if ($r.Text -notmatch 'CUSTOMERS\s+15') { Fail "Cannot read the restored database:`n$($r.Text)" }
    Write-Host "   the restored database is readable: 15 rows in CUSTOMER"
}
Write-Host "Done. Encrypted backup: $backup"

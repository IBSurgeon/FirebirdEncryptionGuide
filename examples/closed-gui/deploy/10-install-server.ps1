<#
.SYNOPSIS
  Installs a private Firebird server with the encryption plugin into the work folder.

.DESCRIPTION
  The script uses the files downloaded by the scripts 01, 02 and 03. It downloads nothing.

    1. Unpacks the official Firebird archive to work\fb<N>\server.
    2. Copies the folder Server of the plugin archive over it.
    3. Copies the license to plugins\DbCrypt.conf.
    4. Adds the port and KeyHolderPlugin to firebird.conf.
    5. Creates the user SYSDBA (password masterkey).

  The server has no keys. Installed Firebird services are not changed.

.EXAMPLE
  .\10-install-server.ps1 -Version 5
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet('3', '4', '5')][string]$Version,
    [string]$WorkDir = ""
)
. (Join-Path $PSScriptRoot "common.ps1")
$d = Get-Deploy $Version $WorkDir

foreach ($f in $d.FirebirdZip, $d.PluginZip, $d.License) {
    if (-not (Test-Path $f)) { Fail "$f is not found. Run the scripts 01, 02 and 03 first." }
}
if (Test-Path $d.Server) { Fail "Folder $($d.Server) exists. Run cleanup.ps1 first." }

Step "Unpack Firebird $($d.Fb.Version) to $($d.Server)"
New-Item -ItemType Directory -Force $d.Root, $d.Db, $d.Tmp | Out-Null
Expand-Archive -Path $d.FirebirdZip -DestinationPath $d.Server

Step "Unpack the plugin archive to $($d.PluginDir)"
if (Test-Path $d.PluginDir) { Remove-Item $d.PluginDir -Recurse -Force }
Expand-Archive -Path $d.PluginZip -DestinationPath $d.PluginDir
$pluginRoot = Join-Path $d.PluginDir $d.Plugin.Folder

Step "Copy the server files of the plugin"
Copy-Item (Join-Path $pluginRoot "Server\*") $d.Server -Recurse -Force
Copy-Item $d.License (Join-Path $d.Server "plugins\DbCrypt.conf") -Force
Set-Content -Path (Join-Path $d.Server "plugins\KeyHolder.conf") -Encoding ASCII -Value @(
    "# The server keeps no keys. Each connection must send the key."
)

Step "Write firebird.conf: port $($d.Fb.Port)"
Add-Content -Path (Join-Path $d.Server "firebird.conf") -Encoding ASCII -Value @(
    "",
    "# ---- added by 10-install-server.ps1",
    "RemoteServicePort = $($d.Fb.Port)",
    "IpcName = FB_CLOSED_GUI_$Version",
    "KeyHolderPlugin = KeyHolder"
)

Step "Create the user SYSDBA"
$out = Invoke-Isql $d @(
    "connect 'security.db';",
    "create or alter user SYSDBA password 'masterkey' using plugin Srp;",
    "commit;"
)
if ($out -match 'SQLSTATE') { Fail "Cannot create SYSDBA:`n$out" }

Write-Host "Done. Next step: .\20-encrypt-database.ps1 -Version $Version"

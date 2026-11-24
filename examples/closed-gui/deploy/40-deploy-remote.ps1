<#
.SYNOPSIS
  Makes the workstation folder for the usual (network) connection.

.DESCRIPTION
  The script copies the client files of the plugin archive to work\fb<N>\remote,
  adds a KeySource library and turns on the client-side KeyHolder plugin.
  An application that loads fbclient.dll from this folder needs no code for the key.

.EXAMPLE
  .\40-deploy-remote.ps1 -Version 5 -KeySourceDll C:\build\KeySource.dll
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet('3', '4', '5')][string]$Version,
    [Parameter(Mandatory = $true)][string]$KeySourceDll,
    [string]$WorkDir = "",
    [string]$Folder = "remote"
)
. (Join-Path $PSScriptRoot "common.ps1")
$d = Get-Deploy $Version $WorkDir
$client = Join-Path $d.PluginDir "$($d.Plugin.Folder)\Client\64bit"
$target = Join-Path $d.Root $Folder

if (-not (Test-Path $client)) { Fail "$client is not found. Run 10-install-server.ps1 first." }
if (-not (Test-Path $KeySourceDll)) { Fail "Library is not found: $KeySourceDll" }

Step "Make the workstation folder $target"
if (Test-Path $target) { Remove-Item $target -Recurse -Force }
New-Item -ItemType Directory -Force $target, (Join-Path $target "plugins") | Out-Null

# Client library, messages, ICU, C++ runtime, OpenSSL and the command-line tools.
Get-ChildItem $client -File | Copy-Item -Destination $target
# The client needs only the key holder plugin. It needs no DbCrypt and no license.
Copy-Item (Join-Path $client "plugins\keyholder.dll") (Join-Path $target "plugins")
# The KeyHolder plugin looks for the library with the name KeySource next to fbclient.dll.
Copy-Item $KeySourceDll (Join-Path $target "KeySource.dll")

Set-Content -Path (Join-Path $target "firebird.conf") -Encoding ASCII -Value @(
    "# The client does not try other Firebird servers of this computer.",
    "Providers = Remote",
    "# The client-side KeyHolder takes the keys from KeySource.dll and sends them to the server.",
    "KeyHolderPlugin = KeyHolder"
)
Write-Host "Done. Database: localhost/$($d.Fb.Port):crypt_employee"

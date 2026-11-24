<#
.SYNOPSIS
  Makes the application folder for the embedded mode (no server).

.DESCRIPTION
  The script builds work\fb<N>\embedded from three sources:

    plugin archive, Client\64bit   fbclient.dll, messages, ICU, C++ runtime, OpenSSL, tools,
                                   plugins: DbCrypt, KeyHolder
    official Firebird              the engine plugin and the folder intl
    license                        plugins\DbCrypt.conf

  Then it adds a KeySource library and its own copy of the encrypted database.
  In the embedded mode the engine works inside the application, so the folder needs
  the DbCrypt plugin and the license. The key does not go through the network.

.EXAMPLE
  .\41-deploy-embedded.ps1 -Version 5 -KeySourceDll C:\build\KeySource.dll
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet('3', '4', '5')][string]$Version,
    [Parameter(Mandatory = $true)][string]$KeySourceDll,
    [string]$WorkDir = "",
    [string]$Folder = "embedded"
)
. (Join-Path $PSScriptRoot "common.ps1")
$d = Get-Deploy $Version $WorkDir
$client = Join-Path $d.PluginDir "$($d.Plugin.Folder)\Client\64bit"
$target = Join-Path $d.Root $Folder
$dbSource = Join-Path $d.Db "EMPLOYEE-EMBEDDED.FDB"
$engine = $d.Fb.Provider.ToLower() + ".dll"

if (-not (Test-Path $client)) { Fail "$client is not found. Run 10-install-server.ps1 first." }
if (-not (Test-Path $dbSource)) { Fail "$dbSource is not found. Run 20-encrypt-database.ps1 first." }
if (-not (Test-Path $KeySourceDll)) { Fail "Library is not found: $KeySourceDll" }

Step "Make the embedded folder $target"
if (Test-Path $target) { Remove-Item $target -Recurse -Force }
New-Item -ItemType Directory -Force $target, (Join-Path $target "plugins"), (Join-Path $target "intl") | Out-Null

# From the plugin archive: client library, messages, ICU, C++ runtime, OpenSSL, tools.
Get-ChildItem $client -File | Copy-Item -Destination $target
Copy-Item (Join-Path $client "plugins\keyholder.dll"), (Join-Path $client "plugins\dbcrypt.dll") (Join-Path $target "plugins")
# From the official Firebird: the engine and the character sets.
Copy-Item (Join-Path $d.Server "plugins\$engine") (Join-Path $target "plugins")
Copy-Item (Join-Path $d.Server "intl\*") (Join-Path $target "intl")
# The DbCrypt plugin works only with a license.
Copy-Item $d.License (Join-Path $target "plugins\DbCrypt.conf")
# The KeyHolder plugin of the engine looks for the library with the name KeySource next to fbclient.dll.
Copy-Item $KeySourceDll (Join-Path $target "KeySource.dll")
Copy-Item $dbSource (Join-Path $target "EMPLOYEE.FDB")

Set-Content -Path (Join-Path $target "firebird.conf") -Encoding ASCII -Value @(
    "# Embedded mode: only the engine, no network and no local server.",
    "Providers = $($d.Fb.Provider)",
    "# The KeyHolder plugin of the engine takes the keys from KeySource.dll.",
    "KeyHolderPlugin = KeyHolder"
)
Write-Host "Done. Database: $(Join-Path $target 'EMPLOYEE.FDB')"

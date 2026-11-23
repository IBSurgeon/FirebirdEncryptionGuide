<#
.SYNOPSIS
  Creates a client folder that sends keys from a KeySource library (key transfer method C).

.DESCRIPTION
  The script copies the client folder created by setup.ps1 to <WorkDir>\client-keysource,
  adds your KeySource library and turns on the client-side KeyHolder plugin.
  An application that loads fbclient from this folder needs no code for the key.

  Build the library first, for example from examples/keysource/cpp.

.EXAMPLE
  .\new-keysource-client.ps1 -KeySourceDll C:\build\KeySource.dll
#>
param(
    [Parameter(Mandatory = $true)][string]$KeySourceDll,
    [string]$WorkDir = (Join-Path $env:TEMP "fbcrypt-examples")
)

$ErrorActionPreference = "Stop"
$client = Join-Path $WorkDir "client"
$target = Join-Path $WorkDir "client-keysource"

if (-not (Test-Path (Join-Path $client "fbclient.dll"))) {
    Write-Host "ERROR: $client is not found. Run setup.ps1 first." -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $KeySourceDll)) {
    Write-Host "ERROR: library is not found: $KeySourceDll" -ForegroundColor Red
    exit 1
}

if (Test-Path $target) { Remove-Item $target -Recurse -Force }
Copy-Item $client $target -Recurse

# The KeyHolder plugin looks for the library with the name KeySource next to fbclient.
Copy-Item $KeySourceDll (Join-Path $target "KeySource.dll") -Force

# The client-side KeyHolder plugin takes the keys from KeySource and sends them
# to the server with the protected key exchange.
$conf = @(
    "Providers = Remote",
    "KeyHolderPlugin = KeyHolder"
)
Set-Content -Path (Join-Path $target "firebird.conf") -Value $conf -Encoding ASCII

Write-Host "== Client folder with KeySource: $target"

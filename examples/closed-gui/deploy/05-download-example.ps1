<#
.SYNOPSIS
  Downloads the ready programs and libraries of the example. Use it when you have no Lazarus.

.DESCRIPTION
  The archive closed-gui-win64.zip is in the releases of
  github.com/IBSurgeon/FirebirdEncryptionGuide. The script unpacks it to work\build.
  The archive contains the same files that 30-build.ps1 makes.

.EXAMPLE
  .\05-download-example.ps1
#>
param(
    [string]$WorkDir = "",
    [string]$Url = "https://github.com/IBSurgeon/FirebirdEncryptionGuide/releases/latest/download/closed-gui-win64.zip"
)
. (Join-Path $PSScriptRoot "common.ps1")
$d = Get-Deploy '5' $WorkDir
$zip = Join-Path $d.Downloads "closed-gui-win64.zip"

Step "Programs of the example"
Get-File $Url $zip
Write-Host ("   size: {0} bytes, SHA-256: {1}" -f (Get-Item $zip).Length, (Get-Sha256 $zip))
if (Test-Path $d.Build) { Remove-Item $d.Build -Recurse -Force }
Expand-Archive -Path $zip -DestinationPath $d.Build
if (-not (Test-Path (Join-Path $d.Build "EmployeeRemote.exe"))) { Fail "EmployeeRemote.exe is not found in $zip." }
Write-Host "Done. Programs and libraries: $($d.Build)"

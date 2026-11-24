<#
.SYNOPSIS
  Stops the server of the example and deletes its folder work\fb<N>.

.DESCRIPTION
  The downloaded archives (work\downloads) and the built programs (work\build) stay.
  Use -All to delete them too.

.EXAMPLE
  .\cleanup.ps1 -Version 5
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet('3', '4', '5')][string]$Version,
    [string]$WorkDir = "",
    [switch]$All
)
. (Join-Path $PSScriptRoot "common.ps1")
$d = Get-Deploy $Version $WorkDir

& (Join-Path $PSScriptRoot "12-stop-server.ps1") -Version $Version -WorkDir $d.WorkDir
# Programs of the example that still run from the folder of this version.
Get-Process KeyProvider, EmployeeRemote, EmployeeEmbedded -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -like (Join-Path $d.Root "*") } | Stop-Process -Force

if (Test-Path $d.Root) {
    Remove-Item $d.Root -Recurse -Force
    Write-Host "== Deleted: $($d.Root)"
}
if ($All) {
    foreach ($folder in $d.Build, $d.Downloads) {
        if (Test-Path $folder) {
            Remove-Item $folder -Recurse -Force
            Write-Host "== Deleted: $folder"
        }
    }
}

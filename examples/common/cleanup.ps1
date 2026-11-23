<#
.SYNOPSIS
  Stops the private test server and deletes the work folder of the examples.
#>
param(
    [string]$WorkDir = (Join-Path $env:TEMP "fbcrypt-examples")
)

& (Join-Path $PSScriptRoot "stop-server.ps1") -WorkDir $WorkDir

if (-not (Test-Path $WorkDir)) {
    Write-Host "== $WorkDir does not exist."
    exit 0
}
# Safety check: delete only a folder created by setup.ps1.
if (-not (Test-Path (Join-Path $WorkDir "server\firebird.exe"))) {
    Write-Host "ERROR: $WorkDir is not a work folder of setup.ps1. Nothing is deleted." -ForegroundColor Red
    exit 1
}
Start-Sleep -Seconds 1
Remove-Item -Path $WorkDir -Recurse -Force
Write-Host "== Deleted $WorkDir"

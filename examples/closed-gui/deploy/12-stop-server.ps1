<#
.SYNOPSIS
  Stops the private Firebird server started by 11-start-server.ps1.

.EXAMPLE
  .\12-stop-server.ps1 -Version 5
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet('3', '4', '5')][string]$Version,
    [string]$WorkDir = ""
)
. (Join-Path $PSScriptRoot "common.ps1")
$d = Get-Deploy $Version $WorkDir

if (-not (Test-Path $d.PidFile)) {
    Write-Host "== No server.pid in $($d.Root). Nothing to stop."
    exit 0
}
$serverPid = [int](Get-Content $d.PidFile | Select-Object -First 1)
$p = Get-Process -Id $serverPid -ErrorAction SilentlyContinue
# Stop the process only if it is the server from the work folder.
if (($null -ne $p) -and ($p.Path -like (Join-Path $d.Server "*"))) {
    Stop-Process -Id $serverPid -Force
    $p.WaitForExit(10000) | Out-Null
    Write-Host "== Firebird $Version is stopped: process $serverPid"
} else {
    Write-Host "== Process $serverPid is not the server of the example. Nothing to stop."
}
Remove-Item $d.PidFile -Force

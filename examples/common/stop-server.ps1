<#
.SYNOPSIS
  Stops the private test server started by setup.ps1 or start-server.ps1.
#>
param(
    [string]$WorkDir = (Join-Path $env:TEMP "fbcrypt-examples")
)

$pidFile = Join-Path $WorkDir "server.pid"
if (-not (Test-Path $pidFile)) {
    Write-Host "== No server.pid in $WorkDir. Nothing to stop."
    exit 0
}

$serverPid = [int](Get-Content $pidFile | Select-Object -First 1)
$p = Get-Process -Id $serverPid -ErrorAction SilentlyContinue
# Stop the process only if it is the test server from the work folder.
if (($null -ne $p) -and ($p.Path -like (Join-Path $WorkDir "server\*"))) {
    Stop-Process -Id $serverPid -Force
    $p.WaitForExit(10000) | Out-Null
    Write-Host "== Server is stopped: process $serverPid"
} else {
    Write-Host "== Process $serverPid is not the test server. Nothing to stop."
}
Remove-Item $pidFile -Force

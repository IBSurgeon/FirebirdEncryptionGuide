<#
.SYNOPSIS
  Starts the private Firebird server as an application. Administrator rights are not necessary.

.EXAMPLE
  .\11-start-server.ps1 -Version 5
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet('3', '4', '5')][string]$Version,
    [string]$WorkDir = ""
)
. (Join-Path $PSScriptRoot "common.ps1")
$d = Get-Deploy $Version $WorkDir
$port = $d.Fb.Port

if (-not (Test-Path (Join-Path $d.Server "firebird.exe"))) { Fail "$($d.Server) is not found. Run 10-install-server.ps1 first." }
if (Test-Port $port) { Fail "Port $port is in use. Stop the other server or change the port in versions.psd1." }

Set-FirebirdEnv $d
$p = Start-Process -FilePath (Join-Path $d.Server "firebird.exe") -ArgumentList "-a" `
    -WorkingDirectory $d.Server -WindowStyle Hidden -PassThru
Set-Content -Path $d.PidFile -Value $p.Id -Encoding ASCII

for ($i = 0; $i -lt 40; $i++) {
    if (Test-Port $port) {
        Write-Host "== Firebird $Version is started: port $port, process $($p.Id)"
        exit 0
    }
    Start-Sleep -Milliseconds 500
}
Fail "The server does not answer on port $port. See $($d.Server)\firebird.log"

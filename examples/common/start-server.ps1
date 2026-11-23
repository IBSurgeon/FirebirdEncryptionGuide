<#
.SYNOPSIS
  Starts the private test server created by setup.ps1.
#>
param(
    [string]$WorkDir = (Join-Path $env:TEMP "fbcrypt-examples"),
    [int]$Port = 3070
)

$ErrorActionPreference = "Stop"
$server = Join-Path $WorkDir "server"
$pidFile = Join-Path $WorkDir "server.pid"

if (-not (Test-Path (Join-Path $server "firebird.exe"))) {
    Write-Host "ERROR: $server is not found. Run setup.ps1 first." -ForegroundColor Red
    exit 1
}

function Test-Port([int]$port) {
    $c = New-Object System.Net.Sockets.TcpClient
    try { $c.Connect("127.0.0.1", $port); return $true } catch { return $false } finally { $c.Close() }
}

if (Test-Port $Port) {
    Write-Host "ERROR: port $Port is in use. Stop the other server or use another -Port in setup.ps1." -ForegroundColor Red
    exit 1
}

$env:FIREBIRD_TMP = Join-Path $WorkDir "tmp"
$p = Start-Process -FilePath (Join-Path $server "firebird.exe") -ArgumentList "-a" `
    -WorkingDirectory $server -WindowStyle Hidden -PassThru
Set-Content -Path $pidFile -Value $p.Id -Encoding ASCII

for ($i = 0; $i -lt 40; $i++) {
    if (Test-Port $Port) {
        Write-Host "== Server is started: port $Port, process $($p.Id)"
        exit 0
    }
    Start-Sleep -Milliseconds 500
}
Write-Host "ERROR: the server does not answer on port $Port. See $server\firebird.log" -ForegroundColor Red
exit 1

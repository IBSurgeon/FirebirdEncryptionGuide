<#
.SYNOPSIS
  Demo key service for the KeySource library "d-rest". For tests only.

.DESCRIPTION
  The script answers the request

      GET http://localhost:<Port>/keys/<key name>
      Authorization: Bearer <Token>

  with the line of the key from the file of keys (format of KeyHolder.conf).
  Each request is written to the console and to the log file.

  A real key service must have: HTTPS, a token for each workstation that you
  can cancel, a log of all requests, and protected storage of the keys.

.EXAMPLE
  .\key-server.ps1
.EXAMPLE
  .\key-server.ps1 -Port 8085 -Token my-token -KeysFile C:\keys\keys.conf
#>
param(
    [int]$Port = 8085,
    [string]$Token = "test-token",
    [string]$KeysFile = "",
    [string]$LogFile = ""
)
$ErrorActionPreference = "Stop"
if ($KeysFile -eq "") { $KeysFile = Join-Path $PSScriptRoot "..\..\common\test-keys.conf" }
if ($LogFile -eq "") { $LogFile = Join-Path $env:TEMP "key-server.log" }

# Key name -> line of the key.
$keys = @{}
foreach ($line in Get-Content $KeysFile) {
    if ($line -match '^\s*(Key|Password)\s*=\s*(\S+)\s') { $keys[$Matches[2]] = $line.Trim() }
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "Key service: http://localhost:$Port/keys/<name>   keys: $($keys.Keys -join ', ')   log: $LogFile"
Write-Host "Press Ctrl+C to stop."

function Send-Answer($context, [int]$status, [string]$text) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    $context.Response.StatusCode = $status
    $context.Response.ContentType = "text/plain; charset=utf-8"
    $context.Response.ContentLength64 = $bytes.Length
    $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $context.Response.Close()
}

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $path = $request.Url.AbsolutePath
        $status = 404
        $answer = "Not found`n"
        if ($request.Headers["Authorization"] -ne "Bearer $Token") {
            $status = 401
            $answer = "Wrong or missing token`n"
        } elseif (($request.HttpMethod -eq "GET") -and ($path -match '^/keys/([A-Za-z0-9_]+)$') -and $keys.ContainsKey($Matches[1])) {
            $status = 200
            $answer = $keys[$Matches[1]] + "`n"
        }
        Send-Answer $context $status $answer
        # The log has no key values.
        $logLine = "{0:yyyy-MM-dd HH:mm:ss} {1} {2} -> {3}  workstation: {4}" -f (Get-Date), $request.HttpMethod, $path, $status, $request.Headers["X-Workstation"]
        Write-Host $logLine
        Add-Content -Path $LogFile -Value $logLine -Encoding UTF8
    }
} finally {
    $listener.Stop()
}

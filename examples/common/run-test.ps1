<#
.SYNOPSIS
  Runs one example and compares its standard output with expected-output.txt.

.DESCRIPTION
  Each example has a small run-test.ps1 that calls this script.
  Run setup.ps1 and dot-source test-env.ps1 before the test.
  The script writes actual-output.txt and actual-errors.txt to the folder of the example.
#>
param(
    [Parameter(Mandatory = $true)][string]$ExampleDir,
    [Parameter(Mandatory = $true)][string]$Command,
    [string]$Build = ""
)

$name = Split-Path (Split-Path $ExampleDir -Parent) -Leaf
$name = "$name/" + (Split-Path $ExampleDir -Leaf)
$expectedFile = Join-Path $ExampleDir "expected-output.txt"
$actualFile = Join-Path $ExampleDir "actual-output.txt"
$errorFile = Join-Path $ExampleDir "actual-errors.txt"

if (-not $env:FBCRYPT_WORK) {
    Write-Host "ERROR: the environment is not set. Dot-source test-env.ps1 first." -ForegroundColor Red
    exit 2
}

Push-Location $ExampleDir
try {
    if ($Build -ne "") {
        cmd /c "$Build > build-output.txt 2>&1"
        if ($LASTEXITCODE -ne 0) {
            Write-Host "FAIL $name (build failed, see build-output.txt)" -ForegroundColor Red
            exit 1
        }
        Remove-Item build-output.txt -ErrorAction SilentlyContinue
    }
    cmd /c "$Command > `"$actualFile`" 2> `"$errorFile`""
    $code = $LASTEXITCODE
} finally {
    Pop-Location
}

function Get-Lines([string]$file) {
    return @(Get-Content $file | ForEach-Object { $_.TrimEnd() } | Where-Object { $_ -ne "" })
}

$diff = Compare-Object (Get-Lines $expectedFile) (Get-Lines $actualFile) -SyncWindow 0
if (($code -eq 0) -and ($null -eq $diff)) {
    Write-Host "PASS $name" -ForegroundColor Green
    exit 0
}
Write-Host "FAIL $name (exit code $code)" -ForegroundColor Red
$diff | ForEach-Object { Write-Host ("  " + $_.SideIndicator + " " + $_.InputObject) }
Write-Host "  See $actualFile and $errorFile"
exit 1

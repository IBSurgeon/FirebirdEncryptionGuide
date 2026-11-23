<#
.SYNOPSIS
  Runs run-test.ps1 of all examples and prints a summary.
#>
$examples = Split-Path $PSScriptRoot -Parent
$tests = @(Get-ChildItem -Path $examples -Recurse -Filter "run-test.ps1" |
    Where-Object { $_.DirectoryName -ne $PSScriptRoot } | Sort-Object FullName)
$failed = 0
foreach ($t in $tests) {
    & $t.FullName
    if ($LASTEXITCODE -ne 0) { $failed++ }
}
Write-Host ""
Write-Host "Tests: $($tests.Count), failed: $failed"
if ($failed -gt 0) { exit 1 }
exit 0

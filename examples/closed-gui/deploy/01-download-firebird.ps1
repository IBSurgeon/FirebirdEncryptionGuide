<#
.SYNOPSIS
  Downloads the official Firebird archive from github.com/FirebirdSQL/firebird and checks its SHA-256.

.EXAMPLE
  .\01-download-firebird.ps1 -Version 5
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet('3', '4', '5')][string]$Version,
    [string]$WorkDir = ""
)
. (Join-Path $PSScriptRoot "common.ps1")
$d = Get-Deploy $Version $WorkDir

Step "Firebird $($d.Fb.Version)"
Get-File $d.Fb.Url $d.FirebirdZip
$sha = Get-Sha256 $d.FirebirdZip
if ($sha -ne $d.Fb.Sha256) {
    Fail "SHA-256 of $($d.FirebirdZip) is $sha. Expected: $($d.Fb.Sha256). Delete the file and run the script again."
}
Write-Host "   SHA-256 is correct"

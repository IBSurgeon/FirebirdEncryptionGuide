<#
.SYNOPSIS
  Downloads the archive of the IBSurgeon encryption plugin from cc.ib-aid.com.

.DESCRIPTION
  The archive contains the plugin files and a trial license. IBSurgeon replaces the archive
  every month. Use -Force to download a new archive when the trial license is expired.

.EXAMPLE
  .\02-download-plugin.ps1 -Version 5
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet('3', '4', '5')][string]$Version,
    [string]$WorkDir = "",
    [switch]$Force
)
. (Join-Path $PSScriptRoot "common.ps1")
$d = Get-Deploy $Version $WorkDir

Step "Encryption plugin for Firebird $Version"
Get-File $d.Plugin.Url $d.PluginZip -Force:$Force

# The archive must contain the server plugin.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [IO.Compression.ZipFile]::OpenRead($d.PluginZip)
try {
    $need = "$($d.Plugin.Folder)/Server/plugins/dbcrypt.dll"
    $found = @($zip.Entries | Where-Object { $_.FullName -eq $need }).Count
} finally {
    $zip.Dispose()
}
if ($found -ne 1) { Fail "File '$need' is not found in $($d.PluginZip)." }
Write-Host ("   size: {0} bytes, SHA-256: {1}" -f (Get-Item $d.PluginZip).Length, (Get-Sha256 $d.PluginZip))

<#
.SYNOPSIS
  Gets the license file DbCrypt.conf and checks its expiry date.

.DESCRIPTION
  Without parameters the script takes the trial license from the plugin archive
  (run 02-download-plugin.ps1 first). Use -Url to download a license file,
  or -LicenseFile to use your own license.

.EXAMPLE
  .\03-download-license.ps1 -Version 5
.EXAMPLE
  .\03-download-license.ps1 -Version 5 -LicenseFile C:\lic\DbCrypt.conf
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet('3', '4', '5')][string]$Version,
    [string]$WorkDir = "",
    [string]$Url = "",
    [string]$LicenseFile = ""
)
. (Join-Path $PSScriptRoot "common.ps1")
$d = Get-Deploy $Version $WorkDir

Step "License for Firebird $Version"
New-Item -ItemType Directory -Force (Split-Path $d.License -Parent) | Out-Null
if ($LicenseFile -ne "") {
    if (-not (Test-Path $LicenseFile)) { Fail "License file is not found: $LicenseFile" }
    Copy-Item $LicenseFile $d.License -Force
} elseif ($Url -ne "") {
    Get-File $Url $d.License -Force
} else {
    if (-not (Test-Path $d.PluginZip)) { Fail "$($d.PluginZip) is not found. Run 02-download-plugin.ps1 first." }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($d.PluginZip)
    try {
        $name = "$($d.Plugin.Folder)/Server/plugins/DbCrypt.conf"
        $entry = $zip.Entries | Where-Object { $_.FullName -eq $name } | Select-Object -First 1
        if ($null -eq $entry) { Fail "File '$name' is not found in $($d.PluginZip)." }
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $d.License, $true)
    } finally {
        $zip.Dispose()
    }
}

$lic = Get-LicenseInfo $d.License
if ($null -eq $lic.Expire) {
    Write-Host "   license: $($lic.RegName), no expiry date"
    exit 0
}
$days = [int][Math]::Floor(($lic.Expire - (Get-Date)).TotalDays)
Write-Host ("   license: {0}, expires {1:dd.MM.yyyy HH:mm}" -f $lic.RegName, $lic.Expire)
if ($days -lt 0) {
    Fail "The license is expired. Run 02-download-plugin.ps1 -Force to get a new archive, or use -LicenseFile."
}
if ($days -lt 7) { Write-Host "   WARNING: the license expires in $days days" -ForegroundColor Yellow }

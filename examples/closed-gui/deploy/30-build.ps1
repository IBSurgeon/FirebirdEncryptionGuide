<#
.SYNOPSIS
  Builds the example application, the KeySource libraries and the key provider.

.DESCRIPTION
  The script needs Lazarus with Free Pascal for Windows x64. The results go to work\build:

    EmployeeRemote.exe, EmployeeEmbedded.exe   the example application
    KeyProvider.exe                            the key provider for the variant C
    keysource\a-static\KeySource.dll           key in the library
    keysource\b-file\KeySource.dll             key in a file
    keysource\c-provider\KeySource.dll         key from the key provider
    keysource\d-rest\KeySource.dll             key from a REST service
    keysource\probe\KeySource.dll              diagnostic library with a log

.EXAMPLE
  .\30-build.ps1 -LazarusDir C:\lazarus
#>
param(
    [string]$LazarusDir = "C:\lazarus",
    [string]$WorkDir = ""
)
. (Join-Path $PSScriptRoot "common.ps1")
$d = Get-Deploy '5' $WorkDir
$example = Split-Path $PSScriptRoot -Parent

$lazbuild = Join-Path $LazarusDir "lazbuild.exe"
if (-not (Test-Path $lazbuild)) { Fail "$lazbuild is not found. Use -LazarusDir <folder of Lazarus>." }
$fpc = Get-ChildItem (Join-Path $LazarusDir "fpc\*\bin\x86_64-win64\fpc.exe") -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $fpc) { Fail "fpc.exe for x86_64-win64 is not found in $LazarusDir\fpc." }

New-Item -ItemType Directory -Force $d.Build | Out-Null

function Build-Project([string]$project, [string]$mode, [string]$exe) {
    Step "Build $exe"
    $arguments = @()
    if ($mode -ne "") { $arguments += "--build-mode=$mode" }
    $arguments += $project
    $out = & $lazbuild @arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { Fail "lazbuild failed:`n$out" }
    $built = Join-Path (Split-Path $project -Parent) "bin\x86_64-win64\$exe"
    Copy-Item $built $d.Build -Force
}

Build-Project (Join-Path $example "app\EmployeeApp\EmployeeApp.lpi") "Remote" "EmployeeRemote.exe"
Build-Project (Join-Path $example "app\EmployeeApp\EmployeeApp.lpi") "Embedded" "EmployeeEmbedded.exe"
Build-Project (Join-Path $example "keyprovider\KeyProvider.lpi") "" "KeyProvider.exe"

foreach ($variant in "a-static", "b-file", "c-provider", "d-rest", "probe") {
    Step "Build keysource\$variant\KeySource.dll"
    $outDir = Join-Path $d.Build "keysource\$variant"
    $unitDir = Join-Path $d.Build "units\$variant"
    New-Item -ItemType Directory -Force $outDir, $unitDir | Out-Null
    $source = Join-Path $example "keysource\$variant\KeySource.lpr"
    $common = Join-Path $example "keysource\common"
    $out = & $fpc.FullName -O2 -Xs -XX -CX "-Fu$common" "-FE$outDir" "-FU$unitDir" $source 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { Fail "fpc failed:`n$out" }
}
Write-Host "Done. Programs and libraries: $($d.Build)"

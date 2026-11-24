<#
.SYNOPSIS
  Runs all steps for one Firebird version: download, install, encrypt, start, deploy.

.DESCRIPTION
  Steps:

    01-download-firebird   official Firebird archive from github.com/FirebirdSQL/firebird
    02-download-plugin     plugin archive from cc.ib-aid.com
    03-download-license    trial license from the plugin archive
    10-install-server      private server in work\fb<N>\server
    20-encrypt-database    encrypted copies of the database employee
    11-start-server        server on its own port
    30-build               programs and libraries (only if work\build is empty)
    40-deploy-remote       workstation folder work\fb<N>\remote
    41-deploy-embedded     embedded folder work\fb<N>\embedded

  Without Lazarus: run 05-download-example.ps1 first. It puts ready programs to work\build.

  The key of the database:

    no parameters          the public test key Red
    -Passphrase "<text>"   a pass phrase
    -AskPassphrase         the script asks for the pass phrase; the phrase is not shown
    -KeyName <name>        name of the key (default: Red)

  With a pass phrase the default variant of KeySource is "c": the key provider in the Windows tray
  asks the user for the phrase. The variant "a" works only with the test key Red.

.EXAMPLE
  .\run-all.ps1 -Version 5
.EXAMPLE
  .\run-all.ps1 -Version 4 -KeySource b -LazarusDir D:\lazarus
.EXAMPLE
  .\run-all.ps1 -Version 5 -AskPassphrase
#>
param(
    [ValidateSet('3', '4', '5')][string]$Version = '5',
    [ValidateSet('a', 'b', 'c', 'd')][string]$KeySource = 'a',
    [string]$LazarusDir = "C:\lazarus",
    [string]$WorkDir = "",
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_]*$')][string]$KeyName = "Red",
    [string]$Passphrase = "",
    [switch]$AskPassphrase
)
. (Join-Path $PSScriptRoot "common.ps1")
$d = Get-Deploy $Version $WorkDir

$ownKey = $AskPassphrase -or ($Passphrase -ne "") -or ($KeyName -ne "Red")
if ($ownKey) {
    # Check the phrase before the long steps.
    if ($Passphrase -ne "") { Test-Passphrase $Passphrase }
    if (Test-Path $d.DbKey) { Fail "The database of the example is encrypted already. To use another key run first: .\cleanup.ps1 -Version $Version" }
    if (-not $PSBoundParameters.ContainsKey('KeySource')) { $KeySource = 'c' }
    if ($KeySource -eq 'a') { Fail "The variant 'a' has the test key Red in the code of the library. Use -KeySource b, c or d." }
}

function Invoke-Step([string]$name, [hashtable]$arguments) {
    $global:LASTEXITCODE = 0
    & (Join-Path $PSScriptRoot "$name.ps1") @arguments
    if ($LASTEXITCODE -ne 0) { Fail "Step $name failed." }
}

$common = @{ Version = $Version; WorkDir = $d.WorkDir }
Invoke-Step "01-download-firebird" $common
Invoke-Step "02-download-plugin" $common
Invoke-Step "03-download-license" $common
if (-not (Test-Path $d.Server)) { Invoke-Step "10-install-server" $common }
if (-not (Test-Path $d.DbKey)) {
    $keyArguments = @{ KeyName = $KeyName }
    if ($AskPassphrase) { $keyArguments.AskPassphrase = $true }
    if ($Passphrase -ne "") { $keyArguments.Passphrase = $Passphrase }
    Invoke-Step "20-encrypt-database" ($common + $keyArguments)
}
if (-not (Test-Port $d.Fb.Port)) { Invoke-Step "11-start-server" $common }
if (-not (Test-Path (Join-Path $d.Build "EmployeeRemote.exe"))) {
    Invoke-Step "30-build" @{ LazarusDir = $LazarusDir; WorkDir = $d.WorkDir }
}
Invoke-Step "40-deploy-remote" ($common + @{ KeySource = $KeySource })
Invoke-Step "41-deploy-embedded" ($common + @{ KeySource = $KeySource })

Write-Host ""
Write-Host "Ready. Firebird $($d.Fb.Version), port $($d.Fb.Port), KeySource variant: $KeySource"
Write-Host "  Network connection:  $(Join-Path $d.Root 'remote\EmployeeRemote.exe')"
if ($Version -eq '3') {
    Write-Host "  Embedded:            $(Join-Path $d.Root 'embedded\EmployeeEmbedded.cmd')"
} else {
    Write-Host "  Embedded:            $(Join-Path $d.Root 'embedded\EmployeeEmbedded.exe')"
}
$key = Get-DbKey $d
if ($KeySource -eq 'c') {
    if ($key.Kind -eq 'Password') { Write-Host "  The key provider asks for the key $($key.Name): type the pass phrase." }
    else { Write-Host "  The key provider asks for the key $($key.Name): type the text after the name from $($d.DbKey)" }
}
if ($KeySource -eq 'd') { Write-Host "  Start the key service first:  ..\restserver\key-server.ps1 -KeysFile `"$($d.DbKey)`"" }
Write-Host "  Stop the server:     .\12-stop-server.ps1 -Version $Version"

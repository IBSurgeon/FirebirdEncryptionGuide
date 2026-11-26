param(
    # The test server folder has a 64-bit client (FBCRYPT_CLIENT).
    # For Win32 a 32-bit client folder is needed: set FBCRYPT_CLIENT32 and use -Platform win32.
    [ValidateSet('win64', 'win32')]
    [string]$Platform = 'win64'
)
if ($Platform -eq 'win32') {
    if (-not $env:FBCRYPT_CLIENT32) {
        Write-Host "ERROR: FBCRYPT_CLIENT32 is not set. It must point to a 32-bit client folder with fbclient, fbcrypt and libcrypto." -ForegroundColor Red
        exit 2
    }
    # The examples read the client folder from FBCRYPT_CLIENT. Change it only for this run.
    $savedClient = $env:FBCRYPT_CLIENT
    $env:FBCRYPT_CLIENT = $env:FBCRYPT_CLIENT32
}
$compiler = if ($Platform -eq 'win32') { 'dcc32' } else { 'dcc64' }
try {
    & "$PSScriptRoot\..\..\common\run-test.ps1" -ExampleDir $PSScriptRoot -Build "(if not exist lib mkdir lib) && $compiler -B -Q -U..\common -N0lib -E. ConsoleFireDAC.dpr" -Command ".\ConsoleFireDAC.exe"
    $code = $LASTEXITCODE
} finally {
    if ($Platform -eq 'win32') { $env:FBCRYPT_CLIENT = $savedClient }
}
exit $code

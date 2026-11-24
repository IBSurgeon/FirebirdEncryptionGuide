# The example needs the plugin for Firebird 5.0 and the utility ClientKeygen.
if (($env:FBCRYPT_FB_MAJOR -ne '5') -or (-not $env:FBCRYPT_CLIENTKEYGEN)) {
    Write-Host "SKIP examples/clientkeygen (needs Firebird 5.0 and the variable FBCRYPT_CLIENTKEYGEN)" -ForegroundColor Yellow
    exit 0
}
& "$PSScriptRoot\..\common\run-test.ps1" -ExampleDir $PSScriptRoot -Command "python main.py"
exit $LASTEXITCODE

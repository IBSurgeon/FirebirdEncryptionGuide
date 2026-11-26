# Scenario S5 reads MON$DATABASE.MON$CRYPT_STATE. Firebird 3.0 has no such column.
if ([int]$env:FBCRYPT_FB_MAJOR -lt 4) {
    Write-Host "SKIP delphi/vcl-firedac (needs Firebird 4.0 or 5.0)" -ForegroundColor Yellow
    exit 0
}
& "$PSScriptRoot\..\..\common\run-test.ps1" -ExampleDir $PSScriptRoot -Build "(if not exist lib mkdir lib) && dcc64 -B -Q -U..\common -N0lib -E. VclFireDAC.dpr" -Command ".\VclFireDAC.exe --test"
exit $LASTEXITCODE

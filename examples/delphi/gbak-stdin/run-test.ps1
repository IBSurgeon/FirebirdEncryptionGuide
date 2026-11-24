& "$PSScriptRoot\..\..\common\run-test.ps1" -ExampleDir $PSScriptRoot -Build "(if not exist lib mkdir lib) && dcc64 -B -Q -U..\common -N0lib -E. GbakStdin.dpr" -Command ".\GbakStdin.exe"
exit $LASTEXITCODE

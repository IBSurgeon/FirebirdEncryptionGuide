& "$PSScriptRoot\..\..\common\run-test.ps1" -ExampleDir $PSScriptRoot -Build "(if not exist lib mkdir lib) && fpc -Fu..\common -FUlib -ogbak_stdin.exe gbak_stdin.lpr" -Command ".\gbak_stdin.exe"
exit $LASTEXITCODE

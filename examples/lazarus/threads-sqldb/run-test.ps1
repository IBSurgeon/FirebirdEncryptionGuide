& "$PSScriptRoot\..\..\common\run-test.ps1" -ExampleDir $PSScriptRoot -Build "(if not exist lib mkdir lib) && fpc -Fu..\common -FUlib -othreads_sqldb.exe threads_sqldb.lpr" -Command ".\threads_sqldb.exe"
exit $LASTEXITCODE

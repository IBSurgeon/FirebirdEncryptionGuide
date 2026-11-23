& "$PSScriptRoot\..\..\common\run-test.ps1" -ExampleDir $PSScriptRoot -Build "(if not exist lib mkdir lib) && fpc -Fu..\common -FUlib -oconsole_sqldb.exe console_sqldb.lpr" -Command ".\console_sqldb.exe"
exit $LASTEXITCODE

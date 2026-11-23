& "$PSScriptRoot\..\..\common\run-test.ps1" -ExampleDir $PSScriptRoot -Command "php -c ..\php.ini main.php"
exit $LASTEXITCODE

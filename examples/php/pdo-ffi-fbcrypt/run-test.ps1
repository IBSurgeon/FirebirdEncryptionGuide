# PHP must load fbclient from the client folder of the plugin.
$env:PATH = "$env:FBCRYPT_CLIENT;$env:PATH"
& "$PSScriptRoot\..\..\common\run-test.ps1" -ExampleDir $PSScriptRoot -Command "php -c ..\php.ini main.php"
exit $LASTEXITCODE

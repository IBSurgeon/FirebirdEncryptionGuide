# PHP must load fbclient from the folder with KeySource.
$env:PATH = "$env:FBCRYPT_WORK\client-keysource;$env:PATH"
& "$PSScriptRoot\..\..\common\run-test.ps1" -ExampleDir $PSScriptRoot -Command "php -c ..\php.ini main.php"
exit $LASTEXITCODE

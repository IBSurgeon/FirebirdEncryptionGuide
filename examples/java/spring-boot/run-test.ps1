# The key comes from an environment variable. The test builds it from the file of test keys.
$line = Get-Content $env:FBCRYPT_KEYS | Where-Object { $_ -match '^Key=Red ' } | Select-Object -First 1
$env:FBCRYPT_DB_KEY = 'Red:' + ($line -split ' ')[1]
& "$PSScriptRoot\..\..\common\run-test.ps1" -ExampleDir $PSScriptRoot -Build "mvn -q -DskipTests package" -Command "mvn -q spring-boot:run"
exit $LASTEXITCODE

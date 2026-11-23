& "$PSScriptRoot\..\..\common\run-test.ps1" -ExampleDir $PSScriptRoot -Build "mvn -q -f ..\pom.xml -DskipTests install" -Command "mvn -q exec:java"
exit $LASTEXITCODE

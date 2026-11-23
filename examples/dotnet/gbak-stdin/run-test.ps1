& "$PSScriptRoot\..\..\common\run-test.ps1" -ExampleDir $PSScriptRoot -Build "dotnet build -c Release -v q --nologo" -Command "dotnet run -c Release --no-build"
exit $LASTEXITCODE

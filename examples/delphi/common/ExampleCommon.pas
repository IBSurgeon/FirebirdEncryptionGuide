unit ExampleCommon;

{ Helpers shared by the Delphi examples.

  The examples read the connection parameters from environment variables.
  The script examples/common/setup.ps1 creates the file test-env.ps1 that sets them. }

interface

uses
  System.SysUtils, System.Classes, FbCryptApi;

{ Value of an environment variable. Stops the program if the variable is not set. }
function Env(const AName: string): string;

{ Connection string for a database alias on the test server: host/port:alias }
function ServerDsn(const AAlias: string): string;

{ Reads a key from the file in KeyHolder.conf format given by FBCRYPT_KEYS: Key=<name> 0x..,0x..,
  Do not keep real keys in the source code. Read them from a protected file. }
function ReadKey(const AName: string): TBytes;

implementation

function Env(const AName: string): string;
begin
  Result := GetEnvironmentVariable(AName);
  if Result = '' then
  begin
    WriteLn(ErrOutput, 'ERROR: environment variable ', AName, ' is not set. ',
      'Run examples/common/setup.ps1 and dot-source test-env.ps1.');
    WriteLn('ERROR: environment variable ', AName, ' is not set');
    Flush(ErrOutput);
    Halt(2);
  end;
end;

function ServerDsn(const AAlias: string): string;
begin
  Result := Env('FBCRYPT_HOST') + '/' + Env('FBCRYPT_PORT') + ':' + AAlias;
end;

function ReadKey(const AName: string): TBytes;
var
  Lines: TStringList;
  LineName: string;
  LineKey, Found: TBytes;
  I: Integer;
begin
  Found := nil;
  Lines := TStringList.Create;
  try
    Lines.LoadFromFile(Env('FBCRYPT_KEYS'));
    for I := 0 to Lines.Count - 1 do
      if ParseKeyLine(Lines[I], LineName, LineKey) and SameText(LineName, AName) then
      begin
        Found := LineKey;
        Break;
      end;
  finally
    Lines.Free;
  end;
  Result := Found;
  if not (Length(Result) in [16, 24, 32]) then
  begin
    WriteLn(ErrOutput, 'ERROR: key ', AName, ' has ', Length(Result), ' bytes, need 16, 24 or 32');
    WriteLn('ERROR: key ', AName, ' has ', Length(Result), ' bytes, need 16, 24 or 32');
    Flush(ErrOutput);
    Halt(2);
  end;
end;

end.

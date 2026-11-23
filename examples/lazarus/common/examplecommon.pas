unit examplecommon;

{ Helpers shared by the Free Pascal examples.

  The examples read the connection parameters from environment variables.
  The script examples/common/setup.ps1 creates the file test-env.ps1 that sets them. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Classes;

{ Value of an environment variable. Stops the program if the variable is not set. }
function Env(const AName: string): string;

{ Connection string for a database alias on the test server: host/port:alias }
function ServerDsn(const AAlias: string): string;

{ Reads a key from a file in KeyHolder.conf format: Key=<name> 0x..,0x..,
  Do not keep real keys in the source code. Read them from a protected file. }
function ReadKey(const AName: string): TBytes;

{ Key value in the notation of the plugin: 0x..,0x.., }
function KeyText(const AKey: TBytes): string;

implementation

function Env(const AName: string): string;
begin
  Result := GetEnvironmentVariable(AName);
  if Result = '' then
  begin
    WriteLn(StdErr, 'ERROR: environment variable ', AName, ' is not set. ',
      'Run examples/common/setup.ps1 and dot-source test-env.ps1.');
    Halt(2);
  end;
end;

function ServerDsn(const AAlias: string): string;
begin
  Result := Env('FBCRYPT_HOST') + '/' + Env('FBCRYPT_PORT') + ':' + AAlias;
end;

function ReadKey(const AName: string): TBytes;
var
  Lines, Parts: TStringList;
  Line, Rest, KeyName, Value: string;
  I, J, P: Integer;
begin
  Result := nil;
  Lines := TStringList.Create;
  Parts := TStringList.Create;
  try
    Lines.LoadFromFile(Env('FBCRYPT_KEYS'));
    for I := 0 to Lines.Count - 1 do
    begin
      Line := Trim(Lines[I]);
      if not SameText(Copy(Line, 1, 3), 'Key') then
        Continue;
      P := Pos('=', Line);
      if P = 0 then
        Continue;
      Rest := Trim(Copy(Line, P + 1, MaxInt));
      P := Pos(' ', Rest);
      if P = 0 then
        Continue;
      KeyName := Copy(Rest, 1, P - 1);
      Value := Trim(Copy(Rest, P + 1, MaxInt));
      if not SameText(KeyName, AName) then
        Continue;

      Parts.Clear;
      Parts.Delimiter := ',';
      Parts.StrictDelimiter := True;
      Parts.DelimitedText := Value;
      for J := 0 to Parts.Count - 1 do
        if Trim(Parts[J]) <> '' then
        begin
          SetLength(Result, Length(Result) + 1);
          // "0xec" -> "$ec"
          Result[High(Result)] := StrToInt('$' + Copy(Trim(Parts[J]), 3, 2));
        end;
      Break;
    end;
  finally
    Parts.Free;
    Lines.Free;
  end;
  if not (Length(Result) in [16, 24, 32]) then
  begin
    WriteLn(StdErr, 'ERROR: key ', AName, ' has ', Length(Result), ' bytes, need 16, 24 or 32');
    Halt(2);
  end;
end;

function KeyText(const AKey: TBytes): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(AKey) do
    Result := Result + '0x' + LowerCase(IntToHex(AKey[I], 2)) + ',';
end;

end.

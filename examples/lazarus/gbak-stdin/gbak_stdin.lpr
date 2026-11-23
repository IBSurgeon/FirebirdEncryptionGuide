program gbak_stdin;

{ Scenario S6: encrypted backup and restore from a program.

  Firebird 4.0 and 5.0: gbak -KeyHolder KeyHolderStdin, the key goes to the standard input of gbak.
  Firebird 3.0: gbak has no -KeyHolder switch. The program writes the key to a temporary file
  in the profile of the current user and runs gbak -KEYFILE.

  The key is never put on the command line: other users can see the command line. }

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, process, examplecommon;

const
  KeyName = 'Red';
  Marker = 'Hello from crypt_red';

type
  TGbakResult = record
    ExitCode: Integer;
    Errors: string;
  end;

var
  FbMajor: Integer;
  Key: TBytes;

function ReadAll(AStream: TStream): string;
var
  Buffer: array[0..4095] of Byte;
  Count: LongInt;
  Part: AnsiString;
begin
  Result := '';
  repeat
    Count := AStream.Read(Buffer, SizeOf(Buffer));
    if Count > 0 then
    begin
      SetString(Part, PAnsiChar(@Buffer[0]), Count);
      Result := Result + Part;
    end;
  until Count <= 0;
end;

{ Runs gbak. The line with the key goes to the standard input of the process. }
function RunGbak(const AArgs: array of string; const AKeyLine: string): TGbakResult;
var
  Gbak: TProcess;
  I: Integer;
begin
  Gbak := TProcess.Create(nil);
  try
    {$IFDEF WINDOWS}
    Gbak.Executable := IncludeTrailingPathDelimiter(Env('FBCRYPT_CLIENT')) + 'gbak.exe';
    {$ELSE}
    Gbak.Executable := IncludeTrailingPathDelimiter(Env('FBCRYPT_CLIENT')) + 'bin/gbak';
    {$ENDIF}
    Gbak.Parameters.Add('-user');
    Gbak.Parameters.Add(Env('FBCRYPT_USER'));
    Gbak.Parameters.Add('-password');
    Gbak.Parameters.Add(Env('FBCRYPT_PASSWORD'));
    for I := Low(AArgs) to High(AArgs) do
      Gbak.Parameters.Add(AArgs[I]);
    Gbak.Options := [poUsePipes, poNoConsole];
    Gbak.Execute;

    if AKeyLine <> '' then
      Gbak.Input.Write(AKeyLine[1], Length(AKeyLine));
    Gbak.CloseInput;

    Result.Errors := ReadAll(Gbak.Stderr);
    ReadAll(Gbak.Output);
    Gbak.WaitOnExit;
    Result.ExitCode := Gbak.ExitCode;
  finally
    Gbak.Free;
  end;
end;

function GbakWithKey(const AArgs: array of string): TGbakResult;
var
  KeyLine, KeyFile: string;
  Args: array of string;
  Lines: TStringList;
  I: Integer;
begin
  KeyLine := 'Key=' + KeyName + ' ' + KeyText(Key);
  Args := nil;
  SetLength(Args, Length(AArgs));
  for I := 0 to High(AArgs) do
    Args[I] := AArgs[I];

  if FbMajor >= 4 then
  begin
    SetLength(Args, Length(Args) + 2);
    Args[High(Args) - 1] := '-keyholder';
    Args[High(Args)] := 'KeyHolderStdin';
    Result := RunGbak(Args, KeyLine);
    Exit;
  end;

  // Firebird 3.0: a temporary key file in the profile of the current user.
  KeyFile := GetTempFileName(GetTempDir(False), 'fbkey');
  Lines := TStringList.Create;
  try
    Lines.Add(KeyLine);
    Lines.SaveToFile(KeyFile);
    SetLength(Args, Length(Args) + 4);
    Args[High(Args) - 3] := '-keyfile';
    Args[High(Args) - 2] := KeyFile;
    Args[High(Args) - 1] := '-keyname';
    Args[High(Args)] := KeyName;
    Result := RunGbak(Args, '');
  finally
    Lines.Free;
    DeleteFile(KeyFile);
  end;
end;

function Report(const ATitle: string; const AResult: TGbakResult; AMustFail: Boolean): Boolean;
var
  Failed: Boolean;
begin
  Failed := AResult.ExitCode <> 0;
  Result := Failed = AMustFail;
  if Result then
  begin
    if AMustFail then
      WriteLn(ATitle, ': error, as expected')
    else
      WriteLn(ATitle, ': OK');
  end
  else if AMustFail then
    WriteLn(ATitle, ': NO ERROR - this is wrong')
  else
    WriteLn(ATitle, ': FAILED');
  if Failed then
  begin
    WriteLn(StdErr, '--- ', ATitle);
    WriteLn(StdErr, AResult.Errors);
  end;
end;

function FileHasText(const AFileName, AText: string): Boolean;
var
  Stream: TFileStream;
  Content: AnsiString;
begin
  Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    Content := '';
    SetLength(Content, Stream.Size);
    if Stream.Size > 0 then
      Stream.ReadBuffer(Content[1], Stream.Size);
  finally
    Stream.Free;
  end;
  Result := Pos(AText, Content) > 0;
end;

var
  Work, BackupFile, RestoredDb, Server: string;
begin
  FbMajor := StrToIntDef(GetEnvironmentVariable('FBCRYPT_FB_MAJOR'), 5);
  Key := ReadKey(KeyName);
  Work := IncludeTrailingPathDelimiter(Env('FBCRYPT_WORK'));
  BackupFile := Work + 'tmp' + PathDelim + 'lazarus-crypt_red.fbk';
  RestoredDb := Work + 'db' + PathDelim + 'lazarus-restored.fdb';
  Server := Env('FBCRYPT_HOST') + '/' + Env('FBCRYPT_PORT') + ':';

  try
    // 1. Backup without a key must fail: the database is encrypted.
    Report('Backup without a key', RunGbak(['-b', Server + 'crypt_red', BackupFile], ''), True);

    // 2. Backup with the key. The backup file is encrypted too.
    if not Report('Backup with the key', GbakWithKey(['-b', Server + 'crypt_red', BackupFile]), False) then
      Halt(1);
    if FileHasText(BackupFile, Marker) then
      WriteLn('Backup file is encrypted: NO - this is wrong')
    else
      WriteLn('Backup file is encrypted: yes');

    // 3. Restore without a key must fail: gbak cannot read the encrypted backup file.
    Report('Restore without a key', RunGbak(['-rep', BackupFile, Server + RestoredDb], ''), True);

    // 4. Restore with the key. gbak encrypts the new database with the same key.
    Report('Restore with the key', GbakWithKey(['-rep', BackupFile, Server + RestoredDb]), False);
  finally
    DeleteFile(BackupFile);
    DeleteFile(RestoredDb);
  end;
end.

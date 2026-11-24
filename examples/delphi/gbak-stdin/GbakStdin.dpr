program GbakStdin;

{ Scenario S6: encrypted backup and restore from a program.

  Firebird 4.0 and 5.0: gbak -KeyHolder KeyHolderStdin, the key goes to the standard input of gbak.
  Firebird 3.0: gbak has no -KeyHolder switch. The program writes the key to a temporary file
  in the folder for temporary files of the current user and runs gbak -KEYFILE.

  The key is never put on the command line: other users can see the command line. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Winapi.Windows,
  FbCryptApi in '..\common\FbCryptApi.pas',
  ExampleCommon in '..\common\ExampleCommon.pas';

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
  GbakExe, Work, Server: string;

{ Puts the argument in quotes when the command line needs it. }
function Quote(const AArg: string): string;
begin
  Result := AArg;
  if (Pos(' ', AArg) > 0) or (Pos('"', AArg) > 0) then
    Result := '"' + StringReplace(AArg, '"', '""', [rfReplaceAll]) + '"';
end;

{ Reads the pipe to the end. gbak writes plain text. }
function ReadPipe(AHandle: THandle): string;
var
  Buffer: array[0..4095] of AnsiChar;
  BytesRead: DWORD;
begin
  Result := '';
  while ReadFile(AHandle, Buffer, SizeOf(Buffer), BytesRead, nil) and (BytesRead > 0) do
    Result := Result + string(AnsiString(Copy(Buffer, 1, BytesRead)));
end;

{ Runs gbak. The line with the key goes to the standard input of the process. }
function RunGbak(const AArgs: array of string; const AKeyLine: string): TGbakResult;
var
  Security: TSecurityAttributes;
  ChildStdIn, ParentStdIn, ChildStdOut, ParentStdOut, ChildStdErr, ParentStdErr: THandle;
  StartupInfo: TStartupInfo;
  ProcessInfo: TProcessInformation;
  CommandLine: string;
  KeyLine: AnsiString;
  ExitCode, BytesWritten: DWORD;
  I: Integer;

  { Creates a pipe for gbak.
    AParentReads = True: gbak writes (standard output, standard error), the parent reads.
    AParentReads = False: the parent writes, gbak reads (standard input).
    The end used by the parent is not inherited by gbak: gbak must not keep it open. }
  function NewPipe(var ARead, AWrite: THandle; AParentReads: Boolean): Boolean;
  begin
    Result := CreatePipe(ARead, AWrite, @Security, 1024 * 1024);
    if not Result then
      Exit;
    if AParentReads then
      Result := SetHandleInformation(ARead, HANDLE_FLAG_INHERIT, 0)
    else
      Result := SetHandleInformation(AWrite, HANDLE_FLAG_INHERIT, 0);
  end;

begin
  ChildStdIn := 0; ParentStdIn := 0;
  ChildStdOut := 0; ParentStdOut := 0;
  ChildStdErr := 0; ParentStdErr := 0;
  ProcessInfo.hProcess := 0;
  ProcessInfo.hThread := 0;
  try
    // The handles of gbak are inherited by the child process only.
    Security.nLength := SizeOf(Security);
    Security.lpSecurityDescriptor := nil;
    Security.bInheritHandle := True;
    if not NewPipe(ChildStdIn, ParentStdIn, False) or
       not NewPipe(ParentStdOut, ChildStdOut, True) or
       not NewPipe(ParentStdErr, ChildStdErr, True) then
      raise Exception.CreateFmt('Cannot create pipes: %s', [SysErrorMessage(GetLastError)]);

    StartupInfo := Default(TStartupInfo);
    StartupInfo.cb := SizeOf(StartupInfo);
    StartupInfo.dwFlags := STARTF_USESTDHANDLES or STARTF_USESHOWWINDOW;
    StartupInfo.wShowWindow := SW_HIDE;
    StartupInfo.hStdInput := ChildStdIn;
    StartupInfo.hStdOutput := ChildStdOut;
    StartupInfo.hStdError := ChildStdErr;

    CommandLine := Quote(GbakExe) + ' -user ' + Quote(Env('FBCRYPT_USER')) +
      ' -password ' + Quote(Env('FBCRYPT_PASSWORD'));
    for I := Low(AArgs) to High(AArgs) do
      CommandLine := CommandLine + ' ' + Quote(AArgs[I]);
    UniqueString(CommandLine); // CreateProcess needs a writable buffer

    if not CreateProcess(nil, PChar(CommandLine), nil, nil, True, CREATE_NO_WINDOW,
        nil, nil, StartupInfo, ProcessInfo) then
      raise Exception.CreateFmt('Cannot start %s: %s', [GbakExe, SysErrorMessage(GetLastError)]);

    // The parent does not use the ends of gbak.
    CloseHandle(ChildStdIn); ChildStdIn := 0;
    CloseHandle(ChildStdOut); ChildStdOut := 0;
    CloseHandle(ChildStdErr); ChildStdErr := 0;

    // The line with the key goes to the standard input of gbak. The end of the pipe is the end of the input.
    KeyLine := AnsiString(AKeyLine);
    if KeyLine <> '' then
      if not WriteFile(ParentStdIn, KeyLine[1], Length(KeyLine), BytesWritten, nil) then
        raise Exception.CreateFmt('Cannot write to the standard input of gbak: %s', [SysErrorMessage(GetLastError)]);
    CloseHandle(ParentStdIn); ParentStdIn := 0;

    // gbak writes little text. The pipes are large enough to read one pipe after the other.
    Result.Errors := ReadPipe(ParentStdErr);
    ReadPipe(ParentStdOut);
    WaitForSingleObject(ProcessInfo.hProcess, INFINITE);
    if not GetExitCodeProcess(ProcessInfo.hProcess, ExitCode) then
      ExitCode := DWORD(-1);
    Result.ExitCode := Integer(ExitCode);
  finally
    if ChildStdIn <> 0 then CloseHandle(ChildStdIn);
    if ParentStdIn <> 0 then CloseHandle(ParentStdIn);
    if ChildStdOut <> 0 then CloseHandle(ChildStdOut);
    if ParentStdOut <> 0 then CloseHandle(ParentStdOut);
    if ChildStdErr <> 0 then CloseHandle(ChildStdErr);
    if ParentStdErr <> 0 then CloseHandle(ParentStdErr);
    if ProcessInfo.hThread <> 0 then CloseHandle(ProcessInfo.hThread);
    if ProcessInfo.hProcess <> 0 then CloseHandle(ProcessInfo.hProcess);
  end;
end;

{ Runs gbak with the key. The way to pass the key depends on the Firebird version. }
function GbakWithKey(const AArgs: array of string): TGbakResult;
var
  Args: TArray<string>;
  KeyLine, KeyFile: string;
  Lines: TStringList;
  Buffer: string;
  I: Integer;
begin
  KeyLine := 'Key=' + KeyName + ' ' + KeyText(Key);
  SetLength(Args, Length(AArgs));
  for I := 0 to High(AArgs) do
    Args[I] := AArgs[I];

  if FbMajor >= 4 then
  begin
    Args := Args + TArray<string>.Create('-keyholder', 'KeyHolderStdin');
    Result := RunGbak(Args, KeyLine);
    Exit;
  end;

  // Firebird 3.0: a temporary key file in the folder for temporary files of the current user.
  // Only the current user has access to this folder. The file is deleted after the run.
  SetLength(Buffer, MAX_PATH + 1);
  UniqueString(Buffer);
  if GetTempFileName(PChar(TPath.GetTempPath), 'fbk', 0, PChar(Buffer)) = 0 then
    raise Exception.CreateFmt('Cannot create a temporary file: %s', [SysErrorMessage(GetLastError)]);
  KeyFile := PChar(Buffer);
  Lines := TStringList.Create;
  try
    Lines.Add(KeyLine);
    Lines.SaveToFile(KeyFile, TEncoding.ASCII);
    Args := Args + TArray<string>.Create('-keyfile', KeyFile, '-keyname', KeyName);
    Result := RunGbak(Args, '');
  finally
    Lines.Free;
    System.SysUtils.DeleteFile(KeyFile);
  end;
end;

{ Prints the result of a gbak run. Returns True when the result is as expected. }
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
    WriteLn(ErrOutput, '--- ', ATitle);
    WriteLn(ErrOutput, AResult.Errors);
    Flush(ErrOutput);
  end;
end;

{ The backup of an encrypted database is encrypted too: the plain text is not found in it. }
function FileHasText(const AFileName, AText: string): Boolean;
var
  Content: AnsiString;
begin
  with TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone) do
    try
      Content := '';
      SetLength(Content, Size);
      if Size > 0 then
        ReadBuffer(Content[1], Size);
    finally
      Free;
    end;
  Result := Pos(AnsiString(AText), Content) > 0;
end;

var
  BackupFile, RestoredDb: string;
begin
  try
    FbMajor := StrToIntDef(GetEnvironmentVariable('FBCRYPT_FB_MAJOR'), 5);
    Key := ReadKey(KeyName);
    GbakExe := IncludeTrailingPathDelimiter(Env('FBCRYPT_CLIENT')) + 'gbak.exe';
    Work := IncludeTrailingPathDelimiter(Env('FBCRYPT_WORK'));
    BackupFile := Work + 'tmp' + PathDelim + 'delphi-crypt_red.fbk';
    RestoredDb := Work + 'db' + PathDelim + 'delphi-restored.fdb';
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
      System.SysUtils.DeleteFile(BackupFile);
      System.SysUtils.DeleteFile(RestoredDb);
    end;
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, 'ERROR: ', E.Message);
      WriteLn('ERROR: ', E.ClassName);
      Flush(ErrOutput);
      ExitCode := 1;
    end;
  end;
end.

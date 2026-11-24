library KeySource;

{ Variant C: the key comes from a separate program, the key provider.

  The library asks the key provider through a named pipe at each connection.
  The key provider asks the user once and keeps the key in its memory.
  The library keeps no key: the key provider has the cache.

  KeySource.ini next to the library:

    [KeySource]
    Pipe=                 name of the pipe; default FbKeyProvider-<user name>
    ProviderExe=          full path of KeyProvider.exe. The library starts it when the
                          pipe is not found, and checks that the pipe belongs to it
    TimeoutMs=120000      how long to wait for the answer (the user types the key)
    Log=0

  Protocol (text, one request for one pipe connection):

    request   GETKEYS 1 <process id> <program name>\n
    answer    OK\n<lines "Key=..." or "Password=...">     the pipe is then closed
              ERROR <text>\n }

{$mode objfpc}{$H+}

uses
  Windows, SysUtils, keysourcecommon;

const
  SECURITY_SQOS_PRESENT = $00100000;
  SECURITY_IDENTIFICATION = $00010000;
  PROCESS_QUERY_LIMITED_INFORMATION = $1000;

function GetNamedPipeServerProcessId(Pipe: THandle; var ProcessId: DWORD): BOOL;
  stdcall; external 'kernel32.dll';
function QueryFullProcessImageNameW(Process: THandle; Flags: DWORD; Name: PWideChar; var Size: DWORD): BOOL;
  stdcall; external 'kernel32.dll';

function CurrentUser: UnicodeString;
var
  Buf: array[0..255] of WideChar;
  Len: DWORD;
begin
  Len := Length(Buf);
  if GetUserNameW(Buf, Len) and (Len > 1) then
    SetString(Result, Buf, Len - 1)
  else
    Result := 'user';
end;

function ProcessFile(ProcessId: DWORD): UnicodeString;
var
  H: THandle;
  Buf: array[0..1023] of WideChar;
  Len: DWORD;
begin
  Result := '';
  H := OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, ProcessId);
  if H = 0 then
    Exit;
  Len := Length(Buf);
  if QueryFullProcessImageNameW(H, 0, Buf, Len) then
    SetString(Result, Buf, Len);
  CloseHandle(H);
end;

function StartProvider(const ExeName: UnicodeString): Boolean;
var
  Startup: TStartupInfoW;
  Info: TProcessInformation;
  CommandLine: UnicodeString;
begin
  FillChar(Startup, SizeOf(Startup), 0);
  Startup.cb := SizeOf(Startup);
  CommandLine := '"' + ExeName + '"';
  UniqueString(CommandLine);
  Result := CreateProcessW(nil, PWideChar(CommandLine), nil, nil, False, 0, nil,
    PWideChar(ExtractFilePath(ExeName)), Startup, Info);
  if Result then
  begin
    CloseHandle(Info.hThread);
    CloseHandle(Info.hProcess);
  end;
end;

// Opens the pipe of the key provider. Starts the key provider if it is not running.
function OpenProviderPipe(const PipeName, ProviderExe: UnicodeString; out Error: string): THandle;
var
  Deadline: QWord;
  Started: Boolean;
  Code, ServerId: DWORD;
begin
  Error := '';
  Started := False;
  Deadline := GetTickCount64 + 10000;
  repeat
    // SECURITY_IDENTIFICATION: the pipe server cannot act with the rights of this process.
    Result := CreateFileW(PWideChar(PipeName), GENERIC_READ or GENERIC_WRITE, 0, nil, OPEN_EXISTING,
      SECURITY_SQOS_PRESENT or SECURITY_IDENTIFICATION, 0);
    if Result <> INVALID_HANDLE_VALUE then
      Break;
    Code := GetLastError;
    if Code = ERROR_PIPE_BUSY then
      WaitNamedPipeW(PWideChar(PipeName), 1000)
    else if Code = ERROR_FILE_NOT_FOUND then
    begin
      if (ProviderExe <> '') and not Started then
      begin
        Started := True;
        if not StartProvider(ProviderExe) then
        begin
          Error := Format('cannot start the key provider %s, error %d', [string(ProviderExe), GetLastError]);
          Exit;
        end;
      end
      else if ProviderExe = '' then
      begin
        Error := 'the key provider is not running';
        Exit;
      end;
      Sleep(200);
    end
    else
    begin
      Error := Format('cannot open the pipe, error %d', [Code]);
      Exit;
    end;
  until GetTickCount64 > Deadline;

  if Result = INVALID_HANDLE_VALUE then
  begin
    Error := 'the key provider does not answer';
    Exit;
  end;

  // The pipe must belong to the program from the settings, not to another program
  // that took the name of the pipe.
  if ProviderExe <> '' then
  begin
    ServerId := 0;
    if not GetNamedPipeServerProcessId(Result, ServerId) or
       (WideCompareText(ProcessFile(ServerId), ProviderExe) <> 0) then
    begin
      CloseHandle(Result);
      Result := INVALID_HANDLE_VALUE;
      Error := 'the pipe does not belong to the key provider from the settings';
    end;
  end;
end;

// Reads the answer until the key provider closes the pipe or the time is over.
function ReadAnswer(Pipe: THandle; TimeoutMs: Integer; out Answer: AnsiString): Boolean;
var
  Deadline: QWord;
  Available, Got: DWORD;
  Buf: array[0..4095] of AnsiChar;
begin
  Answer := '';
  Deadline := GetTickCount64 + QWord(TimeoutMs);
  while GetTickCount64 < Deadline do
  begin
    Available := 0;
    if not PeekNamedPipe(Pipe, nil, 0, nil, @Available, nil) then
      Break;                       // the key provider closed the pipe: the answer is complete
    if Available = 0 then
    begin
      Sleep(5);
      Continue;
    end;
    Got := 0;
    if not ReadFile(Pipe, Buf, SizeOf(Buf), Got, nil) or (Got = 0) then
      Break;
    SetLength(Answer, Length(Answer) + Integer(Got));
    Move(Buf, Answer[Length(Answer) - Integer(Got) + 1], Got);
  end;
  Result := Answer <> '';
end;

function AskProvider(out Keys: AnsiString; out Error: string): Boolean;
var
  PipeName, ProviderExe: UnicodeString;
  Pipe: THandle;
  Request, Answer, FirstLine: AnsiString;
  Written: DWORD;
  P: SizeInt;
begin
  Result := False;
  Keys := '';
  PipeName := '\\.\pipe\' + Setting('Pipe', 'FbKeyProvider-' + CurrentUser);
  ProviderExe := ExpandEnv(Setting('ProviderExe', ''));

  Pipe := OpenProviderPipe(PipeName, ProviderExe, Error);
  if Pipe = INVALID_HANDLE_VALUE then
    Exit;
  try
    Request := AnsiString(Format('GETKEYS 1 %d %s'#10,
      [GetCurrentProcessId, ExtractFileName(ParamStr(0))]));
    if not WriteFile(Pipe, Request[1], Length(Request), Written, nil) then
    begin
      Error := Format('cannot send the request, error %d', [GetLastError]);
      Exit;
    end;
    if not ReadAnswer(Pipe, SettingInt('TimeoutMs', 120000), Answer) then
    begin
      Error := 'no answer from the key provider in the given time';
      Exit;
    end;
  finally
    CloseHandle(Pipe);
  end;

  P := Pos(#10, Answer);
  if P = 0 then
    P := Length(Answer) + 1;
  FirstLine := Trim(Copy(Answer, 1, P - 1));
  if FirstLine <> 'OK' then
  begin
    Error := 'the key provider answered: ' + string(FirstLine);
    Exit;
  end;
  Keys := CleanKeys(Copy(Answer, P + 1, MaxInt));
  Result := Keys <> '';
  if not Result then
    Error := 'the key provider returned no keys';
end;

function MakeKeys(Alloc: TAllocator; var Size: Cardinal): PAnsiChar; cdecl;
var
  Keys: AnsiString;
  Error: string;
begin
  Result := nil;
  Size := 0;
  PinLibrary;   // stay in the process: see the rules in keysourcecommon.pas
  if not AskProvider(Keys, Error) then
  begin
    LogLine('MakeKeys: ' + Error);
    Exit;
  end;
  Result := ReturnKeys(Alloc, Keys, Size);
  LogLine('MakeKeys: the keys from the key provider are returned');
end;

exports
  MakeKeys;

begin
end.

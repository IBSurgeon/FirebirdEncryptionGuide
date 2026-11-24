unit pipeserver;

{ Named pipe server of the key provider.

  One pipe instance. Only the current user can open the pipe; clients from the
  network are rejected. The thread reads one request, asks the main thread for
  the answer (the main thread can show a window) and writes the answer. }

{$mode objfpc}{$H+}

interface

uses
  Windows, Classes, SysUtils;

type
  // Called in the main thread. Returns the complete answer for the client.
  TRequestEvent = procedure(const ClientFile: string; ClientId: Cardinal; out Answer: AnsiString) of object;

  { TPipeServer }

  TPipeServer = class(TThread)
  private
    FPipeName: UnicodeString;
    FPipe: THandle;
    FOnRequest: TRequestEvent;
    FClientFile: string;
    FClientId: Cardinal;
    FAnswer: AnsiString;
    procedure CallHandler;
    procedure ServeClient;
  protected
    procedure Execute; override;
  public
    // Raises an exception if the pipe name is in use (the key provider is already running).
    constructor Create(const PipeName: UnicodeString; Handler: TRequestEvent);
    procedure Stop;
  end;

function DefaultPipeName: UnicodeString;

implementation

const
  PIPE_REJECT_REMOTE_CLIENTS = $00000008;
  FILE_FLAG_FIRST_PIPE_INSTANCE = $00080000;
  PROCESS_QUERY_LIMITED_INFORMATION = $1000;
  SDDL_REVISION_1 = 1;

function GetNamedPipeClientProcessId(Pipe: THandle; var ProcessId: DWORD): BOOL;
  stdcall; external 'kernel32.dll';
function QueryFullProcessImageNameW(Process: THandle; Flags: DWORD; Name: PWideChar; var Size: DWORD): BOOL;
  stdcall; external 'kernel32.dll';
function ConvertSidToStringSidW(Sid: Pointer; var StringSid: PWideChar): BOOL;
  stdcall; external 'advapi32.dll';
function ConvertStringSecurityDescriptorToSecurityDescriptorW(Text: PWideChar; Revision: DWORD;
  var Descriptor: Pointer; Size: PDWORD): BOOL; stdcall; external 'advapi32.dll';

function CurrentUserName: UnicodeString;
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

function DefaultPipeName: UnicodeString;
begin
  Result := 'FbKeyProvider-' + CurrentUserName;
end;

// SID of the current user as text, for example S-1-5-21-...
function CurrentUserSid: UnicodeString;
var
  Token: THandle;
  Buf: array[0..255] of Byte;
  Needed: DWORD;
  Text: PWideChar;
begin
  Result := '';
  if not OpenProcessToken(GetCurrentProcess, TOKEN_QUERY, Token) then
    Exit;
  try
    Needed := 0;
    if GetTokenInformation(Token, TokenUser, @Buf, SizeOf(Buf), Needed) then
    begin
      Text := nil;
      // The buffer starts with the structure TOKEN_USER; its first field is the pointer to the SID.
      if ConvertSidToStringSidW(PPointer(@Buf)^, Text) then
      begin
        Result := Text;
        LocalFree(HLOCAL(Text));
      end;
    end;
  finally
    CloseHandle(Token);
  end;
end;

function ProcessFile(ProcessId: DWORD): string;
var
  H: THandle;
  Buf: array[0..1023] of WideChar;
  Len: DWORD;
  Name: UnicodeString;
begin
  Result := '';
  H := OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, ProcessId);
  if H = 0 then
    Exit;
  Len := Length(Buf);
  if QueryFullProcessImageNameW(H, 0, Buf, Len) then
  begin
    SetString(Name, Buf, Len);
    Result := UTF8Encode(Name);
  end;
  CloseHandle(H);
end;

{ TPipeServer }

constructor TPipeServer.Create(const PipeName: UnicodeString; Handler: TRequestEvent);
var
  Security: TSecurityAttributes;
  Descriptor: Pointer;
  Sddl: UnicodeString;
begin
  FPipeName := '\\.\pipe\' + PipeName;
  FOnRequest := Handler;

  // Access list of the pipe: full access for the current user, nothing for the others.
  Sddl := 'D:P(A;;GA;;;' + CurrentUserSid + ')';
  Descriptor := nil;
  if not ConvertStringSecurityDescriptorToSecurityDescriptorW(PWideChar(Sddl), SDDL_REVISION_1, Descriptor, nil) then
    raise Exception.CreateFmt('Cannot make the access list of the pipe, error %d', [GetLastError]);
  try
    Security.nLength := SizeOf(Security);
    Security.lpSecurityDescriptor := Descriptor;
    Security.bInheritHandle := False;
    // FILE_FLAG_FIRST_PIPE_INSTANCE: fails if another program already has a pipe with this name.
    FPipe := CreateNamedPipeW(PWideChar(FPipeName),
      PIPE_ACCESS_DUPLEX or FILE_FLAG_FIRST_PIPE_INSTANCE,
      PIPE_TYPE_BYTE or PIPE_READMODE_BYTE or PIPE_WAIT or PIPE_REJECT_REMOTE_CLIENTS,
      1, 8192, 8192, 0, @Security);
    if FPipe = INVALID_HANDLE_VALUE then
      raise Exception.CreateFmt('Cannot create the pipe %s, error %d. Is the key provider already running?',
        [UTF8Encode(FPipeName), GetLastError]);
  finally
    LocalFree(HLOCAL(Descriptor));
  end;
  inherited Create(False);
end;

procedure TPipeServer.CallHandler;
begin
  FAnswer := 'ERROR no handler'#10;
  if Assigned(FOnRequest) then
    FOnRequest(FClientFile, FClientId, FAnswer);
end;

procedure TPipeServer.ServeClient;
var
  Buf: array[0..1023] of AnsiChar;
  Got, Written, ClientId: DWORD;
  Request: AnsiString;
begin
  Request := '';
  // The request is one short line.
  while (Pos(#10, Request) = 0) and (Length(Request) < SizeOf(Buf)) do
  begin
    Got := 0;
    if not ReadFile(FPipe, Buf, SizeOf(Buf), Got, nil) or (Got = 0) then
      Break;
    SetLength(Request, Length(Request) + Integer(Got));
    Move(Buf, Request[Length(Request) - Integer(Got) + 1], Got);
  end;
  if Terminated then
    Exit;

  if Copy(Request, 1, 10) <> 'GETKEYS 1 ' then
    FAnswer := 'ERROR unknown request'#10
  else
  begin
    // The process id comes from Windows, not from the text of the request.
    ClientId := 0;
    GetNamedPipeClientProcessId(FPipe, ClientId);
    FClientId := ClientId;
    FClientFile := ProcessFile(ClientId);
    Synchronize(@CallHandler);
  end;
  if FAnswer <> '' then
    WriteFile(FPipe, FAnswer[1], Length(FAnswer), Written, nil);
  // Remove the key from the memory of this thread.
  if FAnswer <> '' then
    FillChar(FAnswer[1], Length(FAnswer), 0);
  FAnswer := '';
  FlushFileBuffers(FPipe);
end;

procedure TPipeServer.Execute;
begin
  while not Terminated do
  begin
    if ConnectNamedPipe(FPipe, nil) or (GetLastError = ERROR_PIPE_CONNECTED) then
    begin
      if not Terminated then
        ServeClient;
      DisconnectNamedPipe(FPipe);
    end
    else
      Sleep(100);
  end;
  CloseHandle(FPipe);
end;

procedure TPipeServer.Stop;
var
  H: THandle;
begin
  Terminate;
  // Open the pipe once: this ends the wait in ConnectNamedPipe.
  H := CreateFileW(PWideChar(FPipeName), GENERIC_READ or GENERIC_WRITE, 0, nil, OPEN_EXISTING, 0, 0);
  if H <> INVALID_HANDLE_VALUE then
    CloseHandle(H);
  WaitFor;
end;

end.

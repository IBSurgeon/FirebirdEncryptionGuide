library KeySource;

{ Variant D: the key comes from a key service through a REST request.

  The library sends GET <Url> with the header "Authorization: Bearer <token>".
  The answer is plain text: lines "Key=<name> 0x..," or "Password=<name> <phrase>".

  The plugin unloads KeySource.dll after each call, so after the first good
  answer the library pins itself in the process and keeps the keys in memory.
  The next connections of this process do not use the network until the cache
  time is over.

  KeySource.ini next to the library:

    [KeySource]
    Url=https://keys.example.com/keys/Red
    Token=                the access token (for tests only)
    TokenFile=            file with the access token; better than Token
    TimeoutMs=5000        time limit of the request
    CacheSeconds=300      how long the keys stay in memory; 0: ask at each connection
    RetrySeconds=10       after a failed request: no new request during this time
    Log=0

  The library uses WinHTTP, a part of Windows. It needs no other dll.
  With https the certificate of the server is checked by Windows.

  When MakeKeys returns NULL, the Firebird client calls it again several times for the
  same connection (5 to 9 times in the tests). Without RetrySeconds a key service that
  does not answer would delay the error message by TimeoutMs for each of these calls. }

{$mode objfpc}{$H+}

uses
  Windows, SysUtils, keysourcecommon;

type
  HINTERNET = Pointer;

const
  winhttp = 'winhttp.dll';
  WINHTTP_ACCESS_TYPE_DEFAULT_PROXY = 0;
  WINHTTP_FLAG_SECURE = $00800000;
  WINHTTP_QUERY_STATUS_CODE = 19;
  WINHTTP_QUERY_FLAG_NUMBER = $20000000;
  WINHTTP_ADDREQ_FLAG_ADD = $20000000;

function WinHttpOpen(UserAgent: PWideChar; AccessType: DWORD; ProxyName, ProxyBypass: PWideChar;
  Flags: DWORD): HINTERNET; stdcall; external winhttp;
function WinHttpConnect(Session: HINTERNET; ServerName: PWideChar; Port: Word;
  Reserved: DWORD): HINTERNET; stdcall; external winhttp;
function WinHttpOpenRequest(Connect: HINTERNET; Verb, ObjectName, Version, Referrer: PWideChar;
  AcceptTypes: Pointer; Flags: DWORD): HINTERNET; stdcall; external winhttp;
function WinHttpSetTimeouts(Handle: HINTERNET; Resolve, Connect, Send, Receive: Integer): BOOL;
  stdcall; external winhttp;
function WinHttpAddRequestHeaders(Request: HINTERNET; Headers: PWideChar; Length: DWORD;
  Modifiers: DWORD): BOOL; stdcall; external winhttp;
function WinHttpSendRequest(Request: HINTERNET; Headers: PWideChar; HeadersLength: DWORD;
  Optional: Pointer; OptionalLength, TotalLength: DWORD; Context: PtrUInt): BOOL; stdcall; external winhttp;
function WinHttpReceiveResponse(Request: HINTERNET; Reserved: Pointer): BOOL; stdcall; external winhttp;
function WinHttpQueryHeaders(Request: HINTERNET; InfoLevel: DWORD; Name: PWideChar; Buffer: Pointer;
  var BufferLength: DWORD; Index: PDWORD): BOOL; stdcall; external winhttp;
function WinHttpReadData(Request: HINTERNET; Buffer: Pointer; ToRead: DWORD; var BytesRead: DWORD): BOOL;
  stdcall; external winhttp;
function WinHttpCloseHandle(Handle: HINTERNET): BOOL; stdcall; external winhttp;

var
  // The cache. It lives between the calls only after PinLibrary.
  CacheLock: TRTLCriticalSection;
  CachedKeys: AnsiString = '';
  CachedAt: QWord = 0;
  FailedAt: QWord = 0;      // time of the last failed request; 0: no failure

// Splits "http://host:port/path" into its parts.
function ParseUrl(const Url: UnicodeString; out Secure: Boolean; out Host: UnicodeString;
  out Port: Word; out Path: UnicodeString): Boolean;
var
  Rest: UnicodeString;
  P: SizeInt;
begin
  Result := False;
  Rest := Url;
  if WideCompareText(Copy(Rest, 1, 8), 'https://') = 0 then
  begin
    Secure := True;
    Port := 443;
    Delete(Rest, 1, 8);
  end
  else if WideCompareText(Copy(Rest, 1, 7), 'http://') = 0 then
  begin
    Secure := False;
    Port := 80;
    Delete(Rest, 1, 7);
  end
  else
    Exit;
  P := Pos('/', Rest);
  if P = 0 then
  begin
    Host := Rest;
    Path := '/';
  end
  else
  begin
    Host := Copy(Rest, 1, P - 1);
    Path := Copy(Rest, P, MaxInt);
  end;
  P := Pos(':', Host);
  if P > 0 then
  begin
    Port := StrToIntDef(string(Copy(Host, P + 1, MaxInt)), 0);
    Host := Copy(Host, 1, P - 1);
  end;
  Result := (Host <> '') and (Port <> 0);
end;

function ReadToken: UnicodeString;
var
  FileName: UnicodeString;
  Data: AnsiString;
begin
  Result := Setting('Token', '');
  FileName := ExpandEnv(Setting('TokenFile', ''));
  if (FileName <> '') and ReadFileBytes(FileName, Data) then
    Result := UnicodeString(Trim(Data));
end;

function ComputerAndUser: UnicodeString;
var
  Buf: array[0..255] of WideChar;
  Len: DWORD;
begin
  Result := '';
  Len := Length(Buf);
  if GetComputerNameW(Buf, Len) then
    Result := Copy(UnicodeString(Buf), 1, Len);
  Len := Length(Buf);
  if GetUserNameW(Buf, Len) and (Len > 1) then
    Result := Result + '\' + Copy(UnicodeString(Buf), 1, Len - 1);
end;

function HttpGet(const Url, Token: UnicodeString; TimeoutMs: Integer; out Body: AnsiString;
  out Error: string): Boolean;
var
  Secure: Boolean;
  Host, Path, Headers: UnicodeString;
  Port: Word;
  Session, Connect, Request: HINTERNET;
  Flags, Status, StatusSize, Got: DWORD;
  Buf: array[0..4095] of AnsiChar;
begin
  Result := False;
  Body := '';
  Error := '';
  if not ParseUrl(Url, Secure, Host, Port, Path) then
  begin
    Error := 'the setting Url is empty or wrong';
    Exit;
  end;
  Session := nil;
  Connect := nil;
  Request := nil;
  try
    Session := WinHttpOpen('FbKeySource/1.0', WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, nil, nil, 0);
    if Session = nil then
    begin
      Error := Format('WinHttpOpen failed, error %d', [GetLastError]);
      Exit;
    end;
    WinHttpSetTimeouts(Session, TimeoutMs, TimeoutMs, TimeoutMs, TimeoutMs);
    Connect := WinHttpConnect(Session, PWideChar(Host), Port, 0);
    if Connect = nil then
    begin
      Error := Format('WinHttpConnect failed, error %d', [GetLastError]);
      Exit;
    end;
    Flags := 0;
    if Secure then
      Flags := WINHTTP_FLAG_SECURE;
    Request := WinHttpOpenRequest(Connect, 'GET', PWideChar(Path), nil, nil, nil, Flags);
    if Request = nil then
    begin
      Error := Format('WinHttpOpenRequest failed, error %d', [GetLastError]);
      Exit;
    end;
    Headers := 'X-Workstation: ' + ComputerAndUser + #13#10;
    if Token <> '' then
      Headers := Headers + 'Authorization: Bearer ' + Token + #13#10;
    WinHttpAddRequestHeaders(Request, PWideChar(Headers), Length(Headers), WINHTTP_ADDREQ_FLAG_ADD);

    if not WinHttpSendRequest(Request, nil, 0, nil, 0, 0, 0) or
       not WinHttpReceiveResponse(Request, nil) then
    begin
      Error := Format('the key service does not answer, error %d', [GetLastError]);
      Exit;
    end;
    Status := 0;
    StatusSize := SizeOf(Status);
    WinHttpQueryHeaders(Request, WINHTTP_QUERY_STATUS_CODE or WINHTTP_QUERY_FLAG_NUMBER, nil,
      @Status, StatusSize, nil);
    if Status <> 200 then
    begin
      Error := Format('the key service answered with the status %d', [Status]);
      Exit;
    end;
    repeat
      Got := 0;
      if not WinHttpReadData(Request, @Buf, SizeOf(Buf), Got) then
      begin
        Error := Format('cannot read the answer, error %d', [GetLastError]);
        Exit;
      end;
      if Got > 0 then
      begin
        SetLength(Body, Length(Body) + Integer(Got));
        Move(Buf, Body[Length(Body) - Integer(Got) + 1], Got);
      end;
    until (Got = 0) or (Length(Body) > 65536);
    Result := True;
  finally
    if Request <> nil then WinHttpCloseHandle(Request);
    if Connect <> nil then WinHttpCloseHandle(Connect);
    if Session <> nil then WinHttpCloseHandle(Session);
  end;
end;

function MakeKeys(Alloc: TAllocator; var Size: Cardinal): PAnsiChar; cdecl;
var
  CacheMs, RetryMs: QWord;
  Body, Keys: AnsiString;
  Error: string;

  // Keeps the time of the failure. The library must stay in the process for that.
  procedure RememberFailure(const Text: string);
  begin
    LogLine('MakeKeys: ' + Text);
    if PinLibrary then
      FailedAt := GetTickCount64;
  end;

begin
  Result := nil;
  Size := 0;
  CacheMs := QWord(SettingInt('CacheSeconds', 300)) * 1000;
  RetryMs := QWord(SettingInt('RetrySeconds', 10)) * 1000;

  // One thread asks the service. The other threads wait and take the answer from the cache.
  EnterCriticalSection(CacheLock);
  try
    if (CachedKeys <> '') and (CacheMs > 0) and (GetTickCount64 - CachedAt < CacheMs) then
    begin
      Result := ReturnKeys(Alloc, CachedKeys, Size);
      LogLine('MakeKeys: the keys from the cache are returned');
      Exit;
    end;

    if (FailedAt <> 0) and (GetTickCount64 - FailedAt < RetryMs) then
    begin
      LogLine('MakeKeys: the last request failed a moment ago; no new request');
      Exit;
    end;

    CachedKeys := '';
    if not HttpGet(Setting('Url', ''), ReadToken, SettingInt('TimeoutMs', 5000), Body, Error) then
    begin
      RememberFailure(Error);
      Exit;
    end;
    Keys := CleanKeys(Body);
    if Keys = '' then
    begin
      RememberFailure('the key service returned no keys');
      Exit;
    end;
    FailedAt := 0;

    if CacheMs > 0 then
      if PinLibrary then
      begin
        CachedKeys := Keys;
        CachedAt := GetTickCount64;
      end
      else
        LogLine(Format('MakeKeys: cannot pin the library, error %d; the cache is off', [GetLastError]));

    Result := ReturnKeys(Alloc, Keys, Size);
    LogLine('MakeKeys: the keys from the key service are returned');
  finally
    LeaveCriticalSection(CacheLock);
  end;
end;

exports
  MakeKeys;

procedure LibraryExit;
begin
  DoneCriticalSection(CacheLock);
end;

begin
  InitCriticalSection(CacheLock);
  AddExitProc(@LibraryExit);
end.

unit FbCryptApi;

{ Wrapper of the fbcrypt library from the client package of the encryption plugin.

  fbcrypt sends the key with the protected key exchange. The server does not need
  UnsafeClient = true.

  Delphi 10.4 and newer. Platforms: Win32 and Win64. }

interface

uses
  System.SysUtils, System.Types, System.Classes;

type
  EFbCrypt = class(Exception);

  // extern "C" int fbcrypt_init(const char* clientPathName);
  TFbCryptInitFunc = function(clientPathName: PAnsiChar): Integer; stdcall;
  // extern "C" int fbcrypt_key(const char* name, const unsigned char* data, unsigned dl);
  TFbCryptKeyFunc = function(name: PAnsiChar; data: PByte; dl: Cardinal): Integer; stdcall;
  // extern "C" int fbcrypt_callback(void* provider);
  TFbCryptCallbackFunc = function(provider: Pointer): Integer; stdcall;

  { TFbCrypt }

  TFbCrypt = class
  private
    FHandle: THandle;
    FInit: TFbCryptInitFunc;
    FKey: TFbCryptKeyFunc;
    FCallback: TFbCryptCallbackFunc;
    function GetProc(const AName: string): Pointer;
    procedure CheckCallback(ACode: Integer);
  public
    { AClientDir: folder with fbcrypt, fbclient and libcrypto.
      The database components must load fbclient from the same folder. }
    constructor Create(const AClientDir: string);
    { Adds a key to the key list of fbcrypt. The list is global for the process. }
    procedure AddKey(const AName: string; const AKey: TBytes);
    { Removes all keys from the key list. }
    procedure ClearKeys;
    { For components on the ISC API (FireDAC, IBX).
      Call it in the thread that opens the connection. }
    procedure RegisterForThread;
    { For code on the object-oriented API: pass the pointer to IProvider. }
    procedure RegisterForProvider(AProvider: Pointer);
  end;

{ Full path of fbclient in the client folder. }
function FbClientLibrary(const AClientDir: string): string;

{ Key value in the notation of the plugin: 0x..,0x.., }
function KeyText(const AKey: TBytes): string;

{ Key value as one line of KeyHolder.conf: Key=<name> 0x..,0x.., }
function KeyLine(const AName: string; const AKey: TBytes): string;

{ Parses the key value in the notation of the plugin: 0x..,0x..,
  Spaces around the elements are allowed. }
function ParseKeyHex(const AText: string): TBytes;

{ Parses a line of KeyHolder.conf: Key=<name> 0x..,0x..,
  Returns False for other lines and for comments. }
function ParseKeyLine(const ALine: string; out AKeyName: string; out AKey: TBytes): Boolean;

implementation

uses
  Winapi.Windows;

{ Loads a library without a system dialog when the file is not found.
  AErrorCode gets the system error code for the message. }
function LoadLibraryQuiet(const AFileName: string; out AErrorCode: Integer): THandle;
var
  OldMode: UINT;
begin
  OldMode := SetErrorMode(SEM_FAILCRITICALERRORS or SEM_NOOPENFILEERRORBOX);
  try
    Result := Winapi.Windows.LoadLibrary(PChar(AFileName));
    AErrorCode := GetLastError;
  finally
    SetErrorMode(OldMode);
  end;
end;

function LoadErrorText(AErrorCode: Integer): string;
begin
  Result := 'error ' + IntToStr(AErrorCode);
  if AErrorCode <> 0 then
    Result := Result + ', ' + SysErrorMessage(AErrorCode);
  if AErrorCode = 193 then
    Result := Result + '. The bitness of the program must be the same as the bitness of ' +
      'fbclient.dll and fbcrypt.dll.';
end;

function FbClientLibrary(const AClientDir: string): string;
begin
  Result := IncludeTrailingPathDelimiter(AClientDir) + 'fbclient.dll';
end;

function KeyText(const AKey: TBytes): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(AKey) do
    Result := Result + '0x' + LowerCase(IntToHex(AKey[I], 2)) + ',';
end;

function KeyLine(const AName: string; const AKey: TBytes): string;
begin
  Result := 'Key=' + AName + ' ' + KeyText(AKey);
end;

function ParseKeyHex(const AText: string): TBytes;
var
  Parts: TStringList;
  Line: string;
  I, Count: Integer;
begin
  Result := nil;
  Parts := TStringList.Create;
  try
    Parts.Delimiter := ',';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := AText;
    SetLength(Result, Parts.Count);
    Count := 0;
    for I := 0 to Parts.Count - 1 do
    begin
      Line := Trim(Parts[I]);
      if Line = '' then
        Continue;
      if not Line.StartsWith('0x', True) then
        raise EFbCrypt.CreateFmt('"%s" is not a key value. Expected: 0x..,0x..,', [Line]);
      Result[Count] := Byte(StrToInt('$' + Line.Substring(2)));
      Inc(Count);
    end;
    SetLength(Result, Count);
  finally
    Parts.Free;
  end;
end;

function ParseKeyLine(const ALine: string; out AKeyName: string; out AKey: TBytes): Boolean;
var
  Line, Rest: string;
  EqualPos, SpacePos: Integer;
begin
  Result := False;
  AKeyName := '';
  AKey := nil;
  Line := Trim(ALine);
  EqualPos := Pos('=', Line);
  if (EqualPos = 0) or not SameText(Copy(Line, 1, EqualPos - 1), 'Key') then
    Exit;
  Rest := Trim(Copy(Line, EqualPos + 1, MaxInt));
  SpacePos := Pos(' ', Rest);
  if SpacePos <= 1 then
    Exit;
  AKeyName := Copy(Rest, 1, SpacePos - 1);
  AKey := ParseKeyHex(Trim(Copy(Rest, SpacePos + 1, MaxInt)));
  Result := True;
end;

{ TFbCrypt }

function TFbCrypt.GetProc(const AName: string): Pointer;
begin
  Result := Winapi.Windows.GetProcAddress(FHandle, PAnsiChar(AnsiString(AName)));
  if Result = nil then
    raise EFbCrypt.CreateFmt('Function %s is not found in the fbcrypt library', [AName]);
end;

constructor TFbCrypt.Create(const AClientDir: string);
var
  Dir, ClientName, LibraryName: string;
  Code, LoadError: Integer;
  Search: TSearchRec;
begin
  inherited Create;
  Dir := IncludeTrailingPathDelimiter(AClientDir);
  ClientName := FbClientLibrary(Dir);
  LibraryName := Dir + 'fbcrypt.dll';
  if not FileExists(LibraryName) then
    raise EFbCrypt.CreateFmt('%s is not found. Use the client folder of the encryption plugin.', [LibraryName]);

  // 1. fbcrypt.dll imports fbclient.dll. Load fbclient from the client folder first:
  //    fbcrypt and the data access components then use the same instance.
  if LoadLibraryQuiet(ClientName, LoadError) = 0 then
    raise EFbCrypt.CreateFmt('Cannot load %s: %s', [ClientName, LoadErrorText(LoadError)]);

  // 2. fbcrypt loads libcrypto by name. Load it by the full path first:
  //    Windows then finds the loaded module.
  if FindFirst(Dir + 'libcrypto-*.dll', faAnyFile, Search) = 0 then
  try
    repeat
      LoadLibraryQuiet(Dir + Search.Name, LoadError);
    until FindNext(Search) <> 0;
  finally
    // Plain FindClose would be the WinAPI function here.
    System.SysUtils.FindClose(Search);
  end;

  // 3. fbcrypt itself.
  FHandle := LoadLibraryQuiet(LibraryName, LoadError);
  if FHandle = 0 then
    raise EFbCrypt.CreateFmt('Cannot load %s: %s', [LibraryName, LoadErrorText(LoadError)]);
  FInit := TFbCryptInitFunc(GetProc('fbcrypt_init'));
  FKey := TFbCryptKeyFunc(GetProc('fbcrypt_key'));
  FCallback := TFbCryptCallbackFunc(GetProc('fbcrypt_callback'));

  // The same fbclient that the data access components load.
  Code := FInit(PAnsiChar(AnsiString(ClientName)));
  if Code < 0 then
    raise EFbCrypt.CreateFmt('fbcrypt_init = %d: cannot load %s. Check the path and the bitness. ' +
      'Another reason: fbcrypt_init was called before with another path.', [Code, ClientName]);
end;

procedure TFbCrypt.AddKey(const AName: string; const AKey: TBytes);
var
  Code: Integer;
begin
  if Length(AKey) = 0 then
    raise EFbCrypt.Create('The key is empty');
  Code := FKey(PAnsiChar(AnsiString(AName)), @AKey[0], Length(AKey));
  if Code < 0 then
    raise EFbCrypt.CreateFmt('fbcrypt_key = %d', [Code]);
end;

procedure TFbCrypt.ClearKeys;
var
  Code: Integer;
begin
  // fbcrypt_init with a null pointer removes all keys from the list.
  Code := FInit(nil);
  if Code < 0 then
    raise EFbCrypt.CreateFmt('fbcrypt_init(nil) = %d', [Code]);
end;

procedure TFbCrypt.CheckCallback(ACode: Integer);
var
  Reason: string;
begin
  if ACode >= 0 then
    Exit;
  case ACode of
    -1: Reason := 'cannot register the keys';
    -5: Reason := 'the loaded fbclient is older than 3.0';
    -10: Reason := 'fbcrypt_init was not called';
  else
    Reason := 'unknown error';
  end;
  raise EFbCrypt.CreateFmt('fbcrypt_callback = %d: %s', [ACode, Reason]);
end;

procedure TFbCrypt.RegisterForThread;
begin
  CheckCallback(FCallback(nil));
end;

procedure TFbCrypt.RegisterForProvider(AProvider: Pointer);
begin
  CheckCallback(FCallback(AProvider));
end;

end.

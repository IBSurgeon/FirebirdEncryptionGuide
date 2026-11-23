unit fbcryptapi;

{ Wrapper of the fbcrypt library from the client package of the encryption plugin.

  fbcrypt sends the key with the protected key exchange. The server does not need
  UnsafeClient = true.

  Free Pascal 3.2.2, Windows and Linux. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, dynlibs;

type
  EFbCrypt = class(Exception);

  // extern "C" int fbcrypt_init(const char* clientPathName);
  TFbCryptInitFunc = function(clientPathName: PAnsiChar): Integer;
    {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
  // extern "C" int fbcrypt_key(const char* name, const unsigned char* data, unsigned dl);
  TFbCryptKeyFunc = function(name: PAnsiChar; data: PByte; dl: Cardinal): Integer;
    {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
  // extern "C" int fbcrypt_callback(void* provider);
  TFbCryptCallbackFunc = function(provider: Pointer): Integer;
    {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};

  { TFbCrypt }

  TFbCrypt = class
  private
    FHandle: TLibHandle;
    FInit: TFbCryptInitFunc;
    FKey: TFbCryptKeyFunc;
    FCallback: TFbCryptCallbackFunc;
    function GetProc(const AName: string): Pointer;
    procedure CheckCallback(ACode: Integer);
  public
    { AClientDir: folder with fbcrypt, fbclient and libcrypto.
      The database components must load fbclient from the same folder. }
    constructor Create(const AClientDir: string);
    destructor Destroy; override;
    { Adds a key to the key list of fbcrypt. The list is global for the process. }
    procedure AddKey(const AName: string; const AKey: TBytes);
    { Removes all keys from the key list. }
    procedure ClearKeys;
    { For components on the ISC API (SQLdb, IBX, ZeosLib).
      Call it in the thread that opens the connection. }
    procedure RegisterForThread;
    { For code on the object-oriented API: pass the pointer to IProvider. }
    procedure RegisterForProvider(AProvider: Pointer);
  end;

{ Full path of fbclient in the client folder. }
function FbClientLibrary(const AClientDir: string): string;

implementation

function LibDir(const AClientDir: string): string;
begin
  {$IFDEF WINDOWS}
  Result := IncludeTrailingPathDelimiter(AClientDir);
  {$ELSE}
  Result := IncludeTrailingPathDelimiter(AClientDir) + 'lib' + PathDelim;
  {$ENDIF}
end;

function FbClientLibrary(const AClientDir: string): string;
begin
  {$IFDEF WINDOWS}
  Result := LibDir(AClientDir) + 'fbclient.dll';
  {$ELSE}
  Result := LibDir(AClientDir) + 'libfbclient.so';
  {$ENDIF}
end;

{ TFbCrypt }

function TFbCrypt.GetProc(const AName: string): Pointer;
begin
  Result := GetProcedureAddress(FHandle, AName);
  if Result = nil then
    raise EFbCrypt.CreateFmt('Function %s is not found in the fbcrypt library', [AName]);
end;

constructor TFbCrypt.Create(const AClientDir: string);
var
  LibraryName, ClientName: string;
  Code: Integer;
  {$IFDEF WINDOWS}
  Search: TSearchRec;
  {$ENDIF}
begin
  inherited Create;
  {$IFDEF WINDOWS}
  // fbcrypt loads libcrypto by name. Load it by the full path first:
  // Windows then finds the loaded module.
  if FindFirst(LibDir(AClientDir) + 'libcrypto-*.dll', faAnyFile, Search) = 0 then
  begin
    repeat
      LoadLibrary(LibDir(AClientDir) + Search.Name);
    until FindNext(Search) <> 0;
    FindClose(Search);
  end;
  LibraryName := LibDir(AClientDir) + 'fbcrypt.dll';
  {$ELSE}
  LibraryName := LibDir(AClientDir) + 'libfbcrypt.so';
  {$ENDIF}

  FHandle := LoadLibrary(LibraryName);
  if FHandle = NilHandle then
    raise EFbCrypt.CreateFmt('Cannot load %s. Check the path and the bitness.', [LibraryName]);
  FInit := TFbCryptInitFunc(GetProc('fbcrypt_init'));
  FKey := TFbCryptKeyFunc(GetProc('fbcrypt_key'));
  FCallback := TFbCryptCallbackFunc(GetProc('fbcrypt_callback'));

  ClientName := FbClientLibrary(AClientDir);
  Code := FInit(PAnsiChar(AnsiString(ClientName)));
  if Code < 0 then
    raise EFbCrypt.CreateFmt('fbcrypt_init = %d: cannot load %s. Check the path and the bitness. ' +
      'Another reason: fbcrypt_init was called before with another path.', [Code, ClientName]);
end;

destructor TFbCrypt.Destroy;
begin
  // The library stays loaded: fbclient keeps the pointer to the callback of fbcrypt.
  inherited Destroy;
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
begin
  FInit(nil);
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

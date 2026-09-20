unit DBCryptHelper;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, DynLibs;

const
  DBKeySize = 32;

type
  TDBKey = array[0..DBKeySize-1] of Byte;
  PDBKey = ^TDBKey;

type
  {$IFDEF WINDOWS}
  // extern "C" int fbcrypt_init(const char* clientPathName);
  Tfbcrypt_init_Func = function (const aStr: PAnsiChar): Integer; StdCall;

  // extern "C" int fbcrypt_key(const char* name, const unsigned char* data, unsigned dl);
  Tfbcrypt_key_Func = function (pszKeyName: Pointer; pKeyValue: Pointer; iKeyLength: Cardinal): Integer; StdCall;

  // extern "C" int fbcrypt_callback(void* provider);
  Tfbcrypt_callback_Func = function(provider: Pointer): Integer; StdCall;
  {$ELSE}
  // extern "C" int fbcrypt_init(const char* clientPathName);
  Tfbcrypt_init_Func = function (const aStr: PAnsiChar): Integer; cdelc;

  // extern "C" int fbcrypt_key(const char* name, const unsigned char* data, unsigned dl);
  Tfbcrypt_key_Func = function (pszKeyName: Pointer; pKeyValue: Pointer; iKeyLength: Cardinal): Integer; cdelc;

  // extern "C" int fbcrypt_callback(void* provider);
  Tfbcrypt_callback_Func = function(provider: Pointer): Integer; cdelc;
  {$ENDIF}

  { TDBCryptHelper }

  TDBCryptHelper = class(TComponent)
  private
    FLibraryPath: TFileName;
    FLibFbCrypt: TLibHandle;
    fbcrypt_init: Tfbcrypt_init_Func;
    fbcrypt_key: Tfbcrypt_key_Func;
    fbcrypt_callback: Tfbcrypt_callback_Func;
  private
    procedure LoadLibFunctions;
    procedure ClearLibFunctions;
    procedure SetLibraryPath(const AValue: TFileName);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure LoadLibrary;
    procedure UnloadLibrary;

    procedure FbCryptInit(const AFbClientPath: TFileName);
    procedure FbCryptKey(const AKeyName: string; AKeyValue: PDBKey);
    procedure FbCryptCallback(AProvider: Pointer);
  public
    property LibraryPath: TFileName read FLibraryPath write SetLibraryPath;
  end;

implementation

{ TDBCryptHelper }

procedure TDBCryptHelper.LoadLibFunctions;
begin
  fbcrypt_init := Tfbcrypt_init_Func(GetProcedureAddress(FLibFbCrypt, 'fbcrypt_init'));
  if fbcrypt_init = nil then
    raise Exception.CreateFmt('Can not find function "%s" in library "%s"', ['fbcrypt_init', FLibraryPath]);

  fbcrypt_key := Tfbcrypt_key_Func(GetProcedureAddress(FLibFbCrypt, 'fbcrypt_key'));
  if fbcrypt_key = nil then
    raise Exception.CreateFmt('Can not find function "%s" in library "%s"', ['fbcrypt_key', FLibraryPath]);

  fbcrypt_callback := Tfbcrypt_callback_Func(GetProcedureAddress(FLibFbCrypt, 'fbcrypt_callback'));
  if fbcrypt_callback = nil then
    raise Exception.CreateFmt('Can not find function "%s" in library "%s"', ['fbcrypt_callback', FLibraryPath]);
end;

procedure TDBCryptHelper.ClearLibFunctions;
begin
  fbcrypt_init := nil;
  fbcrypt_key := nil;
  fbcrypt_callback := nil;
end;


procedure TDBCryptHelper.SetLibraryPath(const AValue: TFileName);
begin
  if FLibraryPath = AValue then
    Exit;
  UnloadLibrary;
  FLibraryPath := AValue;
end;

constructor TDBCryptHelper.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

{$IFDEF WINDOWS}
  FLibraryPath := 'fbcrypt.dll';
{$ELSE}
  FLibraryPath := 'fbcrypt.so';
{$ENDIF}

  FLibFbCrypt := DynLibs.NilHandle;
  fbcrypt_init := nil;
  fbcrypt_key := nil;
  fbcrypt_callback := nil;
end;

destructor TDBCryptHelper.Destroy;
begin
  UnloadLibrary;
  inherited Destroy;
end;

procedure TDBCryptHelper.LoadLibrary;
begin
  if FLibFbCrypt = DynLibs.NilHandle then
  begin
    FLibFbCrypt := SafeLoadLibrary(FLibraryPath);
    if FLibFbCrypt = DynLibs.NilHandle then
      raise Exception.CreateFmt('Can not load library "%s"', [FLibraryPath]);

    try
      LoadLibFunctions;
    except
      on E: Exception do
      begin
        UnloadLibrary;
        raise;
      end;
    end;
  end;
end;

procedure TDBCryptHelper.UnloadLibrary;
begin
  if FLibFbCrypt <> DynLibs.NilHandle then
  begin
    if FreeLibrary(FLibFbCrypt) then
    begin
      FLibFbCrypt := DynLibs.NilHandle;
      ClearLibFunctions;
    end;
  end;
end;

procedure TDBCryptHelper.FbCryptInit(const AFbClientPath: TFileName);
var
  xFuncResult: Integer;
begin
  if not Assigned(fbcrypt_init) then
    raise Exception.Create('FbCrypt library not loaded');

  xFuncResult := fbcrypt_init(PAnsiChar(AnsiString(AFbClientPath)));
  if (xFuncResult < 0) then
  begin
    raise Exception.CreateFmt(
      'fbcrypt_init failed. The client library with the specified name "%s" cannot be loaded.',
      [AFbClientPath]
    );
  end;
end;

procedure TDBCryptHelper.FbCryptKey(const AKeyName: string; AKeyValue: PDBKey);
var
  xFuncResult: Integer;
  xKeyName: PAnsiChar;
begin
  if not Assigned(fbcrypt_key) then
    raise Exception.Create('FbCrypt library not loaded');

  xKeyName := PAnsiChar(AnsiString(AKeyName));

  xFuncResult := fbcrypt_key(
    xKeyName,
    AKeyValue,
    DBKeySize
  );

  if (xFuncResult < 0) then
    raise Exception.Create('fbcrypt_key failed. Unknown error saving key; possibly insufficient memory.');
end;

procedure TDBCryptHelper.FbCryptCallback(AProvider: Pointer);
var
  xFuncResult: Integer;
begin
  if not Assigned(fbcrypt_callback) then
    raise Exception.Create('FbCrypt library not loaded');

  xFuncResult := fbcrypt_callback(AProvider);

  if (xFuncResult < 0) then
  begin
    case xFuncResult of
      -1: raise Exception.Create('fbcrypt_callback failed. Unknown error registering stored keys');

      -5: raise Exception.Create('fbcrypt_callback failed. The call to fb_get_master_interface is missing from ' +
            'the library loaded via fbcrypt_init. You might be using an old version of fbclient (< 3.0).');

      -10: raise Exception.Create('fbcrypt_callback failed. The client library was not loaded using fbcrypt_init.');

      else
          raise Exception.Create('fbcrypt_callback failed');
    end;
  end;
end;

end.


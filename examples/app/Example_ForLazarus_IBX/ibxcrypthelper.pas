unit IBXCryptHelper;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, DBCryptHelper, IBDatabase;

type

  { TIBDatabaseCryptHelper }

  TIBDatabaseCryptHelper = class(TDBCryptHelper)
  public
    procedure SetDatabaseCryptKey(ADatabase: TIbDatabase;
      const AKeyName: string; AKeyValue: PDBKey);
  end;

implementation

uses FB30ClientAPI;

{ TIBDatabaseCryptHelper }

procedure TIBDatabaseCryptHelper.SetDatabaseCryptKey(ADatabase: TIbDatabase;
  const AKeyName: string; AKeyValue: PDBKey);
begin
  LoadLibrary;
  FbCryptInit(ADatabase.FirebirdLibraryPathName);
  if AKeyValue <> nil then
    FbCryptKey(AKeyName, AKeyValue);
  FbCryptCallback((ADatabase.FirebirdAPI as TFB30ClientAPI).ProviderIntf);
end;

end.


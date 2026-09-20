unit ConnectionSettingsForm;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, EditBtn,
  StdCtrls, Buttons, IBDatabase, IBXCryptHelper, DatabaseKeys;

type

  { TfrmConnectionSetting }

  TfrmConnectionSetting = class(TForm)
    BitBtn1: TBitBtn;
    BitBtn2: TBitBtn;
    btnTestConnect: TButton;
    cbDBKeyName: TComboBox;
    cbShowPassword: TCheckBox;
    cbDBCharset: TComboBox;
    edtDatabase: TLabeledEdit;
    edtFirebirdClient: TFileNameEdit;
    edtFbCryptLibrary: TFileNameEdit;
    GroupBox1: TGroupBox;
    dbConnectionTest: TIBDatabase;
    GroupBox2: TGroupBox;
    Label1: TLabel;
    Label2: TLabel;
    edtDBUser: TLabeledEdit;
    edtDBPassword: TLabeledEdit;
    edtDBRole: TLabeledEdit;
    Label3: TLabel;
    Label4: TLabel;
    Label5: TLabel;
    Panel1: TPanel;
    procedure btnTestConnectClick(Sender: TObject);
    procedure cbDBKeyNameChange(Sender: TObject);
    procedure cbShowPasswordChange(Sender: TObject);
    procedure dbConnectionTestAfterDisconnect(Sender: TObject);
    procedure dbConnectionTestBeforeConnect(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
  private
    FBCryptHelper: TIBDatabaseCryptHelper;
  private
    function GetDatabase: string;
    function GetDBCharset: string;
    function GetDBRole: string;
    function GetFirebirdClient: TFileName;
    function GetDBUser: string;
    function GetDBPassword: string;
    function GetFbCryptLibrary: string;
    function GetDbKeyName: string;
    function GetDbKeyIndex: TDBKeyIndex;

    procedure SetDatabase(const AValue: string);
    procedure SetDBCharset(const AValue: string);
    procedure SetDBRole(const AValue: string);
    procedure SetFirebirdClient(const AValue: TFileName);
    procedure SetDBUser(const AValue: string);
    procedure SetDBPassword(const AValue: string);
    procedure SetFbCryptLibrary(const AValue: string);
    procedure SetDbKeyName(const AValue: string);
    procedure SetDbKeyIndex(Index: TDBKeyIndex);
  public
    property Database: string read GetDatabase write SetDatabase;
    property FirebirdClient: TFileName read GetFirebirdClient write SetFirebirdClient;
    property DBUser: string read GetDBUser write SetDBUser;
    property DBPassword: string read GetDBPassword write SetDBPassword;
    property DBRole: string read GetDBRole write SetDBRole;
    property DBCharset: string read GetDBCharset write SetDBCharset;
    property FbCryptLibrary: string read GetFbCryptLibrary write SetFbCryptLibrary;
    property DbKeyName: string read GetDbKeyName write SetDbKeyName;
    property DbKeyIndex: TDBKeyIndex read GetDbKeyIndex write SetDbKeyIndex;
  end;

var
  frmConnectionSetting: TfrmConnectionSetting;

implementation

{$R *.lfm}

{ TfrmConnectionSetting }

procedure TfrmConnectionSetting.cbShowPasswordChange(Sender: TObject);
begin
  if cbShowPassword.Checked then
    edtDBPassword.PasswordChar := #0
  else
    edtDBPassword.PasswordChar := '*';
end;

procedure TfrmConnectionSetting.dbConnectionTestAfterDisconnect(Sender: TObject
  );
begin
  FBCryptHelper.UnloadLibrary;
end;

procedure TfrmConnectionSetting.dbConnectionTestBeforeConnect(Sender: TObject);
begin
  FBCryptHelper.SetDatabaseCryptKey(dbConnectionTest, DbKeyName, GetDBKey(DbKeyIndex));
end;

procedure TfrmConnectionSetting.btnTestConnectClick(Sender: TObject);
begin
  FBCryptHelper.LibraryPath := FbCryptLibrary;

  dbConnectionTest.DatabaseName := Database;
  dbConnectionTest.FirebirdLibraryPathName := FirebirdClient;
  dbConnectionTest.Params.Clear;
  dbConnectionTest.Params.Values['user_name'] := DBUser;
  dbConnectionTest.Params.Values['password'] := DBPassword;
  dbConnectionTest.Params.Values['sql_role_name'] := DBRole;
  dbConnectionTest.Params.Values['lc_ctype'] := DBCharset;
  try
    dbConnectionTest.Open;
    ShowMessage('Connection succefull');
    dbConnectionTest.Close;
  except
    on E: Exception do
    begin
      ShowMessage('Connection Error: ' + E.Message);
      FBCryptHelper.UnloadLibrary;
    end;
  end;
end;

procedure TfrmConnectionSetting.cbDBKeyNameChange(Sender: TObject);
begin
  if cbDBKeyName.ItemIndex = 0 then
    edtFbCryptLibrary.Enabled := False
  else
    edtFbCryptLibrary.Enabled := True;
end;

procedure TfrmConnectionSetting.FormCreate(Sender: TObject);
var
  xKeyIndex: TDBKeyIndex;
begin
  FBCryptHelper := TIBDatabaseCryptHelper.Create(Self);

  edtFirebirdClient.InitialDir := ExtractFileDir(Application.ExeName);
  edtFbCryptLibrary.InitialDir := ExtractFileDir(Application.ExeName);
{$IFDEF WINDOWS}
  edtFirebirdClient.Filter := 'Dynamic Library|*.dll';
  edtFbCryptLibrary.Filter := 'Dynamic Library|*.dll';
{$ELSE}
  edtFirebirdClient.Filter := 'Shared Library|*.so';
  edtFbCryptLibrary.Filter := 'Shared Library|*.so';
{$ENDIF}

  cbDBKeyName.Items.Clear;
  for xKeyIndex := Low(TDBKeyIndex) to High(TDBKeyIndex) do
    cbDBKeyName.Items.Add(DBKeyNames[xKeyIndex]);
  cbDBKeyName.ItemIndex := Integer(keyNone);
end;

procedure TfrmConnectionSetting.FormShow(Sender: TObject);
begin
  if cbDBKeyName.ItemIndex = 0 then
    edtFbCryptLibrary.Enabled := False
  else
    edtFbCryptLibrary.Enabled := True;
end;

function TfrmConnectionSetting.GetDatabase: string;
begin
  Result := edtDatabase.Text;
end;

function TfrmConnectionSetting.GetDBCharset: string;
begin
  Result := cbDBCharset.Text;
end;

function TfrmConnectionSetting.GetDBRole: string;
begin
  Result := edtDBRole.Text;
end;

procedure TfrmConnectionSetting.SetDatabase(const AValue: string);
begin
  edtDatabase.Text := AValue;
end;

procedure TfrmConnectionSetting.SetDBCharset(const AValue: string);
begin
  cbDBCharset.Text := AValue;
end;

function TfrmConnectionSetting.GetFirebirdClient: TFileName;
begin
  Result := edtFirebirdClient.FileName;
end;

procedure TfrmConnectionSetting.SetDBRole(const AValue: string);
begin
  edtDBRole.Text := AValue;
end;

procedure TfrmConnectionSetting.SetFirebirdClient(const AValue: TFileName);
begin
  edtFirebirdClient.FileName := AValue;
end;

function TfrmConnectionSetting.GetDBUser: string;
begin
  Result := edtDBUser.Text;
end;

procedure TfrmConnectionSetting.SetDBUser(const AValue: string);
begin
  edtDBUser.Text := AValue;
end;

function TfrmConnectionSetting.GetDBPassword: string;
begin
  Result := edtDBPassword.Text;
end;

function TfrmConnectionSetting.GetFbCryptLibrary: string;
begin
  Result := edtFbCryptLibrary.Text;
end;

function TfrmConnectionSetting.GetDbKeyName: string;
begin
  Result := cbDBKeyName.Text;
end;

function TfrmConnectionSetting.GetDbKeyIndex: TDBKeyIndex;
begin
  Result := TDBKeyIndex(cbDBKeyName.ItemIndex);
end;

procedure TfrmConnectionSetting.SetDBPassword(const AValue: string);
begin
  edtDBPassword.Text := AValue;
end;

procedure TfrmConnectionSetting.SetFbCryptLibrary(const AValue: string);
begin
  edtFbCryptLibrary.Text := AValue;
end;

procedure TfrmConnectionSetting.SetDbKeyName(const AValue: string);
begin
  cbDBKeyName.Text := AValue;
end;

procedure TfrmConnectionSetting.SetDbKeyIndex(Index: TDBKeyIndex);
begin
  cbDBKeyName.ItemIndex := Integer(Index);
end;

end.


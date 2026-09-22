unit Main;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DB, Forms, Controls, Graphics, Dialogs, DBGrids, ComCtrls,
  ExtCtrls, StdCtrls, IB, IBDatabase, IBQuery, IBXServices, IBXCryptHelper,
  DatabaseKeys, DBCryptHelper;

type

  { TMainForm }

  TMainForm = class(TForm)
    btnOpen: TButton;
    btnClose: TButton;
    btnConnectionSettings: TButton;
    btnCrypt: TButton;
    btnDecrypt: TButton;
    btnGstat: TButton;
    btnSetupCustomKey: TButton;
    cbCryptKeyName: TComboBox;
    cbxTraceCrypt: TCheckBox;
    Database: TIBDatabase;
    DBGrid1: TDBGrid;
    DbGridSource: TDataSource;
    dbServiceConnection: TIBXServicesConnection;
    dbStatService: TIBXStatisticalService;
    Label1: TLabel;
    mmLog: TMemo;
    pnlCryptButtons: TPanel;
    pcMain: TPageControl;
    pnlToolButtons: TPanel;
    tsMain: TTabSheet;
    tsCrypt: TTabSheet;
    TestQuery: TIBQuery;
    ReadTransaction: TIBTransaction;
    procedure btnCloseClick(Sender: TObject);
    procedure btnConnectionSettingsClick(Sender: TObject);
    procedure btnCryptClick(Sender: TObject);
    procedure btnDecryptClick(Sender: TObject);
    procedure btnGstatClick(Sender: TObject);
    procedure btnOpenClick(Sender: TObject);
    procedure btnSetupCustomKeyClick(Sender: TObject);
    procedure DatabaseBeforeConnect(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
  private
    FBCryptHelper: TIBDatabaseCryptHelper;
    DBCryptKeyName: string;
    DBCryptKeyIndex: TDBKeyIndex;
    DBCryptCustomKeyName: string;
    DBCryptCustomKey: string;
    DBCryptCustomKeyBin: TDBKey;
  private
    function GetConfigFileName: TFileName;
    procedure ActiveConnectionControls;
    procedure InactiveConnectionControls;
    procedure LoadConnectionSettings;
    procedure SaveConnectionSettings;
    procedure FillDbKeyNames;
    function NewDatabaseConnection: TIBDatabase;
    procedure CryptMonitoring;
    procedure AddLogLine(const AText: string);
    procedure ThreadMonitoringTerminate(Sender: TObject);
  private
    property ConfigFileName: TFileName read GetConfigFileName;
  public

  end;

var
  MainForm: TMainForm;

implementation

uses ConnectionSettingsForm, SetupCustomKeyForm, IniFiles, EncryptionMonitorThread;

const
  CONNECTION_INI_SECTION = 'CONNECTION';
  FBCRYPT_INI_SECTION = 'FB_CRYPT';
  CUSTOM_KEY_INI_SECTION = 'CUSTOM_KEY';
  DEFAULT_CUSTOM_KEY_NAME = 'Custom';
  {$IFDEF WINDOWS}
  DEFAULT_FB_CLIENT = 'fbclient.dll';
  DEFAULT_LIB_FBCRYPT = 'fbcrypt.dll';
  {$ELSE}
  DEFAULT_FB_CLIENT = 'libfbclient.so';
  DEFAULT_LIB_FBCRYPT = 'libfbcrypt.so';
  {$ENDIF}

{$R *.lfm}

{ TMainForm }

procedure TMainForm.btnOpenClick(Sender: TObject);
begin
  ActiveConnectionControls;
  try
    Database.Open;
    ReadTransaction.StartTransaction;
    TestQuery.Open;
  except
    on E: Exception do
    begin
      if TestQuery.Active then
        TestQuery.Close;
      if ReadTransaction.InTransaction then
        ReadTransaction.Rollback;
      if Database.Connected then
        Database.Close;
      Application.ShowException(E);
      InactiveConnectionControls;
    end;
  end;
end;

procedure TMainForm.btnSetupCustomKeyClick(Sender: TObject);
var
  CustomKeyDlg: TfrmSetupCustomKey;
begin
  CustomKeyDlg := TfrmSetupCustomKey.Create(Self);
  try
    CustomKeyDlg.CustomKeyName := DBCryptCustomKeyName;
    CustomKeyDlg.CustomKey := DBCryptCustomKey;
    if CustomKeyDlg.ShowModal = mrOK then
    begin
      DBCryptCustomKeyName := CustomKeyDlg.CustomKeyName;
      DBCryptCustomKey := CustomKeyDlg.CustomKey;
      SaveConnectionSettings;
      FillDbKeyNames;
    end;
  finally
    CustomKeyDlg.Free;
  end;
end;

procedure TMainForm.DatabaseBeforeConnect(Sender: TObject);
var
  xPKey: PDBKey;
begin
  if DBCryptKeyIndex <> keyCustom then
    xPKey := GetDBKey(DBCryptKeyIndex)
  else
  begin
    xPKey := nil;
    // Parsing the custom key
    if ParseKeyHex(DBCryptCustomKey, DBCryptCustomKeyBin) then
      xPKey := @DBCryptCustomKeyBin;
  end;

  FBCryptHelper.SetDatabaseCryptKey(TIBDatabase(Sender), DBCryptKeyName, xPKey);
end;

procedure TMainForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  if TestQuery.Active then
    TestQuery.Close;
  if ReadTransaction.InTransaction then
    ReadTransaction.Rollback;
  if Database.Connected then
    Database.Close;

  CloseAction := caFree;
end;

procedure TMainForm.FormCreate(Sender: TObject);
begin
  FBCryptHelper := TIBDatabaseCryptHelper.Create(Self);
  DBCryptKeyIndex := keyNone;
  DBCryptCustomKeyBin := ZeroKey;
  LoadConnectionSettings;
  FillDbKeyNames;
end;

procedure TMainForm.FormShow(Sender: TObject);
begin
  pcMain.ActivePageIndex := 0;
  MainForm.Caption := 'Firebird crypt example: ' + Database.DatabaseName;
end;

function TMainForm.GetConfigFileName: TFileName;
begin
  Result := ChangeFileExt(Application.ExeName, '.ini');
end;

procedure TMainForm.btnCloseClick(Sender: TObject);
begin
  InactiveConnectionControls;
  if TestQuery.Active then
    TestQuery.Close;
  if ReadTransaction.InTransaction then
    ReadTransaction.Rollback;
  if Database.Connected then
    Database.Close;
end;

procedure TMainForm.btnConnectionSettingsClick(Sender: TObject);
var
  ConnectionSettingDialog: TfrmConnectionSetting;
begin
  ConnectionSettingDialog := TfrmConnectionSetting.Create(Self);
  try
    ConnectionSettingDialog.Database := Database.DatabaseName;
    ConnectionSettingDialog.FirebirdClient := Database.FirebirdLibraryPathName;

    ConnectionSettingDialog.DBUser := Database.Params.Values['user_name'];
    ConnectionSettingDialog.DBPassword := Database.Params.Values['password'];
    ConnectionSettingDialog.DBRole := Database.Params.Values['sql_role_name'];
    ConnectionSettingDialog.DBCharset := Database.Params.Values['lc_ctype'];

    ConnectionSettingDialog.CustomKeyName := DBCryptCustomKeyName;
    ConnectionSettingDialog.FbCryptLibrary := FBCryptHelper.LibraryPath;
    ConnectionSettingDialog.DbKeyName := DBCryptKeyName;

    if ConnectionSettingDialog.ShowModal = mrOK then
    begin
      Database.ForceClose;

      Database.DatabaseName := ConnectionSettingDialog.Database;
      Database.FirebirdLibraryPathName := ConnectionSettingDialog.FirebirdClient;

      Database.Params.Clear;
      Database.Params.Values['user_name'] := ConnectionSettingDialog.DBUser;
      Database.Params.Values['password'] := ConnectionSettingDialog.DBPassword;
      Database.Params.Values['sql_role_name'] := ConnectionSettingDialog.DBRole;
      Database.Params.Values['lc_ctype'] := ConnectionSettingDialog.DBCharset;

      FBCryptHelper.LibraryPath := ConnectionSettingDialog.FbCryptLibrary;
      DBCryptKeyName := ConnectionSettingDialog.DbKeyName;
      DBCryptKeyIndex := ConnectionSettingDialog.DbKeyIndex;

      SaveConnectionSettings;

      MainForm.Caption := 'Firebird crypt example: ' + Database.DatabaseName;
    end;
  finally
    ConnectionSettingDialog.Free;
  end;
end;

procedure TMainForm.btnCryptClick(Sender: TObject);
var
  xCryptConnection: TIBDatabase;
  xCryptAttachment: IAttachment;
  xCryptSql: string;
  xStartMonitorFlag: Boolean;
begin
  btnCrypt.Enabled := False;
  btnDecrypt.Enabled := False;
  cbCryptKeyName.Enabled := False;
  btnGstat.Enabled := False;
  cbxTraceCrypt.Enabled := False;

  mmLog.Lines.Clear;

  DBCryptKeyName := cbCryptKeyName.Text;
  DBCryptKeyIndex := TDBKeyIndex(cbCryptKeyName.ItemIndex + 1);
  xCryptSql := 'ALTER DATABASE ENCRYPT WITH "dbcrypt" KEY "' + DBCryptKeyName + '"';

  mmLog.Lines.Add('Initiating database encryption with key: ' + DBCryptKeyName);
  try
    // Use a separate connection for encryption,
    // with parameters cloned from the main connection.
    xCryptConnection := NewDatabaseConnection;
    try
      xCryptConnection.Open;
      xCryptAttachment := xCryptConnection.Attachment;
      mmLog.Lines.Add('Execute SQL: ' + xCryptSql);
      xCryptAttachment.ExecImmediate(
        [isc_tpb_write, isc_tpb_nowait, isc_tpb_read_committed, isc_tpb_rec_version],
        xCryptSql
      );
      xStartMonitorFlag := True;
      mmLog.Lines.Add('The database has been successfully switched to encryption mode.');
    finally
      xCryptAttachment := nil;
      if xCryptConnection.Connected then xCryptConnection.Close;
      xCryptConnection.Free;
    end;
  except
    on E: Exception do
    begin
      xStartMonitorFlag := False;
      mmLog.Lines.Add('Error: ' + E.Message);
    end;
  end;

  if cbxTraceCrypt.Checked and xStartMonitorFlag then
    CryptMonitoring
  else
  begin
    cbxTraceCrypt.Enabled := True;
    btnCrypt.Enabled := True;
    btnDecrypt.Enabled := True;
    cbCryptKeyName.Enabled := True;
    btnGstat.Enabled := True;
  end;
end;

procedure TMainForm.btnDecryptClick(Sender: TObject);
var
  xDecryptConnection: TIBDatabase;
  xDecryptAttachment: IAttachment;
  xDecryptSql: string;
  xStartMonitorFlag: Boolean;
begin
  btnCrypt.Enabled := False;
  btnDecrypt.Enabled := False;
  cbCryptKeyName.Enabled := False;
  btnGstat.Enabled := False;
  cbxTraceCrypt.Enabled := False;

  mmLog.Lines.Clear;

  xDecryptSql := 'ALTER DATABASE DECRYPT';
  mmLog.Lines.Add('Initiating database decryption');
  try
    // Use a separate connection for decryption,
    // with parameters cloned from the main connection.
    xDecryptConnection := NewDatabaseConnection;
    try
      xDecryptConnection.Open;
      xDecryptAttachment := xDecryptConnection.Attachment;
      mmLog.Lines.Add('Execute SQL: ' + xDecryptSql);
      xDecryptAttachment.ExecImmediate(
        [isc_tpb_write, isc_tpb_nowait, isc_tpb_read_committed, isc_tpb_rec_version],
        xDecryptSql
      );
      xStartMonitorFlag := True;
      mmLog.Lines.Add('The database has been successfully switched to decryption mode.');
    finally
      xDecryptAttachment := nil;
      if xDecryptConnection.Connected then xDecryptConnection.Close;
      xDecryptConnection.Free;
    end;
  except
    on E: Exception do
    begin
      xStartMonitorFlag := False;
      mmLog.Lines.Add('Error: ' + E.Message);
    end;
  end;

  if cbxTraceCrypt.Checked and xStartMonitorFlag then
    CryptMonitoring
  else
  begin
    cbxTraceCrypt.Enabled := True;
    btnCrypt.Enabled := True;
    btnDecrypt.Enabled := True;
    cbCryptKeyName.Enabled := True;
    btnGstat.Enabled := True;
  end;
end;

procedure TMainForm.btnGstatClick(Sender: TObject);
var
  xConnectFlag: Boolean;
begin
  mmLog.Clear;
  xConnectFlag := Database.Connected;
  try
    try
      dbServiceConnection.Params.Clear;
      // TODO: The login and password for the services may differ from the database login and password.
      dbServiceConnection.Params.Values['user_name'] := Database.Params.Values['user_name'];
      dbServiceConnection.Params.Values['password'] := Database.Params.Values['password'];

      if not xConnectFlag then
        Database.Open;
      dbServiceConnection.ConnectUsing(Database);
      dbStatService.Execute(mmLog.Lines);
    except
      on E: Exception do
        mmLog.Lines.Add('Error: ' + E.Message);
    end;
  finally
    dbServiceConnection.Close;
    if not xConnectFlag then
      Database.Close;
  end;
end;

procedure TMainForm.ActiveConnectionControls;
begin
  btnOpen.Enabled := False;
  btnClose.Enabled := True;
  btnConnectionSettings.Enabled := False;
  btnSetupCustomKey.Enabled := False;
end;

procedure TMainForm.InactiveConnectionControls;
begin
  btnOpen.Enabled := True;
  btnClose.Enabled := False;
  btnConnectionSettings.Enabled := True;
  btnSetupCustomKey.Enabled := True;
end;

procedure TMainForm.LoadConnectionSettings;
var
  xIniFile: TIniFile;
begin
  xIniFile := TIniFile.Create(ConfigFileName);
  try
    Database.DatabaseName := xIniFile.ReadString(CONNECTION_INI_SECTION, 'DATABASE', 'inet://localhost/crypt');
    Database.FirebirdLibraryPathName := xIniFile.ReadString(CONNECTION_INI_SECTION, 'FBCLIENT', DEFAULT_FB_CLIENT);

    Database.Params.Clear;
    Database.Params.Values['user_name'] := xIniFile.ReadString(CONNECTION_INI_SECTION, 'USER', 'SYSDBA');
    Database.Params.Values['password'] := xIniFile.ReadString(CONNECTION_INI_SECTION, 'PASSWORD', 'masterkey');
    Database.Params.Values['sql_role_name'] := xIniFile.ReadString(CONNECTION_INI_SECTION, 'ROLE', 'NONE');
    Database.Params.Values['lc_ctype'] := xIniFile.ReadString(CONNECTION_INI_SECTION, 'CHARSET', 'UTF8');

    // Load FbCrypt settings
    FBCryptHelper.LibraryPath := xIniFile.ReadString(FBCRYPT_INI_SECTION, 'LIB_FBCRYPT', DEFAULT_LIB_FBCRYPT);
    DBCryptKeyName := xIniFile.ReadString(FBCRYPT_INI_SECTION, 'KEY_NAME', 'None');
    DBCryptKeyIndex := GetDBKeyIndexByName(DBCryptKeyName);

    // Load Custom Key
    DBCryptCustomKeyName := xIniFile.ReadString(CUSTOM_KEY_INI_SECTION, 'KEY_NAME', DEFAULT_CUSTOM_KEY_NAME);
    DBCryptCustomKey := xIniFile.ReadString(CUSTOM_KEY_INI_SECTION, 'KEY', '');
  finally
    xIniFile.Free;
  end;
end;

procedure TMainForm.SaveConnectionSettings;
var
  xIniFile: TIniFile;
begin
  xIniFile := TIniFile.Create(ConfigFileName);
  try
    xIniFile.WriteString(CONNECTION_INI_SECTION, 'DATABASE', Database.DatabaseName);
    xIniFile.WriteString(CONNECTION_INI_SECTION, 'FBCLIENT', Database.FirebirdLibraryPathName);

    xIniFile.WriteString(CONNECTION_INI_SECTION, 'USER', Database.Params.Values['user_name']);
    xIniFile.WriteString(CONNECTION_INI_SECTION, 'PASSWORD', Database.Params.Values['password']);
    xIniFile.WriteString(CONNECTION_INI_SECTION, 'ROLE', Database.Params.Values['sql_role_name']);
    xIniFile.WriteString(CONNECTION_INI_SECTION, 'CHARSET', Database.Params.Values['lc_ctype']);

    // Save FbCrypt settings
    xIniFile.WriteString(FBCRYPT_INI_SECTION, 'LIB_FBCRYPT', FBCryptHelper.LibraryPath);
    xIniFile.WriteString(FBCRYPT_INI_SECTION, 'KEY_NAME', DBCryptKeyName);

    // Save Custom Key
    xIniFile.WriteString(CUSTOM_KEY_INI_SECTION, 'KEY_NAME', DBCryptCustomKeyName);
    xIniFile.WriteString(CUSTOM_KEY_INI_SECTION, 'KEY', DBCryptCustomKey);
  finally
    xIniFile.Free;
  end;
end;

procedure TMainForm.FillDbKeyNames;
var
  xKeyIndex: TDBKeyIndex;
begin
  cbCryptKeyName.Items.Clear;
  for xKeyIndex := Succ(Low(TDBKeyIndex)) to High(TDBKeyIndex) do
  begin
    if xKeyIndex <> keyCustom then
      cbCryptKeyName.Items.Add(DBKeyNames[xKeyIndex])
    else
      cbCryptKeyName.Items.Add(DBCryptCustomKeyName);
  end;
  cbCryptKeyName.ItemIndex := 0;
end;

function TMainForm.NewDatabaseConnection: TIBDatabase;
begin
  Result := TIBDatabase.Create(Self);

  Result.LoginPrompt := False;
  Result.DatabaseName := Database.DatabaseName;
  Result.FirebirdLibraryPathName := Database.FirebirdLibraryPathName;

  Result.Params.Assign(Database.Params);

  Result.BeforeConnect := @DatabaseBeforeConnect;
end;

procedure TMainForm.CryptMonitoring;
var
  xMonitorThread:  TEncryptionMonitorThread;
begin
  xMonitorThread := TEncryptionMonitorThread.Create(Database);
  xMonitorThread.OnProgress := @AddLogLine;
  xMonitorThread.Start;
  xMonitorThread.OnTerminate := @ThreadMonitoringTerminate;
end;

procedure TMainForm.AddLogLine(const AText: string);
begin
  mmLog.Lines.Add(AText);
end;

procedure TMainForm.ThreadMonitoringTerminate(Sender: TObject);
begin
  btnCrypt.Enabled := True;
  btnDecrypt.Enabled := True;
  cbCryptKeyName.Enabled := True;
  btnGstat.Enabled := True;
  cbxTraceCrypt.Enabled := True;
end;

end.


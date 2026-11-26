unit MainFormU;

{ Scenarios S1, S5 and S8: a VCL form with FireDAC and fbcrypt.

  S1: connection to an encrypted database. Key transfer method A: fbcrypt registers the
      key callback in the thread that opens the connection.
  S5: encryption, decryption and change of the key. The progress comes from MON$DATABASE.
  S8: the key typed by the user, read from a key file, or from a file protected with DPAPI.

  Firebird 4.0 and 5.0 keep the state in MON$DATABASE.MON$CRYPT_STATE.
  Firebird 3.0 has no such column: Encrypt, Decrypt and Change key need Firebird 4.0 or 5.0.
  Connection and reading of data work with Firebird 3.0 too.

  Rules that the example shows:
    * the encryption thread of the server works only while a connection to the database is open;
    * monitoring data does not change inside a transaction: every poll is a new transaction;
    * to change the key, decrypt the database and encrypt it with the new key.

  The command line switch --test runs scenario S5 on the database work of the test server
  without a window. It prints the same lines as the examples in other languages. }

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.UITypes, System.IOUtils, Vcl.Graphics, Vcl.Controls,
  Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.FileCtrl, Vcl.Grids, Vcl.DBGrids,
  Data.DB, FireDAC.Stan.Intf, FireDAC.Stan.Def, FireDAC.Stan.Async, FireDAC.Stan.Error,
  FireDAC.Stan.Param, FireDAC.DApt, FireDAC.Comp.Client, FireDAC.Comp.DataSet, FireDAC.Phys.FB,
  FireDAC.Phys.IBBase, FireDAC.Phys.IBDef, FireDAC.VCLUI.Wait, FbCryptApi, ExampleCommon, KeyStorageU;

type
  TMainForm = class(TForm)
    ConnectionBox: TGroupBox;
    Label1: TLabel;
    ClientDirEdit: TEdit;
    BrowseClientButton: TButton;
    Label2: TLabel;
    ServerEdit: TEdit;
    Label3: TLabel;
    PortEdit: TEdit;
    Label4: TLabel;
    DatabaseEdit: TEdit;
    Label5: TLabel;
    UserEdit: TEdit;
    Label6: TLabel;
    PasswordEdit: TEdit;
    Label9: TLabel;
    SqlEdit: TEdit;
    KeyBox: TGroupBox;
    Label7: TLabel;
    KeyNameEdit: TEdit;
    Label8: TLabel;
    KeyValueEdit: TEdit;
    ShowKeyCheckBox: TCheckBox;
    UseKeyCheckBox: TCheckBox;
    LoadKeyButton: TButton;
    SaveKeyButton: TButton;
    ConnectButton: TButton;
    DisconnectButton: TButton;
    EncryptButton: TButton;
    DecryptButton: TButton;
    ChangeKeyButton: TButton;
    StateLabel: TLabel;
    ProgressBar1: TProgressBar;
    LogMemo: TMemo;
    DemoGrid: TDBGrid;
    DataSource1: TDataSource;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure BrowseClientButtonClick(Sender: TObject);
    procedure ShowKeyCheckBoxClick(Sender: TObject);
    procedure LoadKeyButtonClick(Sender: TObject);
    procedure SaveKeyButtonClick(Sender: TObject);
    procedure ConnectButtonClick(Sender: TObject);
    procedure DisconnectButtonClick(Sender: TObject);
    procedure EncryptButtonClick(Sender: TObject);
    procedure DecryptButtonClick(Sender: TObject);
    procedure ChangeKeyButtonClick(Sender: TObject);
  private
    FFbCrypt: TFbCrypt;
    FClientDir: string;
    FLink: TFDPhysFBDriverLink;
    FConnection: TFDConnection;
    FMonQuery: TFDQuery;
    FDemoQuery: TFDQuery;
    FBusy: Boolean;
    FHasCryptState: Boolean;
    FState: Integer;
    FPages: Integer;
    function ReadCryptState: Boolean;
    procedure RunStatement(const ASql: string);
    function WaitState(AWanted: Integer): string;
    procedure ShowProgress(AState, APages, APagesAtStart: Integer);
    procedure Log(const AText: string);
    procedure OpenData;
    procedure SetBusy(AValue: Boolean);
    procedure UpdateButtons;
    procedure ShowError(E: Exception);
    procedure OpenConnection;
  public
    { Opens the connection with the values from the form. }
    procedure Connect;
    procedure Disconnect;
    { Scenario S5. Each method waits until the encryption thread of the server finishes. }
    function EncryptDatabase(const AKeyName: string): string;
    function DecryptDatabase: string;
    function ChangeKey(const AKeyName: string; const AKey: TBytes): string;
    { Scenario S5 without the window: the values come from test-env.ps1,
      the output is the same as in the examples in other languages. }
    procedure RunTest;
    { Writes a line to the standard output of the process. Does nothing in the window mode. }
    procedure Print(const AText: string);
  end;

var
  MainForm: TMainForm;

implementation

{$R *.dfm}

const
  StNotEncrypted = 0;
  StEncrypted = 1;
  StDecrypting = 2;
  StEncrypting = 3;

function StateText(AState: Integer): string;
begin
  case AState of
    StNotEncrypted: Result := 'not encrypted';
    StEncrypted: Result := 'encrypted';
    StDecrypting: Result := 'decryption in progress';
    StEncrypting: Result := 'encryption in progress';
  else
    Result := 'unknown (' + IntToStr(AState) + ')';
  end;
end;

{ The key name goes into the text of a statement: it must be a plain identifier. }
function IsIdentifier(const AText: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  if (AText = '') or not CharInSet(AText[1], ['A'..'Z', 'a'..'z', '_']) then
    Exit;
  for I := 2 to Length(AText) do
    if not CharInSet(AText[I], ['A'..'Z', 'a'..'z', '0'..'9', '_']) then
      Exit;
  Result := True;
end;

{ Scenario S8 for the test mode: writes a key to a DPAPI protected file and to a text file
  in the current folder for temporary files, reads them back and compares. }
procedure CheckKeyStorage(const AKey: TBytes);
var
  FileName: string;
  Entries: TKeyFileEntries;
begin
  FileName := TPath.Combine(TPath.GetTempPath, 'vcl-firedac-test.key');
  try
    SaveKeyDpapiFile(FileName, 'TestKey', AKey);
    if not IsDpapiFile(FileName) then
      raise Exception.Create('The DPAPI protected key file has no signature.');
    if not ReadKeyDpapiFile(FileName, Entries) then
      raise Exception.Create('The DPAPI protected key file is not read back.');
    if (Length(Entries) <> 1) or (Entries[0].KeyName <> 'TestKey') or
       not CompareMem(@Entries[0].KeyValue[0], @AKey[0], Length(AKey)) then
      raise Exception.Create('The DPAPI protected key file gives another key.');
    SaveKeyTextFile(FileName, 'TestKey', AKey);
    if IsDpapiFile(FileName) then
      raise Exception.Create('The text key file is taken for a DPAPI protected file.');
    Entries := ReadKeyTextFile(FileName);
    if (Length(Entries) <> 1) or (Entries[0].KeyName <> 'TestKey') or
       not CompareMem(@Entries[0].KeyValue[0], @AKey[0], Length(AKey)) then
      raise Exception.Create('The text key file gives another key.');
  finally
    System.SysUtils.DeleteFile(FileName);
  end;
end;

{ TMainForm }

procedure TMainForm.FormCreate(Sender: TObject);
begin
  FHasCryptState := True;
  FConnection := TFDConnection.Create(Self);
  FConnection.DriverName := 'FB';
  FConnection.LoginPrompt := False;
  FMonQuery := TFDQuery.Create(Self);
  FMonQuery.Connection := FConnection;
  FDemoQuery := TFDQuery.Create(Self);
  FDemoQuery.Connection := FConnection;
  DataSource1.DataSet := FDemoQuery;
  UpdateButtons;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  // The libraries stay loaded: fbclient keeps the pointer to the callback of fbcrypt.
  FreeAndNil(FFbCrypt);
end;

procedure TMainForm.Print(const AText: string);
var
  Handle: THandle;
  S: AnsiString;
  Written: DWORD;
begin
  Handle := GetStdHandle(STD_OUTPUT_HANDLE);
  if (Handle = 0) or (Handle = INVALID_HANDLE_VALUE) then
    Exit;
  S := AnsiString(AText) + #13#10;
  WriteFile(Handle, S[1], Length(S), Written, nil);
end;

procedure TMainForm.Log(const AText: string);
begin
  LogMemo.Lines.Add(AText);
end;

procedure TMainForm.ShowError(E: Exception);
begin
  Log('ERROR: ' + E.Message);
  MessageDlg(E.Message, mtError, [mbOK], 0);
end;

procedure TMainForm.SetBusy(AValue: Boolean);
begin
  FBusy := AValue;
  UpdateButtons;
end;

procedure TMainForm.UpdateButtons;
var
  Connected: Boolean;
begin
  Connected := FConnection.Connected;
  ConnectButton.Enabled := not FBusy and not Connected;
  DisconnectButton.Enabled := not FBusy and Connected;
  EncryptButton.Enabled := not FBusy and Connected and FHasCryptState;
  DecryptButton.Enabled := EncryptButton.Enabled;
  ChangeKeyButton.Enabled := EncryptButton.Enabled;
  if Connected then
    StateLabel.Caption := 'Connected'
  else
    StateLabel.Caption := 'Not connected';
end;

procedure TMainForm.OpenConnection;
begin
  FConnection.Params.Values['Server'] := Trim(ServerEdit.Text);
  FConnection.Params.Values['Port'] := Trim(PortEdit.Text);
  FConnection.Params.Values['Database'] := Trim(DatabaseEdit.Text);
  FConnection.Params.Values['User_Name'] := Trim(UserEdit.Text);
  FConnection.Params.Values['Password'] := PasswordEdit.Text;
  // The callback must be registered in the thread that opens the connection.
  if UseKeyCheckBox.Checked then
    FFbCrypt.RegisterForThread;
  FConnection.Connected := True;
end;

procedure TMainForm.Connect;
var
  ClientDir: string;
begin
  ClientDir := Trim(ClientDirEdit.Text);
  if FFbCrypt = nil then
  begin
    // FireDAC and fbcrypt must use the same fbclient: the one in the client folder.
    FLink := TFDPhysFBDriverLink.Create(Self);
    FLink.VendorHome := ClientDir;
    FLink.VendorLib := 'fbclient.dll';
    FFbCrypt := TFbCrypt.Create(ClientDir);
    FClientDir := ClientDir;
  end
  else if not SameText(ClientDir, FClientDir) then
    raise Exception.Create('The client folder is changed. fbcrypt is already loaded from ' +
      FClientDir + '. Restart the program to use another folder.');

  if UseKeyCheckBox.Checked then
  begin
    // The key list is global for the process. It holds the keys of this program only.
    FFbCrypt.ClearKeys;
    FFbCrypt.AddKey(Trim(KeyNameEdit.Text), ParseKeyHex(KeyValueEdit.Text));
  end;
  OpenConnection;
  ReadCryptState;
  if not FHasCryptState then
    Log('This server has no MON$CRYPT_STATE (Firebird 3.0). ' +
      'Encrypt, Decrypt and Change key need Firebird 4.0 or 5.0.');
  OpenData;
  UpdateButtons;
end;

procedure TMainForm.Disconnect;
begin
  FDemoQuery.Close;
  FConnection.Connected := False;
  UpdateButtons;
end;

procedure TMainForm.OpenData;
begin
  FDemoQuery.Close;
  if Trim(SqlEdit.Text) = '' then
    Exit;
  try
    FDemoQuery.Open(Trim(SqlEdit.Text));
  except
    on E: Exception do
      // The database may have no table demo. The SQL is in the field of the form.
      Log('Data is not opened: ' + E.Message);
  end;
end;

{ Reads MON$DATABASE into FState and FPages.
  Returns False when the server has no MON$CRYPT_STATE (Firebird 3.0). }
function TMainForm.ReadCryptState: Boolean;
begin
  Result := False;
  FState := -1;
  FPages := 0;
  if (not FConnection.Connected) or (not FHasCryptState) then
    Exit;
  try
    FMonQuery.Open('select mon$crypt_state, mon$crypt_page from mon$database');
    try
      FState := FMonQuery.Fields[0].AsInteger;
      FPages := FMonQuery.Fields[1].AsInteger;
    finally
      FMonQuery.Close;
    end;
  except
    on E: EFDException do
    begin
      FHasCryptState := False; // Firebird 3.0: column unknown
      Exit;
    end;
  end;
  FHasCryptState := True;
  // Monitoring data does not change inside a transaction: end it to get new data next time.
  if FConnection.InTransaction then
    FConnection.Commit;
  Result := True;
end;

procedure TMainForm.RunStatement(const ASql: string);
begin
  FDemoQuery.Close;
  FMonQuery.ExecSQL(ASql);
  FConnection.Commit;
end;

procedure TMainForm.ShowProgress(AState, APages, APagesAtStart: Integer);
var
  Percent: Integer;
begin
  if (AState in [StDecrypting, StEncrypting]) and (APagesAtStart > 0) then
    Percent := Round(100 * (APagesAtStart - APages) / APagesAtStart)
  else
    Percent := 100;
  ProgressBar1.Position := Percent;
  StateLabel.Caption := StateText(AState) + ', pages left: ' + IntToStr(APages);
end;

{ Keeps the connection open until the state of the database is AWanted. }
function TMainForm.WaitState(AWanted: Integer): string;
const
  PauseMs = 200;
  TimeoutMs = 120000;
var
  PagesAtStart, SameCount: Integer;
  Ticks: Cardinal;
begin
  PagesAtStart := -1;
  SameCount := 0;
  Ticks := GetTickCount;
  while True do
  begin
    if not ReadCryptState then
      raise Exception.Create('This server has no MON$CRYPT_STATE (Firebird 3.0). ' +
        'Encrypt, Decrypt and Change key need Firebird 4.0 or 5.0.');
    if (PagesAtStart < 0) and (FState in [StDecrypting, StEncrypting]) then
      PagesAtStart := FPages;
    ShowProgress(FState, FPages, PagesAtStart);
    // Two equal answers in a row exclude an old snapshot.
    if FState = AWanted then
      Inc(SameCount)
    else
      SameCount := 0;
    if SameCount >= 2 then
      Exit(StateText(FState));
    if GetTickCount - Ticks > TimeoutMs then
      raise Exception.CreateFmt('Timeout: state %s, pages left %d', [StateText(FState), FPages]);
    Sleep(PauseMs);
    Application.ProcessMessages;
  end;
end;

function TMainForm.EncryptDatabase(const AKeyName: string): string;
begin
  if not IsIdentifier(AKeyName) then
    raise Exception.Create('The key name must consist of letters, digits and underscores.');
  // The plugin name is in double quotes: on Linux the name is case-sensitive.
  // The connection must stay open: the encryption thread works only while it is open.
  RunStatement('alter database encrypt with "DbCrypt" key ' + AKeyName);
  Result := WaitState(StEncrypted);
end;

function TMainForm.DecryptDatabase: string;
begin
  RunStatement('alter database decrypt');
  Result := WaitState(StNotEncrypted);
end;

function TMainForm.ChangeKey(const AKeyName: string; const AKey: TBytes): string;
begin
  // The list keeps the old key too: it is needed to decrypt the database.
  FFbCrypt.AddKey(AKeyName, AKey);
  // A new attachment sends the key list to the server again.
  Disconnect;
  OpenConnection;
  DecryptDatabase;
  Result := EncryptDatabase(AKeyName);
end;

procedure TMainForm.RunTest;
var
  Green: TBytes;
begin
  ClientDirEdit.Text := Env('FBCRYPT_CLIENT');
  ServerEdit.Text := Env('FBCRYPT_HOST');
  PortEdit.Text := Env('FBCRYPT_PORT');
  DatabaseEdit.Text := 'work';
  UserEdit.Text := Env('FBCRYPT_USER');
  PasswordEdit.Text := Env('FBCRYPT_PASSWORD');
  SqlEdit.Text := 'select note from demo where id = 1';
  KeyNameEdit.Text := 'Red';
  KeyValueEdit.Text := KeyText(ReadKey('Red'));
  UseKeyCheckBox.Checked := True;
  Green := ReadKey('Green');
  CheckKeyStorage(Green);

  Connect;
  if not FHasCryptState then
    raise Exception.Create('Scenario S5 needs Firebird 4.0 or 5.0.');
  FFbCrypt.AddKey('Green', Green);

  // A previous run could stop in the middle. Return the database to the start state.
  if FState <> StNotEncrypted then
    DecryptDatabase;
  ReadCryptState;
  Print('State at start: ' + StateText(FState));

  Print('Encrypt with key Red: ' + EncryptDatabase('Red'));

  // A new connection reads the encrypted database with the key Red.
  Disconnect;
  OpenConnection;
  OpenData;
  Print('Read data: ' + FDemoQuery.Fields[0].AsString);

  Print('Change key to Green: ' + ChangeKey('Green', Green));

  Print('Decrypt: ' + DecryptDatabase);
  Disconnect;
end;

procedure TMainForm.BrowseClientButtonClick(Sender: TObject);
var
  Dir: string;
begin
  Dir := Trim(ClientDirEdit.Text);
  if SelectDirectory('Folder with fbclient.dll, fbcrypt.dll and libcrypto', '', Dir,
      [sdNewUI, sdNewFolder, sdShowEdit, sdShowShares, sdShowFiles, sdValidateDir], Self) then
    ClientDirEdit.Text := Dir;
end;

procedure TMainForm.ShowKeyCheckBoxClick(Sender: TObject);
begin
  if ShowKeyCheckBox.Checked then
    KeyValueEdit.PasswordChar := #0
  else
    KeyValueEdit.PasswordChar := '*';
end;

procedure TMainForm.LoadKeyButtonClick(Sender: TObject);
var
  Dialog: TFileOpenDialog;
  Entries: TKeyFileEntries;
begin
  Dialog := TFileOpenDialog.Create(Self);
  try
    Dialog.Title := 'Key file: the format of KeyHolder.conf or a DPAPI protected file';
    Dialog.Options := Dialog.Options + [fdoFileMustExist, fdoPathMustExist];
    if not Dialog.Execute then
      Exit;
    if IsDpapiFile(Dialog.FileName) then
    begin
      if not ReadKeyDpapiFile(Dialog.FileName, Entries) then
        raise Exception.Create('The file was protected by another Windows user or on another computer.');
    end
    else
      Entries := ReadKeyTextFile(Dialog.FileName);
    if Length(Entries) = 0 then
      raise Exception.Create('The file has no line of the form Key=<name> 0x..,0x..,');
    KeyNameEdit.Text := Entries[0].KeyName;
    KeyValueEdit.Text := KeyText(Entries[0].KeyValue);
    UseKeyCheckBox.Checked := True;
    Log('Key ' + Entries[0].KeyName + ' is read from ' + Dialog.FileName);
  finally
    Dialog.Free;
  end;
end;

procedure TMainForm.SaveKeyButtonClick(Sender: TObject);
var
  Dialog: TFileSaveDialog;
begin
  Dialog := TFileSaveDialog.Create(Self);
  try
    Dialog.Title := 'Key file protected with DPAPI';
    Dialog.DefaultExtension := 'key';
    if not Dialog.Execute then
      Exit;
    SaveKeyDpapiFile(Dialog.FileName, Trim(KeyNameEdit.Text), ParseKeyHex(KeyValueEdit.Text));
    Log('Key ' + Trim(KeyNameEdit.Text) + ' is saved to ' + Dialog.FileName +
      ' (only the current Windows user can read it)');
  finally
    Dialog.Free;
  end;
end;

procedure TMainForm.ConnectButtonClick(Sender: TObject);
begin
  try
    Connect;
    if FHasCryptState then
      Log('Connected. State of the database: ' + StateText(FState));
  except
    on E: Exception do
      ShowError(E);
  end;
  UpdateButtons;
end;

procedure TMainForm.DisconnectButtonClick(Sender: TObject);
begin
  Disconnect;
  Log('Disconnected');
end;

procedure TMainForm.EncryptButtonClick(Sender: TObject);
var
  KeyName: string;
begin
  KeyName := Trim(KeyNameEdit.Text);
  SetBusy(True);
  try
    try
      Log('Encrypt with key ' + KeyName + ': ' + EncryptDatabase(KeyName));
    except
      on E: Exception do
        ShowError(E);
    end;
  finally
    SetBusy(False);
  end;
end;

procedure TMainForm.DecryptButtonClick(Sender: TObject);
begin
  SetBusy(True);
  try
    try
      Log('Decrypt: ' + DecryptDatabase);
    except
      on E: Exception do
        ShowError(E);
    end;
  finally
    SetBusy(False);
  end;
end;

procedure TMainForm.ChangeKeyButtonClick(Sender: TObject);
var
  NewName, NewValue: string;
  NewKey: TBytes;
begin
  NewName := Trim(KeyNameEdit.Text);
  if not InputQuery('Change key', 'New key name:', NewName) then
    Exit;
  NewValue := '';
  if not InputQuery('Change key', 'New key value (0x..,0x..,):', NewValue) then
    Exit;
  SetBusy(True);
  try
    try
      NewKey := ParseKeyHex(NewValue);
      Log('Change key to ' + NewName + ': ' + ChangeKey(NewName, NewKey));
      KeyNameEdit.Text := NewName;
      KeyValueEdit.Text := KeyText(NewKey);
    except
      on E: Exception do
        ShowError(E);
    end;
  finally
    SetBusy(False);
  end;
end;

end.

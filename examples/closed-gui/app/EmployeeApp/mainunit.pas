unit mainunit;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, ComCtrls,
  DBGrids, DBCtrls, DB, SQLDB, IBConnection, ibase60dyn, IniFiles;

type

  { TMainForm }

  TMainForm = class(TForm)
    ConnectionBox: TGroupBox;
    HostLabel: TLabel;
    HostEdit: TEdit;
    PortLabel: TLabel;
    PortEdit: TEdit;
    DatabaseLabel: TLabel;
    DatabaseEdit: TEdit;
    UserLabel: TLabel;
    UserEdit: TEdit;
    PasswordLabel: TLabel;
    PasswordEdit: TEdit;
    ConnectButton: TButton;
    DisconnectButton: TButton;
    Navigator: TDBNavigator;
    Grid: TDBGrid;
    BottomPanel: TPanel;
    SaveButton: TButton;
    CancelButton: TButton;
    MessageMemo: TMemo;
    StatusBar: TStatusBar;
    Connection: TIBConnection;
    Transaction: TSQLTransaction;
    Query: TSQLQuery;
    DataSource: TDataSource;
    procedure CancelButtonClick(Sender: TObject);
    procedure ConnectButtonClick(Sender: TObject);
    procedure DisconnectButtonClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
    procedure SaveButtonClick(Sender: TObject);
  private
    function AppDir: string;
    procedure LoadSettings;
    procedure SaveSettings;
    procedure OpenDatabase;
    procedure CloseDatabase;
    procedure SaveChanges;
    procedure CancelChanges;
    function ServerInfo: string;
    procedure Say(const Msg: string);
    procedure UpdateControls;
  public
    function SelfTest: Boolean;
  end;

var
  MainForm: TMainForm;

implementation

{$R *.lfm}

const
  IniName = 'EmployeeApp.ini';
  IniSection = 'Connection';

{ TMainForm }

function TMainForm.AppDir: string;
begin
  Result := ExtractFilePath(ParamStr(0));
end;

procedure TMainForm.FormCreate(Sender: TObject);
begin
  // The application loads the Firebird client library from its own folder.
  InitialiseIBase60(AppDir + 'fbclient.dll');
  {$IFDEF EMBEDDED}
  Caption := 'Employee (embedded)';
  HostLabel.Visible := False;
  HostEdit.Visible := False;
  PortLabel.Visible := False;
  PortEdit.Visible := False;
  PasswordLabel.Visible := False;
  PasswordEdit.Visible := False;
  DatabaseLabel.Left := HostLabel.Left;
  DatabaseEdit.Left := HostEdit.Left;
  DatabaseEdit.Width := ConnectionBox.ClientWidth - DatabaseEdit.Left - 12;
  {$ELSE}
  Caption := 'Employee';
  {$ENDIF}
  LoadSettings;
  UpdateControls;
end;

procedure TMainForm.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  SaveSettings;
  CloseDatabase;
end;

procedure TMainForm.LoadSettings;
var
  Ini: TIniFile;
begin
  Ini := TIniFile.Create(AppDir + IniName);
  try
    HostEdit.Text := Ini.ReadString(IniSection, 'Host', 'localhost');
    PortEdit.Text := Ini.ReadString(IniSection, 'Port', '3050');
    {$IFDEF EMBEDDED}
    DatabaseEdit.Text := Ini.ReadString(IniSection, 'Database', 'EMPLOYEE.FDB');
    {$ELSE}
    DatabaseEdit.Text := Ini.ReadString(IniSection, 'Database', 'employee');
    {$ENDIF}
    UserEdit.Text := Ini.ReadString(IniSection, 'User', 'SYSDBA');
    // The password is read from the file, but the application does not write it.
    PasswordEdit.Text := Ini.ReadString(IniSection, 'Password', '');
  finally
    Ini.Free;
  end;
end;

procedure TMainForm.SaveSettings;
var
  Ini: TIniFile;
begin
  try
    Ini := TIniFile.Create(AppDir + IniName);
    try
      Ini.WriteString(IniSection, 'Host', HostEdit.Text);
      Ini.WriteString(IniSection, 'Port', PortEdit.Text);
      Ini.WriteString(IniSection, 'Database', DatabaseEdit.Text);
      Ini.WriteString(IniSection, 'User', UserEdit.Text);
    finally
      Ini.Free;
    end;
  except
    // A read-only folder is not an error for the application.
  end;
end;

procedure TMainForm.OpenDatabase;
var
  DatabaseName: string;
begin
  CloseDatabase;
  DatabaseName := Trim(DatabaseEdit.Text);
  {$IFDEF EMBEDDED}
  // A file name without a path means a file in the folder of the application.
  if ExtractFilePath(DatabaseName) = '' then
    DatabaseName := AppDir + DatabaseName;
  Connection.HostName := '';
  Connection.Password := '';
  {$ELSE}
  if Trim(PortEdit.Text) <> '' then
    Connection.HostName := Trim(HostEdit.Text) + '/' + Trim(PortEdit.Text)
  else
    Connection.HostName := Trim(HostEdit.Text);
  Connection.Password := PasswordEdit.Text;
  {$ENDIF}
  Connection.DatabaseName := DatabaseName;
  Connection.UserName := Trim(UserEdit.Text);
  Connection.CharSet := 'UTF8';
  Connection.Open;
  Query.Open;
  // The trigger of the table gives the number to a new customer.
  Query.FieldByName('CUST_NO').Required := False;
  StatusBar.SimpleText := ServerInfo;
  UpdateControls;
end;

procedure TMainForm.CloseDatabase;
begin
  if Query.Active then
    Query.Close;
  if Transaction.Active then
    Transaction.Rollback;
  if Connection.Connected then
    Connection.Close;
  StatusBar.SimpleText := 'Not connected';
  UpdateControls;
end;

procedure TMainForm.SaveChanges;
begin
  if Query.State in dsEditModes then
    Query.Post;
  Query.ApplyUpdates;
  Transaction.CommitRetaining;
end;

procedure TMainForm.CancelChanges;
begin
  if Query.State in dsEditModes then
    Query.Cancel;
  Query.CancelUpdates;
  Transaction.RollbackRetaining;
  Query.Close;
  Query.Open;
  Query.FieldByName('CUST_NO').Required := False;
end;

// Server version, protocol and the encryption state of the database.
function TMainForm.ServerInfo: string;
var
  Info: TSQLQuery;
  Version, Protocol, Crypt: string;
begin
  Info := TSQLQuery.Create(nil);
  try
    Info.DataBase := Connection;
    Info.Transaction := Transaction;
    Info.SQL.Text :=
      'select rdb$get_context(''SYSTEM'', ''ENGINE_VERSION'') as VER, ' +
      'coalesce(rdb$get_context(''SYSTEM'', ''NETWORK_PROTOCOL''), ''embedded'') as PROTO ' +
      'from rdb$database';
    Info.Open;
    Version := Info.FieldByName('VER').AsString;
    Protocol := Info.FieldByName('PROTO').AsString;
    Info.Close;
    if StrToIntDef(Copy(Version, 1, Pos('.', Version) - 1), 0) >= 4 then
    begin
      Info.SQL.Text := 'select mon$crypt_state as STATE from mon$database';
      Info.Open;
      case Info.FieldByName('STATE').AsInteger of
        0: Crypt := 'not encrypted';
        1: Crypt := 'encrypted';
        2: Crypt := 'decryption in progress';
        3: Crypt := 'encryption in progress';
      else
        Crypt := 'unknown';
      end;
      Info.Close;
    end
    else
      Crypt := 'no information in Firebird 3.0';
    Result := Format('Firebird %s | %s | database: %s', [Version, Protocol, Crypt]);
  finally
    Info.Free;
  end;
end;

procedure TMainForm.Say(const Msg: string);
begin
  MessageMemo.Lines.Text := FormatDateTime('hh:nn:ss', Now) + '  ' + Msg;
end;

procedure TMainForm.UpdateControls;
var
  Online: Boolean;
begin
  Online := Connection.Connected;
  ConnectButton.Enabled := not Online;
  DisconnectButton.Enabled := Online;
  SaveButton.Enabled := Online;
  CancelButton.Enabled := Online;
end;

procedure TMainForm.ConnectButtonClick(Sender: TObject);
begin
  try
    OpenDatabase;
    Say(Format('Connected. Customers: %d', [Query.RecordCount]));
  except
    on E: Exception do
    begin
      CloseDatabase;
      Say('Cannot connect: ' + E.Message);
    end;
  end;
end;

procedure TMainForm.DisconnectButtonClick(Sender: TObject);
begin
  CloseDatabase;
  Say('Disconnected.');
end;

procedure TMainForm.SaveButtonClick(Sender: TObject);
begin
  try
    SaveChanges;
    Say('Changes are saved.');
  except
    on E: Exception do
      Say('Cannot save: ' + E.Message);
  end;
end;

procedure TMainForm.CancelButtonClick(Sender: TObject);
begin
  try
    CancelChanges;
    Say('Changes are cancelled.');
  except
    on E: Exception do
      Say('Cannot cancel: ' + E.Message);
  end;
end;

// Test without a user: the same components and the same code as the buttons use.
function TMainForm.SelfTest: Boolean;
const
  CustomerNo = 1001;
var
  Log: TStringList;
  OldPhone, NewPhone: string;

  procedure FindCustomer;
  begin
    if not Query.Locate('CUST_NO', CustomerNo, []) then
      raise Exception.CreateFmt('Customer %d is not found', [CustomerNo]);
  end;

begin
  Result := False;
  Log := TStringList.Create;
  try
    try
      OpenDatabase;
      Log.Add('connected: ' + StatusBar.SimpleText);
      Query.Last;
      Log.Add(Format('customers: %d', [Query.RecordCount]));

      FindCustomer;
      OldPhone := Query.FieldByName('PHONE_NO').AsString;
      NewPhone := 'T' + FormatDateTime('hhnnsszzz', Now);
      Query.Edit;
      Query.FieldByName('PHONE_NO').AsString := NewPhone;
      Query.Post;
      SaveChanges;
      CloseDatabase;
      Log.Add('row is changed and saved');

      OpenDatabase;
      FindCustomer;
      if Query.FieldByName('PHONE_NO').AsString <> NewPhone then
        raise Exception.Create('The changed row is not found after the second connection');
      Log.Add('row is read after the second connection');

      Query.Edit;
      Query.FieldByName('PHONE_NO').AsString := OldPhone;
      Query.Post;
      SaveChanges;
      CloseDatabase;
      Log.Add('RESULT: OK');
      Result := True;
    except
      on E: Exception do
        Log.Add('RESULT: FAILED: ' + StringReplace(E.Message, LineEnding, ' | ', [rfReplaceAll]));
    end;
  finally
    try
      Log.SaveToFile(AppDir + 'selftest.log');
    except
    end;
    Log.Free;
  end;
end;

end.

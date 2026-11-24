unit providermain;

{ Main window of the key provider.

  The program lives in the tray of Windows. The library KeySource.dll (variant
  "c-provider") asks it for the key through a named pipe. At the first request
  the program asks the user for the key and keeps it in memory. The next requests
  get the key at once. The key is never written to the disk.

  KeyProvider.ini next to the program:

    [KeyProvider]
    KeyName=Red        name of the key, as in "alter database encrypt ... key <name>"
    KeepMinutes=0      how long to keep the key; 0: until the program ends
    Pipe=              name of the pipe; default FbKeyProvider-<user name> }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, Menus, IniFiles,
  pipeserver, askkeyunit;

type

  { TProviderForm }

  TProviderForm = class(TForm)
    InfoLabel: TLabel;
    LogMemo: TMemo;
    ButtonPanel: TPanel;
    EnterKeyButton: TButton;
    ForgetKeyButton: TButton;
    ExitButton: TButton;
    TrayIcon: TTrayIcon;
    TrayMenu: TPopupMenu;
    ShowItem: TMenuItem;
    EnterKeyItem: TMenuItem;
    ForgetKeyItem: TMenuItem;
    KeepItem: TMenuItem;
    KeepUntilExitItem: TMenuItem;
    Keep15Item: TMenuItem;
    Keep60Item: TMenuItem;
    ExitItem: TMenuItem;
    procedure EnterKeyClick(Sender: TObject);
    procedure ExitClick(Sender: TObject);
    procedure ForgetKeyClick(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure KeepItemClick(Sender: TObject);
    procedure ShowClick(Sender: TObject);
  private
    FKeyName: string;
    FKeyLine: AnsiString;     // the key; only in memory
    FKeyTime: TDateTime;
    FKeepMinutes: Integer;
    FExiting: Boolean;
    FServer: TPipeServer;
    function IniFile: string;
    function HasKey: Boolean;
    procedure ForgetKey;
    procedure Note(const Msg: string);
    procedure UpdateView;
    procedure HandleRequest(const ClientFile: string; ClientId: Cardinal; out Answer: AnsiString);
  end;

var
  ProviderForm: TProviderForm;

implementation

{$R *.lfm}

const
  IniSection = 'KeyProvider';

{ TProviderForm }

function TProviderForm.IniFile: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'KeyProvider.ini';
end;

procedure TProviderForm.FormCreate(Sender: TObject);
var
  Ini: TIniFile;
  PipeName: string;
begin
  Ini := TIniFile.Create(IniFile);
  try
    FKeyName := Ini.ReadString(IniSection, 'KeyName', 'Red');
    FKeepMinutes := Ini.ReadInteger(IniSection, 'KeepMinutes', 0);
    PipeName := Ini.ReadString(IniSection, 'Pipe', '');
  finally
    Ini.Free;
  end;
  if PipeName = '' then
    PipeName := UTF8Encode(DefaultPipeName);
  KeepUntilExitItem.Checked := FKeepMinutes = 0;
  Keep15Item.Checked := FKeepMinutes = 15;
  Keep60Item.Checked := FKeepMinutes = 60;

  try
    FServer := TPipeServer.Create(UTF8Decode(PipeName), @HandleRequest);
    Note('Started. Pipe: ' + PipeName + '. Key name: ' + FKeyName);
  except
    on E: Exception do
    begin
      // The usual reason: the key provider is already running.
      FServer := nil;
      Application.ShowMainForm := True;
      Note('ERROR: ' + E.Message);
    end;
  end;
  UpdateView;
  TrayIcon.Show;
end;

procedure TProviderForm.FormDestroy(Sender: TObject);
begin
  if FServer <> nil then
  begin
    FServer.Stop;
    FServer.Free;
  end;
  ForgetKey;
end;

procedure TProviderForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  // The close button hides the window. The program stays in the tray.
  CanClose := FExiting;
  if not CanClose then
    Hide;
end;

function TProviderForm.HasKey: Boolean;
begin
  if (FKeyLine <> '') and (FKeepMinutes > 0) and ((Now - FKeyTime) * 24 * 60 > FKeepMinutes) then
  begin
    ForgetKey;
    Note('The key is removed from memory: the keep time is over.');
  end;
  Result := FKeyLine <> '';
end;

procedure TProviderForm.ForgetKey;
begin
  if FKeyLine <> '' then
    FillChar(FKeyLine[1], Length(FKeyLine), 0);
  FKeyLine := '';
end;

procedure TProviderForm.Note(const Msg: string);
begin
  LogMemo.Lines.Add(FormatDateTime('hh:nn:ss', Now) + '  ' + Msg);
end;

procedure TProviderForm.UpdateView;
var
  Bitmap: TBitmap;
  State: string;
begin
  if FKeyLine <> '' then
    State := 'the key is in memory'
  else
    State := 'no key in memory';
  InfoLabel.Caption := Format('Key name: %s. State: %s.', [FKeyName, State]);
  TrayIcon.Hint := 'Key Provider: ' + State;
  ForgetKeyButton.Enabled := FKeyLine <> '';
  ForgetKeyItem.Enabled := FKeyLine <> '';

  // Tray icon: a green square when the key is in memory, a grey one when it is not.
  Bitmap := TBitmap.Create;
  try
    Bitmap.SetSize(32, 32);
    if FKeyLine <> '' then
      Bitmap.Canvas.Brush.Color := clGreen
    else
      Bitmap.Canvas.Brush.Color := clGray;
    Bitmap.Canvas.FillRect(0, 0, 32, 32);
    Bitmap.Canvas.Font.Color := clWhite;
    Bitmap.Canvas.Font.Style := [fsBold];
    Bitmap.Canvas.Font.Height := 26;
    Bitmap.Canvas.TextOut(8, 2, 'K');
    TrayIcon.Icon.Assign(Bitmap);
  finally
    Bitmap.Free;
  end;
end;

// Runs in the main thread: the pipe thread calls it through Synchronize.
procedure TProviderForm.HandleRequest(const ClientFile: string; ClientId: Cardinal; out Answer: AnsiString);
var
  Client: string;
  Line: AnsiString;
begin
  Client := Format('%s (process %d)', [ExtractFileName(ClientFile), ClientId]);
  if not HasKey then
  begin
    if TAskKeyForm.Ask(FKeyName, 'The program ' + Client + ' opens an encrypted database.', Line) then
    begin
      FKeyLine := Line;
      FKeyTime := Now;
      Note('The user entered the key.');
    end;
  end;

  if FKeyLine <> '' then
  begin
    Answer := 'OK'#10 + FKeyLine;
    Note('Key is given to ' + Client);
  end
  else
  begin
    Answer := 'ERROR the user did not enter the key'#10;
    Note('No key for ' + Client + ': the user cancelled the input.');
  end;
  UpdateView;
end;

procedure TProviderForm.EnterKeyClick(Sender: TObject);
var
  Line: AnsiString;
begin
  if TAskKeyForm.Ask(FKeyName, 'A new value replaces the key in memory.', Line) then
  begin
    ForgetKey;
    FKeyLine := Line;
    FKeyTime := Now;
    Note('The user entered the key.');
    UpdateView;
  end;
end;

procedure TProviderForm.ForgetKeyClick(Sender: TObject);
begin
  ForgetKey;
  Note('The key is removed from memory.');
  UpdateView;
end;

procedure TProviderForm.KeepItemClick(Sender: TObject);
var
  Ini: TIniFile;
begin
  FKeepMinutes := (Sender as TMenuItem).Tag;
  KeepUntilExitItem.Checked := FKeepMinutes = 0;
  Keep15Item.Checked := FKeepMinutes = 15;
  Keep60Item.Checked := FKeepMinutes = 60;
  try
    Ini := TIniFile.Create(IniFile);
    try
      Ini.WriteInteger(IniSection, 'KeepMinutes', FKeepMinutes);
    finally
      Ini.Free;
    end;
  except
    // A read-only folder is not an error.
  end;
  if FKeepMinutes = 0 then
    Note('Keep time: until the program ends.')
  else
    Note(Format('Keep time: %d minutes.', [FKeepMinutes]));
end;

procedure TProviderForm.ShowClick(Sender: TObject);
begin
  Show;
  BringToFront;
end;

procedure TProviderForm.ExitClick(Sender: TObject);
begin
  FExiting := True;
  Close;
end;

end.

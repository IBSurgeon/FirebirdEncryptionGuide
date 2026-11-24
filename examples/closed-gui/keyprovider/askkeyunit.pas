unit askkeyunit;

{ Window that asks the user for the key or the pass phrase. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls;

type

  { TAskKeyForm }

  TAskKeyForm = class(TForm)
    PromptLabel: TLabel;
    KeyEdit: TEdit;
    ShowCheck: TCheckBox;
    ErrorLabel: TLabel;
    OkButton: TButton;
    CancelButton: TButton;
    procedure FormShow(Sender: TObject);
    procedure OkButtonClick(Sender: TObject);
    procedure ShowCheckChange(Sender: TObject);
  private
    FKeyName: string;
    FKeyLine: AnsiString;
  public
    // Returns True and the line "Key=..." or "Password=..." when the user gave a correct value.
    class function Ask(const KeyName, Reason: string; out KeyLine: AnsiString): Boolean;
  end;

// Makes the line for the KeyHolder plugin from the text that the user typed.
//   0x..,0x..,  (16, 24 or 32 bytes)  ->  Key=<name> 0x..,
//   other text                        ->  Password=<name> <text>
function BuildKeyLine(const KeyName, Input: string; out Line: AnsiString; out Error: string): Boolean;

implementation

{$R *.lfm}

function IsHexKey(const Text: string; out Normal: string; out Error: string): Boolean;
var
  Parts: TStringList;
  I, Count: Integer;
  Part: string;
begin
  Result := False;
  Normal := '';
  Error := '';
  Parts := TStringList.Create;
  try
    Parts.Delimiter := ',';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := Text;
    Count := 0;
    for I := 0 to Parts.Count - 1 do
    begin
      Part := LowerCase(Trim(Parts[I]));
      if Part = '' then
        Continue;
      if (Length(Part) <> 4) or (Copy(Part, 1, 2) <> '0x') or
         not (Part[3] in ['0'..'9', 'a'..'f']) or not (Part[4] in ['0'..'9', 'a'..'f']) then
      begin
        Error := 'A key is a list of bytes: 0x1a,0x2b,...';
        Exit;
      end;
      Normal := Normal + Part + ',';
      Inc(Count);
    end;
    if not (Count in [16, 24, 32]) then
    begin
      Error := Format('A key has 16, 24 or 32 bytes. This text has %d.', [Count]);
      Exit;
    end;
    Result := True;
  finally
    Parts.Free;
  end;
end;

function BuildKeyLine(const KeyName, Input: string; out Line: AnsiString; out Error: string): Boolean;
var
  Text, Normal: string;
begin
  Result := False;
  Line := '';
  Error := '';
  // The plugin removes spaces at the ends of a pass phrase. Do the same here.
  Text := Trim(Input);
  if Text = '' then
  begin
    Error := 'The value is empty.';
    Exit;
  end;

  if LowerCase(Copy(Text, 1, 2)) = '0x' then
  begin
    if not IsHexKey(Text, Normal, Error) then
      Exit;
    Line := 'Key=' + KeyName + ' ' + Normal + #10;
    Result := True;
    Exit;
  end;

  // The plugin reads the text of the keys as a configuration file:
  // # starts a comment, " is a quotation mark, $( starts a macro.
  if (Pos('#', Text) > 0) or (Pos('"', Text) > 0) or (Pos('$(', Text) > 0) then
  begin
    Error := 'A pass phrase cannot contain  #  "  $(';
    Exit;
  end;
  // LCL strings are UTF-8. The pass phrase goes to the plugin in UTF-8.
  Line := 'Password=' + KeyName + ' ' + Text + #10;
  Result := True;
end;

{ TAskKeyForm }

class function TAskKeyForm.Ask(const KeyName, Reason: string; out KeyLine: AnsiString): Boolean;
var
  Form: TAskKeyForm;
begin
  KeyLine := '';
  Form := TAskKeyForm.Create(Application);
  try
    Form.FKeyName := KeyName;
    Form.PromptLabel.Caption := Reason + LineEnding +
      Format('Enter the key "%s": a pass phrase, or bytes 0x..,0x..,', [KeyName]);
    Result := Form.ShowModal = mrOk;
    if Result then
      KeyLine := Form.FKeyLine;
    Form.KeyEdit.Text := '';
  finally
    Form.Free;
  end;
end;

procedure TAskKeyForm.FormShow(Sender: TObject);
begin
  ErrorLabel.Caption := '';
  KeyEdit.SetFocus;
  // The key provider lives in the tray. Bring the window in front of the application that waits.
  Application.BringToFront;
  BringToFront;
end;

procedure TAskKeyForm.OkButtonClick(Sender: TObject);
var
  Error: string;
begin
  if BuildKeyLine(FKeyName, KeyEdit.Text, FKeyLine, Error) then
    ModalResult := mrOk
  else
    ErrorLabel.Caption := Error;
end;

procedure TAskKeyForm.ShowCheckChange(Sender: TObject);
begin
  if ShowCheck.Checked then
    KeyEdit.PasswordChar := #0
  else
    KeyEdit.PasswordChar := '*';
end;

end.

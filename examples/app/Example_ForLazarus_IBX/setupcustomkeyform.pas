unit SetupCustomKeyForm;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  Buttons;

type

  { TfrmSetupCustomKey }

  TfrmSetupCustomKey = class(TForm)
    btnOK: TBitBtn;
    btnCancel: TBitBtn;
    btnGenerateKey: TButton;
    edtCustomKeyName: TLabeledEdit;
    Label1: TLabel;
    mmKey: TMemo;
    procedure btnGenerateKeyClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
  private
    function GetCustomKeyName: string;
    procedure SetCustomKeyName(const AValue: string);
    function GetCustomKey: string;
    procedure SetCustomKey(const AValue: string);
  public
    property CustomKeyName: string read GetCustomKeyName write SetCustomKeyName;
    property CustomKey: string read GetCustomKey write SetCustomKey;
  end;

var
  frmSetupCustomKey: TfrmSetupCustomKey;

implementation

uses openssl, DBCryptHelper;

{$R *.lfm}

{ TfrmSetupCustomKey }

procedure TfrmSetupCustomKey.btnGenerateKeyClick(Sender: TObject);
var
  Bytes: array[0..DBKeySize - 1] of Byte;
  KeyValue: string;
  i: Integer;
  ErrCode: Cardinal;
begin
  if RAND_bytes(@Bytes[0], SizeOf(Bytes)) <> 1 then
  begin
    ErrCode := ErrGetError;
    raise Exception.CreateFmt('Error %d', [ErrCode]);
  end;

  KeyValue := '';
  for i := 0 to DBKeySize - 1 do
  begin
    KeyValue := KeyValue + Format('$%.2x', [Bytes[I]]);
    if i < DBKeySize - 1 then
      KeyValue := KeyValue + ',';
  end;

  CustomKey := KeyValue;
end;

procedure TfrmSetupCustomKey.FormClose(Sender: TObject;
  var CloseAction: TCloseAction);
begin
  CloseAction := caFree;
  if ModalResult = mrOK then
  begin
    if CustomKeyName = '' then
    begin
      CloseAction := caNone;
      ShowMessage('Key name cannot be empty');
      Exit;
    end;
    if not IsValidKeyHex(CustomKey) then
    begin
      CloseAction := caNone;
      ShowMessage('Invalid key format');
    end;
  end;
end;

procedure TfrmSetupCustomKey.FormCreate(Sender: TObject);
begin
  if not InitSSLInterface then
    raise Exception.Create('Can not load OpenSSL');
end;

function TfrmSetupCustomKey.GetCustomKeyName: string;
begin
  Result := Trim(edtCustomKeyName.Text);
end;

procedure TfrmSetupCustomKey.SetCustomKeyName(const AValue: string);
begin
  edtCustomKeyName.Text := AValue;
end;

function TfrmSetupCustomKey.GetCustomKey: string;
begin
  Result := Trim(mmKey.Text);
end;

procedure TfrmSetupCustomKey.SetCustomKey(const AValue: string);
begin
  mmKey.Text := AValue;
end;

end.


unit KeyStorageU;

{ Scenario S8: where the application takes the key from.

  1. The user types the key (see the form).
  2. A text file in the format of KeyHolder.conf: Key=<name> 0x..,0x..,
     Protect such a file with access rights: only the account of the application
     must be able to read it.
  3. The same file protected with DPAPI (Windows Data Protection API).
     Only the same Windows user on the same computer can read it.

  Do not keep real keys in the source code. }

interface

uses
  System.SysUtils, System.Classes, FbCryptApi;

type
  TKeyFileEntry = record
    KeyName: string;
    KeyValue: TBytes;
  end;
  TKeyFileEntries = TArray<TKeyFileEntry>;

{ Reads all keys from a text file in the format of KeyHolder.conf. }
function ReadKeyTextFile(const AFileName: string): TKeyFileEntries;

{ Writes one key to a text file in the format of KeyHolder.conf. The file is replaced. }
procedure SaveKeyTextFile(const AFileName, AKeyName: string; const AKey: TBytes);

{ True when the file was written by SaveKeyDpapiFile. }
function IsDpapiFile(const AFileName: string): Boolean;

{ Writes the key to a file protected with DPAPI for the current Windows user.
  Another user or another computer cannot read it. The file is replaced. }
procedure SaveKeyDpapiFile(const AFileName, AKeyName: string; const AKey: TBytes);

{ Reads a DPAPI protected file.
  Returns False when another user or another computer created the file,
  or when the file is damaged. }
function ReadKeyDpapiFile(const AFileName: string; out AEntries: TKeyFileEntries): Boolean;

implementation

uses
  Winapi.Windows, System.IOUtils;

{ Windows Data Protection API. The declarations are not in the RTL. }
function CryptProtectData(pDataIn: PDATA_BLOB; szDataDescr: LPCWSTR;
  pOptionalEntropy: PDATA_BLOB; pvReserved: LPVOID; pPromptStruct: Pointer;
  dwFlags: DWORD; pDataOut: PDATA_BLOB): BOOL; stdcall; external 'crypt32.dll';

function CryptUnprotectData(pDataIn: PDATA_BLOB; pp_szDataDescr: Pointer;
  pOptionalEntropy: PDATA_BLOB; pvReserved: LPVOID; pPromptStruct: Pointer;
  dwFlags: DWORD; pDataOut: PDATA_BLOB): BOOL; stdcall; external 'crypt32.dll';

const
  // The first bytes of a DPAPI protected key file.
  Signature: AnsiString = 'FBKEYDPF';

function Dpapi(const AData: TBytes; AProtect: Boolean; out AResult: TBytes): Boolean;
var
  InBlob, OutBlob: DATA_BLOB;
begin
  AResult := nil;
  FillChar(InBlob, SizeOf(InBlob), 0);
  FillChar(OutBlob, SizeOf(OutBlob), 0);
  InBlob.cbData := Length(AData);
  InBlob.pbData := @AData[0];
  try
    if AProtect then
      Result := CryptProtectData(@InBlob, nil, nil, nil, nil, 0, @OutBlob)
    else
      Result := CryptUnprotectData(@InBlob, nil, nil, nil, nil, 0, @OutBlob);
    if Result then
    begin
      SetLength(AResult, OutBlob.cbData);
      if OutBlob.cbData > 0 then
        Move(OutBlob.pbData^, AResult[0], OutBlob.cbData);
    end;
  finally
    if OutBlob.pbData <> nil then
      LocalFree(HLOCAL(OutBlob.pbData));
  end;
end;

function TextToEntries(const AText: string): TKeyFileEntries;
var
  Lines: TStringList;
  Entry: TKeyFileEntry;
  I: Integer;
begin
  Result := nil;
  Lines := TStringList.Create;
  try
    Lines.Text := AText;
    for I := 0 to Lines.Count - 1 do
      if ParseKeyLine(Lines[I], Entry.KeyName, Entry.KeyValue) then
        Result := Result + TArray<TKeyFileEntry>.Create(Entry);
  finally
    Lines.Free;
  end;
end;

function ReadKeyTextFile(const AFileName: string): TKeyFileEntries;
begin
  Result := TextToEntries(TFile.ReadAllText(AFileName, TEncoding.ASCII));
end;

procedure SaveKeyTextFile(const AFileName, AKeyName: string; const AKey: TBytes);
begin
  TFile.WriteAllText(AFileName, KeyLine(AKeyName, AKey) + sLineBreak, TEncoding.ASCII);
end;

function IsDpapiFile(const AFileName: string): Boolean;
var
  Content: TBytes;
begin
  Content := TFile.ReadAllBytes(AFileName);
  Result := Length(Content) > Length(Signature);
  if Result then
    Result := CompareMem(@Content[0], PAnsiChar(Signature), Length(Signature));
end;

procedure SaveKeyDpapiFile(const AFileName, AKeyName: string; const AKey: TBytes);
var
  Text, ProtectedBytes: TBytes;
begin
  Text := TEncoding.UTF8.GetBytes(KeyLine(AKeyName, AKey) + sLineBreak);
  if not Dpapi(Text, True, ProtectedBytes) then
    raise Exception.CreateFmt('DPAPI cannot protect the data (error %d).', [GetLastError]);
  TFile.WriteAllBytes(AFileName, TEncoding.ASCII.GetBytes(string(Signature)) + ProtectedBytes);
end;

function ReadKeyDpapiFile(const AFileName: string; out AEntries: TKeyFileEntries): Boolean;
var
  Content, Text: TBytes;
begin
  AEntries := nil;
  Content := TFile.ReadAllBytes(AFileName);
  if (Length(Content) <= Length(Signature)) or
     not CompareMem(@Content[0], PAnsiChar(Signature), Length(Signature)) then
    raise Exception.CreateFmt('%s is not a key file protected with DPAPI.', [AFileName]);
  // Returns False when the file was protected by another user or on another computer.
  Result := Dpapi(Copy(Content, Length(Signature), Length(Content) - Length(Signature)), False, Text);
  if Result then
    AEntries := TextToEntries(TEncoding.UTF8.GetString(Text));
end;

end.

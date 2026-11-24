unit keysourcecommon;

{ Common code of the KeySource libraries.

  Rules that come from the KeyHolder plugin:

    * The plugin loads KeySource.dll, calls MakeKeys once and unloads the library.
      This happens for each connection. Global variables do not live between
      the calls. A library that keeps a cache must call PinLibrary.
    * MakeKeys can be called from several threads at the same time.
    * The memory for the result comes only from the allocator of the plugin.
      allocator(n) gives n + 1 bytes. The plugin frees the memory.
    * If MakeKeys returns NULL, the plugin takes the keys from KeyHolder.conf.
    * The client sends ALL returned keys to the server. Return only the keys
      that this workstation needs.

  Settings are in KeySource.ini next to the library, section [KeySource].
  Log=1 turns on the log KeySource.log. The log never contains a key. }

{$mode objfpc}{$H+}

interface

uses
  Windows, SysUtils;

type
  TAllocator = function(size: Cardinal): PAnsiChar; cdecl;

function LibraryDir: UnicodeString;
function Setting(const Name, Default: UnicodeString): UnicodeString;
function SettingInt(const Name: UnicodeString; Default: Integer): Integer;
function ExpandEnv(const Text: UnicodeString): UnicodeString;
procedure LogLine(const Text: string);
function ReadFileBytes(const FileName: UnicodeString; out Data: AnsiString): Boolean;
function CleanKeys(const Text: AnsiString): AnsiString;
function ReturnKeys(Alloc: TAllocator; const Keys: AnsiString; var Size: Cardinal): PAnsiChar;
function PinLibrary: Boolean;

implementation

const
  GET_MODULE_HANDLE_EX_FLAG_PIN = $00000001;
  GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS = $00000004;

function GetModuleHandleExW(dwFlags: DWORD; lpModuleName: Pointer; var phModule: HMODULE): BOOL;
  stdcall; external 'kernel32.dll';

function LibraryDir: UnicodeString;
var
  Buf: array[0..1023] of WideChar;
  Name: UnicodeString;
begin
  SetString(Name, Buf, GetModuleFileNameW(HInstance, Buf, Length(Buf)));
  Result := ExtractFilePath(Name);
end;

function Setting(const Name, Default: UnicodeString): UnicodeString;
var
  Buf: array[0..2047] of WideChar;
begin
  SetString(Result, Buf, GetPrivateProfileStringW('KeySource', PWideChar(Name), PWideChar(Default),
    Buf, Length(Buf), PWideChar(LibraryDir + 'KeySource.ini')));
  Result := Trim(Result);
end;

function SettingInt(const Name: UnicodeString; Default: Integer): Integer;
begin
  Result := StrToIntDef(string(Setting(Name, '')), Default);
end;

// Replaces %NAME% with the value of the environment variable.
function ExpandEnv(const Text: UnicodeString): UnicodeString;
var
  Buf: array[0..2047] of WideChar;
  Len: DWORD;
begin
  Len := ExpandEnvironmentStringsW(PWideChar(Text), Buf, Length(Buf));
  if (Len = 0) or (Len > Length(Buf)) then
    Result := Text
  else
    SetString(Result, Buf, Len - 1);
end;

// One WriteFile call with FILE_APPEND_DATA: lines of different threads and processes do not mix.
procedure LogLine(const Text: string);
var
  H: THandle;
  Line: AnsiString;
  Written: DWORD;
begin
  if Setting('Log', '0') <> '1' then
    Exit;
  Line := AnsiString(Format('%s pid=%d tid=%d %s'#13#10,
    [FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now), GetCurrentProcessId, GetCurrentThreadId, Text]));
  H := CreateFileW(PWideChar(LibraryDir + 'KeySource.log'), FILE_APPEND_DATA,
    FILE_SHARE_READ or FILE_SHARE_WRITE, nil, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
  if H = INVALID_HANDLE_VALUE then
    Exit;
  WriteFile(H, Line[1], Length(Line), Written, nil);
  CloseHandle(H);
end;

function ReadFileBytes(const FileName: UnicodeString; out Data: AnsiString): Boolean;
var
  H: THandle;
  Size, Got: DWORD;
begin
  Result := False;
  Data := '';
  H := CreateFileW(PWideChar(FileName), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING, 0, 0);
  if H = INVALID_HANDLE_VALUE then
    Exit;
  Size := GetFileSize(H, nil);
  if Size > 65536 then
    Size := 65536;   // a file of keys is small
  SetLength(Data, Size);
  Got := 0;
  Result := (Size = 0) or (ReadFile(H, Data[1], Size, Got, nil) and (Got = Size));
  CloseHandle(H);
end;

// Keeps only the lines "Key=..." and "Password=...". Removes the BOM, comments,
// empty lines and CR. Each line of the result ends with LF.
function CleanKeys(const Text: AnsiString): AnsiString;
var
  Source, Line, Lower: AnsiString;
  P: SizeInt;
begin
  Result := '';
  Source := Text;
  if (Length(Source) >= 3) and (Source[1] = #$EF) and (Source[2] = #$BB) and (Source[3] = #$BF) then
    Delete(Source, 1, 3);
  while Source <> '' do
  begin
    P := Pos(#10, Source);
    if P = 0 then
    begin
      Line := Source;
      Source := '';
    end
    else
    begin
      Line := Copy(Source, 1, P - 1);
      Delete(Source, 1, P);
    end;
    Line := Trim(Line);
    Lower := LowerCase(Line);
    if (Copy(Lower, 1, 4) = 'key=') or (Copy(Lower, 1, 9) = 'password=') then
      Result := Result + Line + #10;
  end;
end;

// Copies the text of the keys to the memory of the plugin. Empty text gives NULL.
function ReturnKeys(Alloc: TAllocator; const Keys: AnsiString; var Size: Cardinal): PAnsiChar;
begin
  Result := nil;
  Size := 0;
  if Keys = '' then
    Exit;
  Result := Alloc(Length(Keys));
  if Result = nil then
    Exit;
  Size := Length(Keys);
  Move(Keys[1], Result^, Size);
end;

// After this call the library stays in the process until the process ends.
// Global variables keep their values between the calls of MakeKeys.
function PinLibrary: Boolean;
var
  Module: HMODULE;
begin
  Module := 0;
  Result := GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_PIN or GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS,
    @LibraryDir, Module);
end;

end.

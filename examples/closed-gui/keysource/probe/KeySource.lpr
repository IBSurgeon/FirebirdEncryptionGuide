library KeySource;

{ Diagnostic KeySource library.

  It returns the public test key Red and writes each event to KeySource.log
  next to the library: load, unload, each call of MakeKeys with process and thread.
  Use it to see when and how many times Firebird calls MakeKeys.

  Optional settings in KeySource.ini next to the library:

    [KeySource]
    DelayMs=0        wait this time inside MakeKeys
    Pin=0            1: the library stays in the process after the first call
    ReturnNull=0     1: MakeKeys returns NULL
    KeysFile=        file with the text of the keys (replaces the key Red)
}

{$mode objfpc}{$H+}

uses
  Windows, SysUtils;

type
  TAllocator = function(size: Cardinal): PAnsiChar; cdecl;

const
  RedKey: AnsiString =
    'Key=Red 0xec,0xa1,0x52,0xf6,0x4d,0x27,0xda,0x93,0x53,0xe5,0x48,0x86,0xb9,0x7d,0xe2,0x8f,' +
    '0x3b,0xfa,0xb7,0x91,0x22,0x5b,0x59,0x15,0x82,0x35,0xf5,0x30,0x1f,0x04,0xdc,0x75,'#10;

  GET_MODULE_HANDLE_EX_FLAG_PIN = $00000001;
  GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS = $00000004;

function GetModuleHandleExW(dwFlags: DWORD; lpModuleName: Pointer; var phModule: HMODULE): BOOL;
  stdcall; external 'kernel32.dll';

var
  CallCount: LongInt = 0;   // calls of MakeKeys after this load of the library

function LibraryFile: UnicodeString;
var
  buf: array[0..1023] of WideChar;
begin
  SetString(Result, buf, GetModuleFileNameW(HInstance, buf, Length(buf)));
end;

function LibraryDir: UnicodeString;
begin
  Result := ExtractFilePath(LibraryFile);
end;

// One WriteFile call with FILE_APPEND_DATA: lines of different threads and processes do not mix.
procedure Log(const text: string);
var
  h: THandle;
  line: AnsiString;
  written: DWORD;
begin
  line := AnsiString(Format('%s pid=%d tid=%d %s'#13#10,
    [FormatDateTime('hh:nn:ss.zzz', Now), GetCurrentProcessId, GetCurrentThreadId, text]));
  h := CreateFileW(PWideChar(LibraryDir + 'KeySource.log'), FILE_APPEND_DATA,
    FILE_SHARE_READ or FILE_SHARE_WRITE, nil, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
  if h = INVALID_HANDLE_VALUE then
    Exit;
  WriteFile(h, line[1], Length(line), written, nil);
  CloseHandle(h);
end;

function Setting(const name, default: UnicodeString): UnicodeString;
var
  buf: array[0..1023] of WideChar;
begin
  SetString(Result, buf, GetPrivateProfileStringW('KeySource', PWideChar(name), PWideChar(default),
    buf, Length(buf), PWideChar(LibraryDir + 'KeySource.ini')));
end;

function ReadFileBytes(const fileName: UnicodeString; out data: AnsiString): Boolean;
var
  h: THandle;
  size, got: DWORD;
begin
  Result := False;
  data := '';
  h := CreateFileW(PWideChar(fileName), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING, 0, 0);
  if h = INVALID_HANDLE_VALUE then
    Exit;
  size := GetFileSize(h, nil);
  SetLength(data, size);
  Result := (size = 0) or (ReadFile(h, data[1], size, got, nil) and (got = size));
  CloseHandle(h);
end;

function MakeKeys(alloc: TAllocator; var size: Cardinal): PAnsiChar; cdecl;
var
  n, delay: LongInt;
  keys: AnsiString;
  keysFile: UnicodeString;
  module: HMODULE;
begin
  Result := nil;
  size := 0;
  n := InterlockedIncrement(CallCount);
  Log(Format('MakeKeys: call %d after load', [n]));

  if (n = 1) and (Setting('Pin', '0') = '1') then
  begin
    module := 0;
    // Any address inside this library. Not @MakeKeys: inside the function it is the result variable.
    if GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_PIN or GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS,
      @Log, module) then
      Log('MakeKeys: the library is pinned in the process')
    else
      Log(Format('MakeKeys: cannot pin the library, error %d', [GetLastError]));
  end;

  delay := StrToIntDef(string(Setting('DelayMs', '0')), 0);
  if delay > 0 then
  begin
    Sleep(delay);
    Log(Format('MakeKeys: waited %d ms', [delay]));
  end;

  if Setting('ReturnNull', '0') = '1' then
  begin
    Log('MakeKeys: return NULL');
    Exit;
  end;

  keys := RedKey;
  keysFile := Setting('KeysFile', '');
  if keysFile <> '' then
    if not ReadFileBytes(keysFile, keys) then
    begin
      Log('MakeKeys: cannot read the file of keys, return NULL');
      Exit;
    end;

  // The plugin frees this memory. allocator(n) gives n + 1 bytes.
  size := Length(keys);
  Result := alloc(size);
  if size > 0 then
    Move(keys[1], Result^, size);
  Log(Format('MakeKeys: return %d bytes', [size]));
end;

exports
  MakeKeys;

procedure LibraryExit;
begin
  Log('library unloaded');
end;

begin
  AddExitProc(@LibraryExit);
  Log('library loaded');
end.

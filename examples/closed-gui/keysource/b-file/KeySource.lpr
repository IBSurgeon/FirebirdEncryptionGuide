library KeySource;

{ Variant B: the key is in a file.

  KeySource.ini next to the library:

    [KeySource]
    KeyFile=E:\keys\employee.key
    Log=0

  The file has the format of KeyHolder.conf: lines "Key=<name> 0x..," or
  "Password=<name> <phrase>". Other lines are ignored. %NAME% in the path is
  replaced with the environment variable. Without KeyFile the library reads
  KeySource.key from its own folder.

  Keep the file on a removable disk or in a folder that only the users of the
  application can read. The file is read at each connection: when the disk is
  removed, new connections are not possible. }

{$mode objfpc}{$H+}

uses
  Windows, SysUtils, keysourcecommon;

function MakeKeys(Alloc: TAllocator; var Size: Cardinal): PAnsiChar; cdecl;
var
  FileName: UnicodeString;
  Data, Keys: AnsiString;
begin
  Result := nil;
  Size := 0;
  PinLibrary;   // stay in the process: see the rules in keysourcecommon.pas
  FileName := ExpandEnv(Setting('KeyFile', ''));
  if FileName = '' then
    FileName := LibraryDir + 'KeySource.key';

  if not ReadFileBytes(FileName, Data) then
  begin
    LogLine(Format('MakeKeys: cannot read the file of keys %s, error %d', [string(FileName), GetLastError]));
    Exit;
  end;

  Keys := CleanKeys(Data);
  if Keys = '' then
  begin
    LogLine(Format('MakeKeys: no lines "Key=" or "Password=" in the file %s', [string(FileName)]));
    Exit;
  end;

  Result := ReturnKeys(Alloc, Keys, Size);
  LogLine(Format('MakeKeys: the keys from the file %s are returned', [string(FileName)]));
end;

exports
  MakeKeys;

begin
end.

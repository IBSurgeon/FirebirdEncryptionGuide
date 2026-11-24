library KeyChecker;

{ KeyChecker: a library that the KeyHolder plugin calls for each key it loads.

  The plugin looks for the library with the name KeyChecker in the folder of Firebird
  libraries (Windows: next to firebird.exe or fbclient.dll; Linux: the lib folder,
  file libKeyChecker.so). The library must export the function CheckKey.

  The function gets the key name, the full path of the current program, and a pointer
  to the key value. It returns nothing, so it cannot reject a key. It can:
    * write an audit record (this example);
    * change the key value in place. The length cannot change.

  This example writes one line for each key to the file from the environment variable
  FBCRYPT_KEYCHECKER_LOG. It never writes the key value.

  Build:  fpc KeyChecker.lpr }

{$mode objfpc}{$H+}

uses
  SysUtils;

// extern "C" void CheckKey(const char* keyName, const char* exeName, unsigned keyLen, void* keyValue);
procedure CheckKey(keyName: PAnsiChar; exeName: PAnsiChar; keyLen: Cardinal; keyValue: Pointer); cdecl;
var
  LogName: string;
  Log: TextFile;
begin
  // The example does not read and does not change the key (keyValue).
  LogName := GetEnvironmentVariable('FBCRYPT_KEYCHECKER_LOG');
  if LogName = '' then
    Exit;
  try
    AssignFile(Log, LogName);
    if FileExists(LogName) then
      Append(Log)
    else
      Rewrite(Log);
    try
      WriteLn(Log, FormatDateTime('yyyy-mm-dd hh:nn:ss', Now), ' key=', keyName,
        ' length=', keyLen, ' program=', exeName);
    finally
      CloseFile(Log);
    end;
  except
    // An exception must not leave the library.
  end;
end;

exports
  CheckKey;

begin
end.

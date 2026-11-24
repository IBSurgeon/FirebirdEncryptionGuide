library KeySource;

{ Variant A: the key is a constant in the library.

  The simplest variant. Replace the public test key Red with your key and build
  the library. Protects the database file and the backups if somebody steals them.
  Does not protect from a person who has the library: the key can be read from it. }

{$mode objfpc}{$H+}

uses
  keysourcecommon;

const
  // The public test key Red. Do not use it for real data.
  Keys: AnsiString =
    'Key=Red 0xec,0xa1,0x52,0xf6,0x4d,0x27,0xda,0x93,0x53,0xe5,0x48,0x86,0xb9,0x7d,0xe2,0x8f,' +
    '0x3b,0xfa,0xb7,0x91,0x22,0x5b,0x59,0x15,0x82,0x35,0xf5,0x30,0x1f,0x04,0xdc,0x75,'#10;

function MakeKeys(Alloc: TAllocator; var Size: Cardinal): PAnsiChar; cdecl;
begin
  Result := ReturnKeys(Alloc, Keys, Size);
  LogLine('MakeKeys: the key from the library is returned');
end;

exports
  MakeKeys;

begin
end.

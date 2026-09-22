unit DatabaseKeys;

{$mode ObjFPC}{$H+}

interface

uses DBCryptHelper;

type
  TDBKeyIndex = (keyNone = 0, keyRed = 1, keyGreen = 2, keyBlue = 3, keyCustom = 4);

const

  ZeroKey: TDBKey = ($00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00);

  DBKeyNames: array [Low(TDBKeyIndex)..High(TDBKeyIndex)] of string = (
     'None',
     'Red',
     'Green',
     'Blue',
     ''
  );

function GetDBKeyIndexByName(const ADBKeyName: string): TDBKeyIndex;
function GetDBKey(Index: TDBKeyIndex): PDBKey;
function GetDBKeyByName(const ADBKeyName: string): PDBKey;

implementation

const
  RedKey: TDBKey = ($ec,$a1,$52,$f6,$4d,$27,$da,$93,$53,$e5,$48,$86,$b9,$7d,$e2,$8f,$3b,$fa,$b7,$91,$22,$5b,$59,$15,$82,$35,$f5,$30,$1f,$04,$dc,$75);
  GreenKey: TDBKey = ($ab,$d7,$34,$63,$ae,$19,$52,$00,$b8,$84,$a3,$44,$bd,$11,$9f,$72,$e0,$04,$68,$4f,$c4,$89,$3b,$20,$8d,$2a,$a7,$07,$32,$3b,$5e,$74);
  BlueKey: TDBKey = ($25,$83,$46,$88,$f2,$1d,$2c,$69,$48,$56,$7a,$4a,$0a,$85,$35,$22,$5c,$02,$4f,$65,$b8,$73,$77,$07,$89,$b2,$c6,$04,$da,$e4,$03,$5d);

function GetDBKeyIndexByName(const ADBKeyName: string): TDBKeyIndex;
var
  i: TDBKeyIndex;
begin
  Result := keyNone;
  for i:= Low(TDBKeyIndex) to High(TDBKeyIndex) do
  begin
    if ADBKeyName = DBKeyNames[i] then
    begin
      Result := i;
      Exit;
    end;
  end;
end;

function GetDBKey(Index: TDBKeyIndex): PDBKey;
begin
  case Index of
    keyNone: Result := nil;
    keyRed: Result := @RedKey;
    keyGreen: Result := @GreenKey;
    keyBlue: Result := @BlueKey;
    else
      Result := nil;
  end;
end;

function GetDBKeyByName(const ADBKeyName: string): PDBKey;
var
  xIndex: TDBKeyIndex;
begin
  xIndex := GetDBKeyIndexByName(ADBKeyName);
  Result := GetDBKey(xIndex);
end;

end.


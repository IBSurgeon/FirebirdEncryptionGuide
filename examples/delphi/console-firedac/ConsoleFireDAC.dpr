program ConsoleFireDAC;

{ Scenarios S1, S2 and S3: connect to an encrypted database with FireDAC.

  Key transfer method A: FireDAC works on the ISC API, and fbcrypt registers the key
  callback for the current thread. The key exchange is protected.
  The server does not need UnsafeClient = true.

  Standard output is the same on each run (see expected-output.txt).
  Full error texts go to standard error. }

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  Data.DB,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Def,
  FireDAC.Stan.Async,
  FireDAC.Stan.Param,
  FireDAC.DApt,
  FireDAC.Comp.Client,
  FireDAC.Comp.DataSet,
  FireDAC.Phys.FB,
  FireDAC.Phys.IBBase,
  FireDAC.Phys.IBDef,
  FbCryptApi in '..\common\FbCryptApi.pas',
  ExampleCommon in '..\common\ExampleCommon.pas';

var
  FbCrypt: TFbCrypt;
  Link: TFDPhysFBDriverLink;
  Connection: TFDConnection;

{ Opens the connection and returns the note from the table demo.
  The key callback must be registered in the thread that opens the connection,
  before every new connection: see threads-firedac. }
function QueryNote(const AAlias: string): string;
var
  Query: TFDQuery;
begin
  Connection.Params.Values['Database'] := AAlias;
  FbCrypt.RegisterForThread;
  Connection.Connected := True;
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := Connection;
    Query.Open('select note from demo where id = 1');
    Result := Query.Fields[0].AsString;
  finally
    Query.Free;
    Connection.Connected := False;
  end;
end;

procedure ExpectError(const ATitle, AAlias: string);
var
  Note: string;
begin
  Note := '';
  try
    Note := QueryNote(AAlias);
  except
    on E: Exception do
    begin
      WriteLn(ATitle, ': error, as expected');
      WriteLn(ErrOutput, '--- ', ATitle);
      WriteLn(ErrOutput, E.Message);
      WriteLn(ErrOutput);
      Flush(ErrOutput);
      Exit;
    end;
  end;
  WriteLn(ATitle, ': NO ERROR - this is wrong: ', Note);
end;

begin
  try
    // FireDAC and fbcrypt must use the same fbclient: the one in the client folder.
    Link := TFDPhysFBDriverLink.Create(nil);
    Link.VendorHome := Env('FBCRYPT_CLIENT');
    Link.VendorLib := 'fbclient.dll';
    Connection := TFDConnection.Create(nil);
    Connection.DriverName := 'FB';
    Connection.LoginPrompt := False;
    Connection.Params.Values['Server'] := Env('FBCRYPT_HOST');
    Connection.Params.Values['Port'] := Env('FBCRYPT_PORT');
    Connection.Params.Values['User_Name'] := Env('FBCRYPT_USER');
    Connection.Params.Values['Password'] := Env('FBCRYPT_PASSWORD');

    // TFbCrypt loads the same fbclient and passes its path to fbcrypt_init.
    FbCrypt := TFbCrypt.Create(Link.VendorHome);
    try
      // S1: one key
      FbCrypt.AddKey('Red', ReadKey('Red'));
      WriteLn('S1 connect with key Red: ', QueryNote('crypt_red'));

      // S3: two keys in the list, two databases
      FbCrypt.AddKey('Green', ReadKey('Green'));
      WriteLn('S3 two keys, database crypt_red: ', QueryNote('crypt_red'));
      WriteLn('S3 two keys, database crypt_green: ', QueryNote('crypt_green'));

      // S2: errors. The key list is global for the process. ClearKeys removes all keys from it.
      // The callback stays registered in the thread, but the list is empty.
      FbCrypt.ClearKeys;
      ExpectError('S2 no key', 'crypt_red');
      FbCrypt.AddKey('Red', ReadKey('Green'));
      ExpectError('S2 wrong key value', 'crypt_red');
      FbCrypt.ClearKeys;
      FbCrypt.AddKey('Blue', ReadKey('Red'));
      ExpectError('S2 wrong key name', 'crypt_red');

      // Back to the right key
      FbCrypt.ClearKeys;
      FbCrypt.AddKey('Red', ReadKey('Red'));
      WriteLn('S1 connect again with key Red: ', QueryNote('crypt_red'));
    finally
      FbCrypt.Free;
    end;
  except
    on E: Exception do
    begin
      WriteLn(ErrOutput, 'ERROR: ', E.Message);
      WriteLn('ERROR: ', E.ClassName);
      Flush(ErrOutput);
      ExitCode := 1;
    end;
  end;
end.

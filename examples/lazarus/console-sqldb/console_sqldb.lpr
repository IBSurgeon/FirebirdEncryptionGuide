program console_sqldb;

{ Scenarios S1, S2 and S3: connect to an encrypted database with SQLdb (TIBConnection).

  Key transfer method A: SQLdb works on the ISC API, and fbcrypt registers the key
  callback for the current thread. The key exchange is protected.
  The server does not need UnsafeClient = true.

  Standard output is the same on each run (see expected-output.txt).
  Full error texts go to standard error. }

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, sqldb, sqldblib, IBConnection, fbcryptapi, examplecommon;

var
  FbCrypt: TFbCrypt;

function QueryNote(const AAlias: string): string;
var
  Connection: TIBConnection;
  Transaction: TSQLTransaction;
  Query: TSQLQuery;
begin
  Connection := TIBConnection.Create(nil);
  Transaction := TSQLTransaction.Create(nil);
  Query := TSQLQuery.Create(nil);
  try
    Connection.DatabaseName := ServerDsn(AAlias);
    Connection.UserName := Env('FBCRYPT_USER');
    Connection.Password := Env('FBCRYPT_PASSWORD');
    Connection.CharSet := 'UTF8';
    Connection.Transaction := Transaction;
    Query.DataBase := Connection;
    Query.Transaction := Transaction;

    // The callback must be registered in the thread that opens the connection.
    FbCrypt.RegisterForThread;
    Connection.Open;

    Query.SQL.Text := 'select note from demo where id = 1';
    Query.Open;
    Result := Query.Fields[0].AsString;
    Query.Close;
    Transaction.Commit;
    Connection.Close;
  finally
    Query.Free;
    Transaction.Free;
    Connection.Free;
  end;
end;

procedure ExpectError(const ATitle, AAlias: string);
begin
  try
    QueryNote(AAlias);
    WriteLn(ATitle, ': NO ERROR - this is wrong');
  except
    on E: Exception do
    begin
      WriteLn(ATitle, ': error, as expected');
      WriteLn(StdErr, '--- ', ATitle);
      WriteLn(StdErr, E.Message);
      WriteLn(StdErr);
    end;
  end;
end;

var
  Loader: TSQLDBLibraryLoader;
  ClientDir: string;
begin
  ClientDir := Env('FBCRYPT_CLIENT');

  // SQLdb and fbcrypt must use the same fbclient.
  Loader := TSQLDBLibraryLoader.Create(nil);
  Loader.ConnectionType := 'Firebird';
  Loader.LibraryName := FbClientLibrary(ClientDir);
  Loader.Enabled := True;

  FbCrypt := TFbCrypt.Create(ClientDir);
  try
    // S1: one key
    FbCrypt.AddKey('Red', ReadKey('Red'));
    WriteLn('S1 connect with key Red: ', QueryNote('crypt_red'));

    // S3: two keys in the list, two databases
    FbCrypt.AddKey('Green', ReadKey('Green'));
    WriteLn('S3 two keys, database crypt_red: ', QueryNote('crypt_red'));
    WriteLn('S3 two keys, database crypt_green: ', QueryNote('crypt_green'));

    // S2: errors. ClearKeys removes all keys from the list.
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
    Loader.Free;
  end;
end.

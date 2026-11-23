program threads_sqldb;

{ Scenario S4: threads with SQLdb and fbcrypt.

  The key callback of fbcrypt is registered for a thread (method A).
  Each thread that opens a connection must call TFbCrypt.RegisterForThread first.
  A thread that does not call it gets the error "Key not set". }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Classes, sqldb, sqldblib, IBConnection, fbcryptapi, examplecommon;

const
  ThreadCount = 4;
  Expected = 'Hello from crypt_red';

var
  FbCrypt: TFbCrypt;
  // The threads read these values. The main thread fills them before the start.
  Dsn, UserName, Password: string;

type

  { TQueryThread }

  TQueryThread = class(TThread)
  private
    FRegister: Boolean;
  protected
    procedure Execute; override;
  public
    Note: string;
    ErrorText: string;
    constructor Create(ARegister: Boolean);
  end;

constructor TQueryThread.Create(ARegister: Boolean);
begin
  FRegister := ARegister;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TQueryThread.Execute;
var
  Connection: TIBConnection;
  Transaction: TSQLTransaction;
  Query: TSQLQuery;
begin
  // Each thread has its own connection objects.
  Connection := TIBConnection.Create(nil);
  Transaction := TSQLTransaction.Create(nil);
  Query := TSQLQuery.Create(nil);
  try
    try
      Connection.DatabaseName := Dsn;
      Connection.UserName := UserName;
      Connection.Password := Password;
      Connection.CharSet := 'UTF8';
      Connection.Transaction := Transaction;
      Query.DataBase := Connection;
      Query.Transaction := Transaction;

      if FRegister then
        FbCrypt.RegisterForThread;
      Connection.Open;

      Query.SQL.Text := 'select note from demo where id = 1';
      Query.Open;
      Note := Query.Fields[0].AsString;
      Query.Close;
      Transaction.Commit;
      Connection.Close;
    except
      on E: Exception do
        ErrorText := E.Message;
    end;
  finally
    Query.Free;
    Transaction.Free;
    Connection.Free;
  end;
end;

var
  Loader: TSQLDBLibraryLoader;
  ClientDir: string;
  Thread: TQueryThread;
  Threads: array[1..ThreadCount] of TQueryThread;
  I, Correct: Integer;
begin
  ClientDir := Env('FBCRYPT_CLIENT');
  Dsn := ServerDsn('crypt_red');
  UserName := Env('FBCRYPT_USER');
  Password := Env('FBCRYPT_PASSWORD');

  Loader := TSQLDBLibraryLoader.Create(nil);
  Loader.ConnectionType := 'Firebird';
  Loader.LibraryName := FbClientLibrary(ClientDir);
  Loader.Enabled := True;

  FbCrypt := TFbCrypt.Create(ClientDir);
  // The key list is global for the process: add the key one time.
  FbCrypt.AddKey('Red', ReadKey('Red'));

  // 1. A thread that registers the callback
  Thread := TQueryThread.Create(True);
  Thread.WaitFor;
  if Thread.ErrorText = '' then
    WriteLn('Thread with RegisterForThread: ', Thread.Note)
  else
    WriteLn('Thread with RegisterForThread: FAILED: ', Thread.ErrorText);
  Thread.Free;

  // 2. A thread that does not register the callback
  Thread := TQueryThread.Create(False);
  Thread.WaitFor;
  if Thread.ErrorText <> '' then
  begin
    WriteLn('Thread without RegisterForThread: error, as expected');
    WriteLn(StdErr, '--- Thread without RegisterForThread');
    WriteLn(StdErr, Thread.ErrorText);
  end
  else
    WriteLn('Thread without RegisterForThread: NO ERROR - this is wrong');
  Thread.Free;

  // 3. Several threads at the same time
  for I := 1 to ThreadCount do
    Threads[I] := TQueryThread.Create(True);
  Correct := 0;
  for I := 1 to ThreadCount do
  begin
    Threads[I].WaitFor;
    if Threads[I].Note = Expected then
      Inc(Correct);
    Threads[I].Free;
  end;
  WriteLn(ThreadCount, ' threads: ', Correct, ' correct answers');

  FbCrypt.Free;
  Loader.Free;
end.

program ThreadsFireDAC;

{ Scenario S4: threads, the FireDAC connection pool and fbcrypt.

  The key callback of fbcrypt is registered for a thread (method A).
  Each thread that opens a connection must call TFbCrypt.RegisterForThread first.
  A thread that does not call it gets the error "Key not set".

  With a pool (Pooled = True) a closed connection returns to the pool, and the next
  thread takes it. Such a thread works without the callback: the connection is
  already open with the key. }

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
  FireDAC.Stan.Pool, // the pool itself: without this unit FireDAC raises an error at the first pooled connection
  FireDAC.Comp.Client,
  FireDAC.Comp.DataSet,
  FireDAC.Phys.FB,
  FireDAC.Phys.IBBase,
  FireDAC.Phys.IBDef,
  FireDAC.Comp.UI,
  FbCryptApi in '..\common\FbCryptApi.pas',
  ExampleCommon in '..\common\ExampleCommon.pas';

const
  ThreadCount = 4;
  Expected = 'Hello from crypt_red';
  PoolDefName = 'fbcrypt_examples_pool';

var
  FbCrypt: TFbCrypt;
  // The threads read these values. The main thread fills them before the start.
  Server, Port, UserName, Password: string;
  Pooled: Boolean;

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
  Connection: TFDConnection;
  Query: TFDQuery;
begin
  try
    // Each thread has its own connection object.
    Connection := TFDConnection.Create(nil);
    try
      Connection.LoginPrompt := False;
      if Pooled then
        // With a pool the connection uses the connection definition that switches the pool on.
        Connection.ConnectionDefName := PoolDefName
      else begin
        Connection.DriverName := 'FB';
        Connection.Params.Values['Server'] := Server;
        Connection.Params.Values['Port'] := Port;
        Connection.Params.Values['Database'] := 'crypt_red';
        Connection.Params.Values['User_Name'] := UserName;
        Connection.Params.Values['Password'] := Password;
      end;

      if FRegister then
        FbCrypt.RegisterForThread;
      Connection.Connected := True;

      Query := TFDQuery.Create(nil);
      try
        Query.Connection := Connection;
        Query.Open('select note from demo where id = 1');
        Note := Query.Fields[0].AsString;
      finally
        Query.Free;
        // Without a pool the connection is closed. With a pool it returns to the pool.
        Connection.Connected := False;
      end;
    finally
      Connection.Free;
    end;
  except
    on E: Exception do
      ErrorText := E.Message;
  end;
end;

{ Runs one thread and prints its result. }
procedure RunOne(const ATitle: string; ARegister, AMustFail: Boolean);
var
  Thread: TQueryThread;
begin
  Thread := TQueryThread.Create(ARegister);
  try
    Thread.WaitFor;
    if AMustFail then
    begin
      if Thread.ErrorText <> '' then
      begin
        WriteLn(ATitle, ': error, as expected');
        WriteLn(ErrOutput, '--- ', ATitle);
        WriteLn(ErrOutput, Thread.ErrorText);
        Flush(ErrOutput);
      end
      else
        WriteLn(ATitle, ': NO ERROR - this is wrong');
    end
    else if Thread.ErrorText = '' then
      WriteLn(ATitle, ': ', Thread.Note)
    else
    begin
      WriteLn(ATitle, ': FAILED: ', Thread.ErrorText);
      ExitCode := 1;
    end;
  finally
    Thread.Free;
  end;
end;

{ Runs ThreadCount threads at the same time. Each one registers the callback. }
procedure RunMany(const ATitle: string);
var
  Threads: array[0..ThreadCount - 1] of TQueryThread;
  I, Correct: Integer;
begin
  for I := 0 to ThreadCount - 1 do
    Threads[I] := TQueryThread.Create(True);
  Correct := 0;
  for I := 0 to ThreadCount - 1 do
  begin
    Threads[I].WaitFor;
    if Threads[I].Note = Expected then
      Inc(Correct)
    else
    begin
      WriteLn(ErrOutput, '--- ', ATitle, ', thread ', I);
      WriteLn(ErrOutput, Threads[I].ErrorText);
      Flush(ErrOutput);
    end;
    Threads[I].Free;
  end;
  WriteLn(ATitle, ': ', Correct, ' correct answers');
  if Correct <> ThreadCount then
    ExitCode := 1;
end;

{ The FireDAC pool belongs to a connection definition. The definition is registered in FDManager
  with the parameter Pooled = True. An anonymous TFDConnection with parameters cannot be pooled. }
procedure AddPoolDefinition;
var
  Params: TStrings;
begin
  Params := TStringList.Create;
  try
    Params.Values['Server'] := Server;
    Params.Values['Port'] := Port;
    Params.Values['Database'] := 'crypt_red';
    Params.Values['User_Name'] := UserName;
    Params.Values['Password'] := Password;
    Params.Values['Pooled'] := 'True';
    FDManager.AddConnectionDef(PoolDefName, 'FB', Params);
  finally
    Params.Free;
  end;
end;

var
  Link: TFDPhysFBDriverLink;
begin
  try
    // FireDAC and fbcrypt must use the same fbclient: the one in the client folder.
    Link := TFDPhysFBDriverLink.Create(nil);
    Link.VendorHome := Env('FBCRYPT_CLIENT');
    Link.VendorLib := 'fbclient.dll';
    Server := Env('FBCRYPT_HOST');
    Port := Env('FBCRYPT_PORT');
    UserName := Env('FBCRYPT_USER');
    Password := Env('FBCRYPT_PASSWORD');
    Pooled := False;

    FbCrypt := TFbCrypt.Create(Link.VendorHome);
    try
      // The key list is global for the process: add the key one time.
      FbCrypt.AddKey('Red', ReadKey('Red'));

      // 1. A thread that registers the callback
      RunOne('Thread with RegisterForThread', True, False);

      // 2. A thread that does not register the callback
      RunOne('Thread without RegisterForThread', False, True);

      // 3. Several threads at the same time
      RunMany(IntToStr(ThreadCount) + ' threads');

      // 4. The FireDAC pool. New connections are opened by threads with the callback.
      AddPoolDefinition;
      Pooled := True;
      RunMany('Pool, ' + IntToStr(ThreadCount) + ' threads with RegisterForThread');

      // 5. The pool returns an open connection. The thread works without the callback.
      RunOne('Pool, thread without RegisterForThread takes an open connection', False, False);
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

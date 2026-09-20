unit EncryptionMonitorThread;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, IBQuery, IBDatabase, IB;

type
  TProgressCallback = procedure(const AMessage: string) of object;

  { Firebird database encryption process monitoring thread }
  TEncryptionMonitorThread = class(TThread)
  private
    FDatabase: TIBDatabase;
    FTransaction: TIBTransaction;
    FQuery: TIBQuery;
    FLastMessage: string;
    FOnProgress: TProgressCallback;
    procedure DoProgress;
    procedure SetupComponents;
    procedure FreeComponents;
  protected
    procedure Execute; override;
  public
    constructor Create(AMainDatabase: TIBDatabase);
    destructor Destroy; override;

    property OnProgress: TProgressCallback read FOnProgress write FOnProgress;
  end;

implementation

uses
  {$IFDEF WINDOWS}
  Windows;
  {$ENDIF}

{ TEncryptionMonitorThread }

constructor TEncryptionMonitorThread.Create(AMainDatabase: TIBDatabase);
begin
  inherited Create(True);  // create it in a suspended state
  FreeOnTerminate := True;

  FDatabase := TIBDatabase.Create(nil);
  FDatabase.FirebirdLibraryPathName := AMainDatabase.FirebirdLibraryPathName;
  FDatabase.DatabaseName := AMainDatabase.DatabaseName;
  FDatabase.Params.Assign(AMainDatabase.Params);
  FDatabase.LoginPrompt := False;
  FDatabase.BeforeConnect := AMainDatabase.BeforeConnect;
end;

destructor TEncryptionMonitorThread.Destroy;
begin
  FreeComponents;
  inherited Destroy;
end;

procedure TEncryptionMonitorThread.SetupComponents;
begin
  FDatabase.Open;

  FTransaction := TIBTransaction.Create(nil);
  FTransaction.DefaultDatabase := FDatabase;

  FQuery := TIBQuery.Create(nil);
  FQuery.Database := FDatabase;
  FQuery.Transaction := FTransaction;
  FQuery.SQL.Text :=
    'SELECT ' +
    '  TRIM(CASE MON$CRYPT_STATE ' +
    '    WHEN 0 THEN ''Not encrypted'' ' +
    '    WHEN 1 THEN ''Encrypted'' ' +
    '    WHEN 2 THEN ''Decrypting process...'' ' +
    '    WHEN 3 THEN ''Encrypting process...'' ' +
    '  END) AS CRYPT_STATE, ' +
    '  MON$CRYPT_PAGE AS CRYPT_PAGE ' +
    'FROM MON$DATABASE';
end;

procedure TEncryptionMonitorThread.FreeComponents;
begin
  if Assigned(FQuery) then
  begin
    FQuery.Close;
    FreeAndNil(FQuery);
  end;
  if Assigned(FTransaction) then
  begin
    if FTransaction.Active then
      FTransaction.Rollback;
    FreeAndNil(FTransaction);
  end;
  if Assigned(FDatabase) then
  begin
    if FDatabase.Connected then
      FDatabase.Close;
    FreeAndNil(FDatabase);
  end;
end;

procedure TEncryptionMonitorThread.DoProgress;
begin
  if Assigned(FOnProgress) then
    FOnProgress(FLastMessage);
end;

procedure TEncryptionMonitorThread.Execute;
var
  CryptState: string;
  CryptPage: Integer;
begin
  try
    SetupComponents;
    try
      while not Terminated do
      begin
        // Each cycle is a new transaction to obtain a fresh snapshot.
        if not FTransaction.Active then
          FTransaction.StartTransaction;

        FQuery.Open;
        try
          if not FQuery.Eof then
          begin
            CryptState := FQuery.FieldByName('CRYPT_STATE').AsString;
            CryptPage := FQuery.FieldByName('CRYPT_PAGE').AsInteger;

            FLastMessage := Format('[%s] CRYPT_STATE=%s, CRYPT_PAGE=%d',
                [TimeToStr(Now), CryptState, CryptPage]);

            // publishing the result to the main stream
            Synchronize(@DoProgress);

            // stop monitoring when encryption is complete
            if CryptState = 'Encrypted' then
            begin
              FLastMessage := '=== Database encryption complete. ===';
              Synchronize(@DoProgress);
              Break;
            end;

            // stop monitoring when decryption is complete
            if CryptState = 'Not encrypted' then
            begin
              FLastMessage := '=== Database decryption complete. ===';
              Synchronize(@DoProgress);
              Break;
            end;
          end;
        finally
          FQuery.Close;
        end;

        // Commit the transaction so that the next request receives a new snapshot
        // (monitoring tables return data as of the start of the transaction)
        if FTransaction.Active then
          FTransaction.Commit;

        Sleep(1000);  // 1 second
      end;
    finally
      FreeComponents;
    end;
  except
    on E: Exception do
    begin
      FLastMessage := 'Monitoring error: ' + E.Message;
      Synchronize(@DoProgress);
    end;
  end;
end;

end.


program EmployeeApp;

{ Small database application for the database "employee".

  It plays the role of an application without source code: there is no line
  about encryption in it. The key comes from the library KeySource.dll that
  lies next to fbclient.dll.

  Build modes:
    Remote    EmployeeRemote.exe    connection to a Firebird server
    Embedded  EmployeeEmbedded.exe  the Firebird engine works inside the application

  Switch /selftest: connect with the settings of EmployeeApp.ini, change a row,
  connect again, check the row, write selftest.log, exit with code 0 or 1. }

{$mode objfpc}{$H+}

uses
  Interfaces, // this includes the LCL widgetset
  SysUtils, Forms, mainunit;

{$R *.res}

begin
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  {$PUSH}{$WARN 5044 OFF}
  Application.MainFormOnTaskbar := True;
  {$POP}
  Application.Initialize;
  if FindCmdLineSwitch('selftest') then
  begin
    Application.ShowMainForm := False;
    Application.CreateForm(TMainForm, MainForm);
    if MainForm.SelfTest then
      Halt(0)
    else
      Halt(1);
  end;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.

program VclFireDAC;

{ Scenarios S1, S5 and S8: a VCL form with FireDAC and fbcrypt. See MainFormU.

  Without parameters: the window.
  With --test: scenario S5 without the window, for run-test.ps1. }

uses
  Vcl.Forms,
  System.SysUtils,
  MainFormU in 'MainFormU.pas' {MainForm},
  KeyStorageU in 'KeyStorageU.pas',
  FbCryptApi in '..\common\FbCryptApi.pas',
  ExampleCommon in '..\common\ExampleCommon.pas';

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TMainForm, MainForm);
  if (ParamCount = 1) and (ParamStr(1) = '--test') then
  begin
    // No window. The lines go to the standard output of the process.
    try
      MainForm.RunTest;
    except
      on E: Exception do
      begin
        MainForm.Print('ERROR: ' + E.Message);
        ExitCode := 1;
      end;
    end;
  end
  else
    Application.Run;
end.

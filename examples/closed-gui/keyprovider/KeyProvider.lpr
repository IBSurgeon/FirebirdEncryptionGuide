program KeyProvider;

{ Key provider for the KeySource library "c-provider".

  The program starts hidden and shows an icon in the tray of Windows.
  Switch /show: start with the window on the screen. }

{$mode objfpc}{$H+}

uses
  Interfaces, // this includes the LCL widgetset
  SysUtils, Forms, providermain, askkeyunit, pipeserver;

{$R *.res}

begin
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  {$PUSH}{$WARN 5044 OFF}
  Application.MainFormOnTaskbar := True;
  {$POP}
  Application.Initialize;
  Application.ShowMainForm := FindCmdLineSwitch('show');
  Application.CreateForm(TProviderForm, ProviderForm);
  Application.Run;
end.

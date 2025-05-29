program uni_profiler_test;

{$MODE Delphi}

uses
  {$IFDEF LINUX}
  cthreads,
  {$ENDIF}
  SysUtils,
  Unit1,
  Unit2;

begin
  try
    StartTest;
    StartTest2;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.

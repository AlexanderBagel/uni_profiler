program uni_profiler_test;

{$MODE Delphi}

uses
  {$IFDEF LINUX}
  cthreads,
  {$ENDIF}
  SysUtils,
  Unit1;

begin
  try
    StartTest;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.

program uni_profiler_test;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  uni_profiler in '..\uni_profiler.pas',
  Unit1 in 'Unit1.pas';

begin
  try
    StartTest;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.

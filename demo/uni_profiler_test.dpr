program uni_profiler_test;

{$APPTYPE CONSOLE}

uses
  SysUtils,
  uni_profiler in '..\uni_profiler.pas',
  Unit1 in 'Unit1.pas',
  Unit2 in 'Unit2.pas';

begin
  try
    StartTest;
    StartTest2;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.

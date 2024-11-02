program uni_profiler_test;

{$MODE Delphi}

uses
  {$IFDEF LINUX}
  cthreads,
  {$ENDIF}
  Classes,
  SysUtils,
  uni_profiler in '..\uni_profiler.pas';

procedure Test;
var
  I: Integer;
  FullH, CounterH: THash;
  PV: TProfileValue;
begin
  FullH := uprof.Start('Whole cycle');
  for i := 0 to 10 do
  begin
    CounterH := uprof.Start('Each iteration');
      Writeln(I);
    uprof.Stop;
    // dump profile counters for iterator
    PV := uprof.GetProfileValue(CounterH);
    Writeln(Format('max %d', [PV.MaxTime]));
    Writeln(Format('min %d', [PV.MinTime]));
    Writeln(Format('avg %d', [PV.Total div PV.Count]));
  end;
  uprof.Stop;
  // dump profile counters for all cicle
  PV := uprof.GetProfileValue(FullH);
  Writeln(Format('Total max %d', [PV.MaxTime]));
  Writeln(Format('Total min %d', [PV.MinTime]));
  Writeln(Format('Total avg %d', [PV.Total div PV.Count]));
end;

begin
  try
    uprof.MiltiThread := True;
    TThread.CreateAnonymousThread(Test).Start;
    Test;
    Sleep(50);
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.

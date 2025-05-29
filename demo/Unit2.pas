unit Unit2;

interface

uses
  Classes,
  SysUtils,
  uni_profiler;

  procedure StartTest2;

implementation

procedure ChildProc2;
begin
  uprof.Start('ChildProc2 Sleep 500');
  Sleep(500);
  uprof.Stop;
end;

procedure ChildProc;
begin
  uprof.Start('ChildProc Sleep 500');
  Sleep(500);
  ChildProc2;
  uprof.Stop;
end;

procedure RootProc;
var
  I: Integer;
begin
  uprof.Start('RootProc Sleep 1000');
  for I := 0 to 2 do
  begin
    Sleep(1000);
    ChildProc;
  end;
  uprof.Stop;
end;

procedure StartTest2;
var
  I: Integer;
  Report: TStringList;
begin
  // After the first test, the previously accumulated data must be reset
  uprof.Reset;

  RootProc;

  Writeln;
  Writeln('Test2: ');
  Writeln;

  // Showing a full report of all meters
  Report := uprof.GetResult;
  try
    for I := 0 to Report.Count - 1 do
      Writeln(Report[I]);
  finally
    Report.Free;
  end;
end;

end.

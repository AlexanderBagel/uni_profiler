unit Unit1;

interface

uses
  Classes,
  SysUtils,
  uni_profiler;

  procedure StartTest;

implementation

type
  TThreadReport = procedure(AThread: TThread; FullHash, IterationHash: THash);

  TThreadForProfiling = class(TThread)
  private
    FFullHash, FIterationHash: THash;
    FReport: TThreadReport;
    function CalcFactorial(Value: UInt64): UInt64;
    procedure NotifyEnd;
  protected
    procedure Execute; override;
  public
    property OnReport: TThreadReport read FReport write FReport;
  end;

{ TThreadForProfiling }

function TThreadForProfiling.CalcFactorial(Value: UInt64): UInt64;
begin
  if Value = 0 then
    Result := 1
  else
    // Because of the large value chosen for load emulation,
    // there will be Integer Overflow here
    {$Q-}
    Result := Value * CalcFactorial(Value - 1);
    {$Q+}
end;

procedure TThreadForProfiling.Execute;
var
  I: Integer;
begin
  FreeOnTerminate := True;
  FFullHash := uprof.Start('Whole cycle');
  for I := 0 to 999 do
  begin
    FIterationHash := uprof.Start('Each iteration');
    CalcFactorial(10000);
    uprof.Stop;
  end;
  uprof.Stop;
  Synchronize(NotifyEnd);
end;

procedure TThreadForProfiling.NotifyEnd;
begin
  if Assigned(FReport) then
    FReport(Self, FFullHash, FIterationHash);
end;

var
  ThreadCount: Integer;

procedure ThreadNotify(AThread: TThread; FullHash, IterationHash: THash);
var
  PV: TProfileValue;
begin

  // Здесь показана только возможность получения значений каждого счетчика.
  // Но так как это многопоточный код, то в данном конкретном случае выводимые
  // значения будут не совсем корректны и нужно опираться на показания счетчиков
  // после завершения всех потоков.

  // This shows only the ability to retrieve the values of each counter.
  // But since this is a multithreaded code, in this particular case the output
  // values will not be quite correct and we should rely on the counter readings
  // after all threads are finished.

  Writeln('Thread: ', AThread.ThreadID, ' finished.');
  PV := uprof.GetProfileValue(IterationHash);
  Writeln(Format('Each iteration: total %d, max %7.6f, min %7.6f, avg %7.6f',
    [
    PV.Count,
    PV.MaxTime / uprof.Frequency,
    PV.MinTime / uprof.Frequency,
    PV.Total / PV.Count / uprof.Frequency
    ]));
  PV := uprof.GetProfileValue(FullHash);
  Writeln(Format('Whole cycle: %7.6f', [PV.MaxTime / uprof.Frequency]));
  Writeln;
  Dec(ThreadCount);
end;

procedure StartTest;
var
  I: Integer;
  T: TThreadForProfiling;
  Report: TStringList;
begin
  uprof.MultiThread := True;
  ThreadCount := 5;

  // Starting test threads
  for I := 0 to ThreadCount - 1 do
  begin
    T := TThreadForProfiling.Create(True);
    T.OnReport := ThreadNotify;
    T.Start;
  end;

  // Wait for all threads to complete
  while ThreadCount > 0 do
    CheckSynchronize(10);

  Writeln('Test1: ');
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

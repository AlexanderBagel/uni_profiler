////////////////////////////////////////////////////////////////////////////////
//
//  ****************************************************************************
//  * Project   : Universal profiler (Delphi/Lazarus - Windows/Linux)
//  * Unit Name : uni_profiler.pas
//  * Purpose   : Universal profiler for code profiling in Delphi and Lazarus.
//  *           : Supported operating systems: Windows/Linux.
//  *           : Supported CPUs: Intel x86_64, ARM (AARCH64)
//  * Author    : Alexander (Rouse_) Bagel
//  * Copyright : © Fangorn Wizards Lab 1998 - 2025.
//  * Version   : 1.5
//  * Home Page : http://rouse.drkb.ru
//  * Home Blog : http://alexander-bagel.blogspot.ru
//  ****************************************************************************
//  * Latest Source  : https://github.com/AlexanderBagel/uni_profiler
//  ****************************************************************************
//

// To use the profiler:
// 1. connect this module to the profiled module
// 2. to create a code block profile, place this calls on its edges
//       uprof.Start('section name') // to start profiling
//       ... profiled code here
//       uprof.Stop                  // to end profiling
// 3. save the accumulated statistics to an external file
//       uprof.SaveToFile(path to file)
// 4. use THash returned by Start() function and GetProfileValue function to get current counter values.
//    The counter values have an accuracy of 100 nanoseconds.
//    To convert to seconds, divide this value by the Frequency parameter.

unit uni_profiler;

{$UNDEF EXTENDED_RTL}
{$IFDEF FPC}
  {$I uni_profiler_fpc.inc}
{$ELSE}
  {$DEFINE EXTENDED_RTL}
{$ENDIF}

interface

uses
  {$IFDEF MSWINDOWS}
  Windows,
  {$ENDIF}
  {$IFDEF LINUX}
  linux, unixtype,
  {$ENDIF LINUX}
  Classes, SysUtils, SyncObjs, Generics.Collections, Generics.Defaults;

const
  TicksPerMillisecond = 10000;
  TicksPerSecond = 10000000;

type
  THash = Pointer;

  /// <summary>
  ///  TProfileValue: Contains the current values for the specified hash.
  ///  MinTime, MaxTime, Total = 100 nanosecond resolution
  /// </summary>
  TProfileValue = record
    // Net execution time of the procedure without taking into account the call of children under profiling
    MinTimeClean, MaxTimeClean, TotalClean,
    // Total time of the procedure taking into account the call of children under profiling
    MinTime, MaxTime, Total,
    Count: Int64;
  end;

  TStackParam = record
    Hash: THash;
    StartTimeFull, StartTimeClean: Int64;
  end;

  TStackEx<T> = class(TStack<T>)
  {$IFNDEF EXTENDED_RTL}
  protected type
    TArrayOfT = array of T;
  public
    property List: TArrayOfT read FItems;
  {$ENDIF}
  end;

  TUniversalProfiler = class
  private
    class var _Instance: TUniversalProfiler;
    class destructor ClassDestroy;
  private
    FFrequency: Int64;
    FIsHighResolution: Boolean;
    FLock: TCriticalSection;
    FMaxNameLen: Integer;
    FMultiThread: Boolean;
    FSaveOnShutdown: Boolean;
    FValues: TDictionary<THash, TProfileValue>;
    FValueDescriptions: TDictionary<THash, string>;
    FThreads: TObjectDictionary<TThreadID, TStackEx<TStackParam>>;
    FFilePath: string;
    function GetNow: Int64;
    function InternalStart(const ASectionName: string; AHash: THash): THash;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>The method returns the description previously set when Start() was called.</summary>
    function GetHashDescription(AHash: THash): string;
    /// <summary>The method returns the current counter values by the passed hash.</summary>
    function GetProfileValue(AHash: THash): TProfileValue;
    /// <summary>The function collects complete statistics on accumulated counter values and returns it in a formatted form.</summary>
    /// <return>The function returns a TStringList which should be destroyed by the calling code.</return>
    function GetResult: TStringList;
    /// <summary>Reset all counter values.</summary>
    procedure Reset;
    /// <summary>The method collects complete statistics on accumulated counter values and save it in a formatted form.</summary>
    procedure SaveToFile(const AFilePath: string; SkipIfEmpty: Boolean = True);
    /// <summary>The function sets a new observation point.</summary>
    /// <return>The function returns a THash which desribe a new observation point.</return>
    function Start(const ASectionName: string): THash;
    /// <summary>The procedure deletes the previous observation point and updates the statistics by the previous point's THash.</summary>
    procedure Stop;
    /// <summary>The property contains the current frequency of the counters.</summary>
    property Frequency: Int64 read FFrequency;
    /// <summary>The property enables support for multithreading.</summary>
    property MultiThread: Boolean read FMultiThread write FMultiThread;
    /// <summary>The property enables automatic saving of accumulated counter values at the end of the process.</summary>
    property SaveOnShutdown: Boolean read FSaveOnShutdown write FSaveOnShutdown;
    /// <summary>Default path for autosave on process termination..</summary>
    property SaveOnShutdownDirectory: string read FFilePath write FFilePath;
  end;

  /// <summary>Single point of entry for accessing the profiler instance.</summary>
  function uprof: TUniversalProfiler;

implementation

uses
  Math;

function uprof: TUniversalProfiler;
begin
  if TUniversalProfiler._Instance = nil then
    TUniversalProfiler._Instance := TUniversalProfiler.Create;
  Result := TUniversalProfiler._Instance;
end;

{ TUniversalProfiler }

class destructor TUniversalProfiler.ClassDestroy;
begin
  FreeAndNil(_Instance);
end;

constructor TUniversalProfiler.Create;
{$IFDEF LINUX}
var
  Measure: TTimeSpec;
{$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  FIsHighResolution := QueryPerformanceFrequency(FFrequency);
  if not FIsHighResolution then
    FFrequency := TicksPerSecond;
  {$ENDIF}
  {$IFDEF LINUX}
  FIsHighResolution := (clock_getres(CLOCK_MONOTONIC, @Measure) = 0) and (Measure.tv_nsec <> 0);
  Measure.tv_nsec := Max(Measure.tv_nsec, 1);
  FFrequency := (TicksPerSecond div Measure.tv_nsec) * 100; // 100 nanosecond
  {$ENDIF}
  FLock := TCriticalSection.Create;
  FValues := TDictionary<THash, TProfileValue>.Create;
  FValueDescriptions := TDictionary<THash, string>.Create;
  FThreads := TObjectDictionary<TThreadID, TStackEx<TStackParam>>.Create([doOwnsValues]);
  FSaveOnShutdown := True;
  FMaxNameLen := 4;
end;

destructor TUniversalProfiler.Destroy;
var
  Path: string;
begin
  if SaveOnShutdown then
  begin
    if SaveOnShutdownDirectory <> '' then
    begin
      Path := IncludeTrailingPathDelimiter(SaveOnShutdownDirectory);
      if not DirectoryExists(Path) then
        ForceDirectories(Path);
    end
    else
      Path := ExtractFilePath(ParamStr(0));
    SaveToFile(Path + 'profiler.txt');
  end;
  FLock.Free;
  FValues.Free;
  FValueDescriptions.Free;
  FThreads.Free;
  inherited;
end;

function TUniversalProfiler.GetHashDescription(AHash: THash): string;
begin
  Result := '';
  FValueDescriptions.TryGetValue(AHash, Result);
end;

function TUniversalProfiler.GetNow: Int64;
{$IFDEF LINUX}
var
  Measure: TTimeSpec;
{$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  if FIsHighResolution then
    QueryPerformanceCounter(Result{%H-})
  else
    Result := {%H-}GetTickCount * Int64(TicksPerMillisecond);
  {$ENDIF}
  {$IFDEF LINUX}
  clock_gettime(CLOCK_MONOTONIC, @Measure);
  Result := (Measure.tv_sec  * 1000000000) + Measure.tv_nsec;
  {$ENDIF}
end;

function TUniversalProfiler.GetProfileValue(AHash: THash): TProfileValue;
begin
  if MultiThread then FLock.Enter;
  try
    Result := Default(TProfileValue);
    FValues.TryGetValue(AHash, Result);
  finally
    if MultiThread then FLock.Leave;
  end;
end;

type
  TSortRec = record
    Hash: THash;
    Value: TProfileValue;
  end;

function ProfilerCompare(const A, B: TSortRec): Integer;
begin
  // descending order
  Result := IfThen(A.Value.Total < B.Value.Total, 1,
    IfThen(A.Value.Total = B.Value.Total, 0, -1));
end;

function TUniversalProfiler.GetResult: TStringList;
var
  Hashes: TArray<THash>;
  List: TList<TSortRec>;
  I: Integer;
  SortRec: TSortRec;
  HashName: string;
  NameLenIncValue: Integer;
begin
  if MultiThread then FLock.Enter;
  try
    Result := TStringList.Create;
    Hashes := FValues.Keys.ToArray;
    List := TList<TSortRec>.Create(TComparer<TSortRec>.Construct({$IFDEF FPC}@{$ENDIF}ProfilerCompare));
    try
      NameLenIncValue := 0;
      for I := 0 to Length(Hashes) - 1 do
      begin
        SortRec.Hash := Hashes[I];
        FValues.TryGetValue(SortRec.Hash, SortRec.Value);
        if SortRec.Value.Total <> SortRec.Value.TotalClean then
          NameLenIncValue := 8;
        List.Add(SortRec);
      end;
      Result.Add(Format('%16s | %*s | %8s | %16s | %16s | %16s | %16s |', [
        'Hash', FMaxNameLen + NameLenIncValue, 'Name', 'Count', 'Total', 'Average', 'Max', 'Min']));
      List.Sort;
      for SortRec in List do
      begin
        FValueDescriptions.TryGetValue(SortRec.Hash, HashName);
        if SortRec.Value.Total <> SortRec.Value.TotalClean then
        begin
          Result.Add(Format(
            '%16p | %*s | %8d | %16.6f | %16.6f | %16.6f | %16.6f |', [
            SortRec.Hash, FMaxNameLen + 8, HashName + ' (Full)', SortRec.Value.Count,
            SortRec.Value.Total / Frequency,
            SortRec.Value.Total / SortRec.Value.Count / Frequency,
            SortRec.Value.MaxTime / Frequency,
            SortRec.Value.MinTime / Frequency]));
          Result.Add(Format(
            '%16s | %*s | %8d | %16.6f | %16.6f | %16.6f | %16.6f |', [
            '', FMaxNameLen + 8, HashName + ' (Clean)', SortRec.Value.Count,
            SortRec.Value.TotalClean / Frequency,
            SortRec.Value.TotalClean / SortRec.Value.Count / Frequency,
            SortRec.Value.MaxTimeClean / Frequency,
            SortRec.Value.MinTimeClean / Frequency]));
        end
        else
          Result.Add(Format(
            '%16p | %*s | %8d | %16.6f | %16.6f | %16.6f | %16.6f |', [
            SortRec.Hash, FMaxNameLen + NameLenIncValue, HashName, SortRec.Value.Count,
            SortRec.Value.Total / Frequency,
            SortRec.Value.Total / SortRec.Value.Count / Frequency,
            SortRec.Value.MaxTime / Frequency,
            SortRec.Value.MinTime / Frequency]));
      end;
    finally
      List.Free;
    end;
  finally
    if MultiThread then FLock.Leave;
  end;
end;

function TUniversalProfiler.InternalStart(const ASectionName: string;
  AHash: THash): THash;
var
  ProfileValue: TProfileValue;
  PresentSectionName: string;
  ThreadID: TThreadID;
  ThreadStack: TStackEx<TStackParam>;
  StackParam: TStackParam;
begin
  if MultiThread then FLock.Enter;
  try
    FMaxNameLen := Max(FMaxNameLen, Length(ASectionName));
    StackParam.Hash := AHash;
    if not FValueDescriptions.TryGetValue(StackParam.Hash, PresentSectionName) then
      FValueDescriptions.Add(StackParam.Hash, ASectionName);
    ProfileValue := Default(TProfileValue);
    if not FValues.TryGetValue(StackParam.Hash, ProfileValue) then
      FValues.Add(StackParam.Hash, ProfileValue);
    ThreadID := GetCurrentThreadId;
    if not FThreads.TryGetValue(ThreadID, ThreadStack) then
    begin
      ThreadStack := TStackEx<TStackParam>.Create;
      FThreads.Add(ThreadID, ThreadStack);
    end;
    Result := StackParam.Hash;
    StackParam.StartTimeFull := GetNow;
    StackParam.StartTimeClean := StackParam.StartTimeFull;
    ThreadStack.Push(StackParam);
  finally
    if MultiThread then FLock.Leave;
  end;
end;

procedure TUniversalProfiler.Reset;
begin
  if MultiThread then FLock.Enter;
  try
    FMaxNameLen := 0;
    FValues.Clear;
    FValueDescriptions.Clear;
    FThreads.Clear;
  finally
    if MultiThread then FLock.Leave;
  end;
end;

procedure TUniversalProfiler.SaveToFile(const AFilePath: string;
  SkipIfEmpty: Boolean);
var
  ResultList: TStringList;
begin
  ResultList := GetResult;
  try
    if SkipIfEmpty and (ResultList.Count = 1) then Exit;
    ResultList.SaveToFile(AFilePath);
  finally
    ResultList.Free;
  end;
end;

function TUniversalProfiler.Start(const ASectionName: string): THash;  assembler; {$IFDEF FPC}nostackframe;{$ENDIF}
asm
  {$IFDEF CPUAARCH64}
    mov x2, x30
    b InternalStart
  {$ENDIF}

  {$IFDEF CPUX86}
    mov ecx, [esp]
    jmp InternalStart
  {$ENDIF}

  {$IFDEF CPUX64}
    {$IFNDEF FPC}
      .noframe
    {$ENDIF}
    {$IFDEF MSWINDOWS}
      mov r8, [rsp]
    {$ENDIF}
    {$IFDEF LINUX}
      mov rdx, [rsp]
    {$ENDIF}
    jmp InternalStart
  {$ENDIF}

end;

procedure TUniversalProfiler.Stop;
var
  StopTime, StopTimeClean, StopTimeFull: Int64;
  ThreadID: TThreadID;
  ThreadStack: TStackEx<TStackParam>;
  StackParam: TStackParam;
  ProfileValue: TProfileValue;
  Idx: Integer;
begin
  StopTime := GetNow;
  if MultiThread then FLock.Enter;
  try
    ThreadID := GetCurrentThreadId;
    if not FThreads.TryGetValue(ThreadID, ThreadStack) then Exit;
    if ThreadStack.Count = 0 then Exit;
    StackParam := ThreadStack.Pop;

    StopTimeFull := StopTime - StackParam.StartTimeFull;
    if not FValues.TryGetValue(StackParam.Hash, ProfileValue) then Exit;
    if ProfileValue.MinTime = 0 then
      ProfileValue.MinTime := StopTimeFull
    else
      ProfileValue.MinTime := Min(StopTimeFull, ProfileValue.MinTime);
    ProfileValue.MaxTime := Max(StopTimeFull, ProfileValue.MaxTime);
    Inc(ProfileValue.Total, StopTimeFull);

    StopTimeClean := StopTime - StackParam.StartTimeClean;
    if ProfileValue.MinTimeClean = 0 then
      ProfileValue.MinTimeClean := StopTimeClean
    else
      ProfileValue.MinTimeClean := Min(StopTimeClean, ProfileValue.MinTimeClean);
    ProfileValue.MaxTimeClean := Max(StopTimeClean, ProfileValue.MaxTimeClean);
    Inc(ProfileValue.TotalClean, StopTimeClean);

    Inc(ProfileValue.Count);
    Idx := ThreadStack.Count - 1;
    if Idx >= 0 then
      Inc(ThreadStack.List[Idx].StartTimeClean, StopTimeFull);

    FValues.AddOrSetValue(StackParam.Hash, ProfileValue);
  finally
    if MultiThread then FLock.Leave;
  end;
end;

end.

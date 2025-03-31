#define Dependency_Path_DotNet "Dependencies\\"
#define Dependency_Path_VC2022 "Dependencies\\"
#define Dependency_Path_WebView2 "Dependencies\\"
#define Dependency_Path_DirectX "Dependencies\\"

[Code]
type
  TDependency_Entry = record
    Filename: String;
    Parameters: String;
    Title: String;
    URL: String;
    Checksum: String;
    ForceSuccess: Boolean;
    RestartAfter: Boolean;
  end;

var
  Dependency_Memo: String;
  Dependency_List: array of TDependency_Entry;
  Dependency_NeedToRestart, Dependency_ForceX86: Boolean;
  Dependency_DownloadPage: TDownloadWizardPage;

procedure Dependency_Add(const Filename, Parameters, Title, URL, Checksum: String;
  const ForceSuccess, RestartAfter: Boolean);
var
  Dependency: TDependency_Entry;
  DependencyCount: Integer;
begin
  Dependency_Memo := Dependency_Memo + #13#10 + '%1' + Title;

  Dependency.Filename := Filename;
  Dependency.Parameters := Parameters;
  Dependency.Title := Title;

  Dependency.URL := '';
  Dependency.Checksum := '';

  Dependency.ForceSuccess := ForceSuccess;
  Dependency.RestartAfter := RestartAfter;

  DependencyCount := GetArrayLength(Dependency_List);
  SetArrayLength(Dependency_List, DependencyCount + 1);
  Dependency_List[DependencyCount] := Dependency;
end;

<event('PrepareToInstall')>
function Dependency_PrepareToInstall(var NeedsRestart: Boolean): String;
var
  DependencyCount, DependencyIndex, ResultCode: Integer;
  Retry: Boolean;
  TempValue: String;
begin
  DependencyCount := GetArrayLength(Dependency_List);

  if DependencyCount > 0 then
  begin
    Dependency_DownloadPage.Show;

    for DependencyIndex := 0 to DependencyCount - 1 do
    begin
      if Dependency_List[DependencyIndex].URL <> '' then
      begin
        Dependency_DownloadPage.Clear;
        Dependency_DownloadPage.Add(
          Dependency_List[DependencyIndex].URL,
          Dependency_List[DependencyIndex].Filename,
          Dependency_List[DependencyIndex].Checksum
        );

        Retry := True;
        while Retry do
        begin
          Retry := False;
          try
            Dependency_DownloadPage.Download;
          except
            if Dependency_DownloadPage.AbortedByUser then
            begin
              Result := Dependency_List[DependencyIndex].Title;
              DependencyIndex := DependencyCount;
            end
            else
            begin
              case SuppressibleMsgBox(AddPeriod(GetExceptionMessage),
                     mbError, MB_ABORTRETRYIGNORE, IDIGNORE) of
                IDABORT:
                  begin
                    Result := Dependency_List[DependencyIndex].Title;
                    DependencyIndex := DependencyCount;
                  end;
                IDRETRY:
                  Retry := True;
              end;
            end;
          end;
        end;
      end;
    end;

    if Result = '' then
    begin
      for DependencyIndex := 0 to DependencyCount - 1 do
      begin
        Dependency_DownloadPage.SetText(Dependency_List[DependencyIndex].Title, '');
        Dependency_DownloadPage.SetProgress(DependencyIndex + 1, DependencyCount + 1);

        while True do
        begin
          ResultCode := 0;

          if ShellExec(
               '',
               ExpandConstant('{app}\') + Dependency_List[DependencyIndex].Filename,
               Dependency_List[DependencyIndex].Parameters,
               '',
               SW_SHOWNORMAL,
               ewWaitUntilTerminated,
               ResultCode
             ) then

          begin
            if Dependency_List[DependencyIndex].RestartAfter then
            begin
              if DependencyIndex = DependencyCount - 1 then
                Dependency_NeedToRestart := True
              else
              begin
                NeedsRestart := True;
                Result := Dependency_List[DependencyIndex].Title;
              end;
              break;
            end
            else if (ResultCode = 0) or Dependency_List[DependencyIndex].ForceSuccess then
            begin
              break;
            end
            else if ResultCode = 1641 then
            begin
              NeedsRestart := True;
              Result := Dependency_List[DependencyIndex].Title;
              break;
            end
            else if ResultCode = 3010 then
            begin
              Dependency_NeedToRestart := True;
              break;
            end;
          end;

          case SuppressibleMsgBox(
                 FmtMessage(
                   SetupMessage(msgErrorFunctionFailed),[Dependency_List[DependencyIndex].Title, IntToStr(ResultCode)]
                 ),
                 mbError,
                 MB_ABORTRETRYIGNORE,
                 IDIGNORE
               ) of
            IDABORT:
              begin
                Result := Dependency_List[DependencyIndex].Title;
                break;
              end;
            IDIGNORE:
              begin
                break;
              end;
          end;
        end;

        if Result <> '' then
          break;
      end;

      if NeedsRestart then
      begin
        TempValue := '"' + ExpandConstant('{srcexe}') + '" /restart=1 /LANG="' +
          ExpandConstant('{language}') + '" /DIR="' + WizardDirValue +
          '" /GROUP="' + WizardGroupValue + '" /TYPE="' +
          WizardSetupType(False) + '" /COMPONENTS="' +
          WizardSelectedComponents(False) + '" /TASKS="' +
          WizardSelectedTasks(False) + '"';
        if WizardNoIcons then
          TempValue := TempValue + ' /NOICONS';
        RegWriteStringValue(HKA, 'SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
          '{#SetupSetting("AppName")}', TempValue);
      end;
    end;

    Dependency_DownloadPage.Hide;
  end;
end;

#ifndef Dependency_NoUpdateReadyMemo
<event('UpdateReadyMemo')>
#endif
function Dependency_UpdateReadyMemo(const Space, NewLine, MemoUserInfoInfo, MemoDirInfo,
  MemoTypeInfo, MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
begin
  Result := '';
  if MemoUserInfoInfo <> '' then
    Result := Result + MemoUserInfoInfo + NewLine + NewLine;
  if MemoDirInfo <> '' then
    Result := Result + MemoDirInfo + NewLine + NewLine;
  if MemoTypeInfo <> '' then
    Result := Result + MemoTypeInfo + NewLine + NewLine;
  if MemoComponentsInfo <> '' then
    Result := Result + MemoComponentsInfo + NewLine + NewLine;
  if MemoGroupInfo <> '' then
    Result := Result + MemoGroupInfo + NewLine + NewLine;
  if MemoTasksInfo <> '' then
    Result := Result + MemoTasksInfo;

  if Dependency_Memo <> '' then
  begin
    if MemoTasksInfo = '' then
      Result := Result + SetupMessage(msgReadyMemoTasks);
    Result := Result + FmtMessage(Dependency_Memo, [Space]);
  end;
end;

<event('NeedRestart')>
function Dependency_NeedRestart: Boolean;
begin
  Result := Dependency_NeedToRestart;
end;

function Dependency_IsX64: Boolean;
begin
  Result := not Dependency_ForceX86 and Is64BitInstallMode;
end;

function Dependency_String(const x86, x64: String): String;
begin
  if Dependency_IsX64 then
    Result := x64
  else
    Result := x86;
end;

function Dependency_ArchSuffix: String;
begin
  Result := Dependency_String('', '_x64');
end;

function Dependency_ArchTitle: String;
begin
  Result := Dependency_String(' (x86)', ' (x64)');
end;

function Dependency_IsNetCoreInstalled(Runtime: String; Major, Minor, Revision: Word): Boolean;
var
  Path: String;
  ResultCode: Integer;
  Output: TExecOutput;
  LineIndex: Integer;
  LineParts: TArrayOfString;
  PackedVersion: Int64;
  LineMajor, LineMinor, LineRevision, LineBuild: Word;
begin
  if not RegQueryStringValue(HKLM32,
       'SOFTWARE\dotnet\Setup\InstalledVersions\x' + Dependency_String('86', '64'),
       'InstallLocation', Path) or not FileExists(Path + 'dotnet.exe') then
  begin
    Path := ExpandConstant(Dependency_String('{commonpf32}', '{commonpf64}')) + '\dotnet\';
  end;
  if ExecAndCaptureOutput(Path + 'dotnet.exe', '--list-runtimes', '', SW_HIDE,
       ewWaitUntilTerminated, ResultCode, Output) and (ResultCode = 0) then
  begin
    for LineIndex := 0 to Length(Output.StdOut) - 1 do
    begin
      LineParts := StringSplit(Trim(Output.StdOut[LineIndex]), [' '], stExcludeEmpty);
      if (Length(LineParts) > 1) and (Lowercase(LineParts[0]) = Lowercase(Runtime)) and
         StrToVersion(LineParts[1], PackedVersion) then
      begin
        UnpackVersionComponents(PackedVersion, LineMajor, LineMinor, LineRevision, LineBuild);
        if (LineMajor = Major) and (LineMinor = Minor) and (LineRevision >= Revision) then
        begin
          Result := True;
          exit;
        end;
      end;
    end;
  end;
  Result := False;
end;

//의존성 함수

// .NET Framework 4.7.2
procedure InstallDotNet47IfNeeded;
var
  Release: Cardinal;
  ExecResult: Integer;
begin
  if not RegQueryDWordValue(HKLM, 'SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full', 'Release', Release) or
     (Release < 461808) then
  begin
    MsgBox('.NET Framework 4.7.2가 설치되어 있지 않아 설치가 진행됩니다.', mbInformation, MB_OK);
    ShellExec('', ExpandConstant('{app}\Dependencies\dotnetframework472.exe'),
      '/lcid ' + IntToStr(GetUILanguage) + ' /passive /norestart', '', SW_SHOWNORMAL, ewWaitUntilTerminated, ExecResult);
  end
  else
    MsgBox('.NET Framework 4.7.2가 이미 설치되어 있습니다.', mbInformation, MB_OK);
end;


procedure InstallVC2015To2022IfNeeded;
var
  ExecResult: Integer;
begin
  if not IsMsiProductInstalled(
       Dependency_String('{65E5BD06-6392-3027-8C26-853107D3CF1A}', '{36F68A90-239C-34DF-B58C-64B30153CE35}'),
       PackVersionComponents(14, 42, 34433, 0)) then
  begin
    MsgBox('Visual C++ 2022 Redistributable이(가) 설치되어 있지 않아 설치가 진행됩니다.', mbInformation, MB_OK);
    ShellExec('', ExpandConstant('{app}\Dependencies\VC_redist.x64.exe'),
      '/passive /norestart', '', SW_SHOWNORMAL, ewWaitUntilTerminated, ExecResult);
  end
  else
    MsgBox('Visual C++ 2022 Redistributable이(가) 이미 설치되어 있습니다.', mbInformation, MB_OK);
end;


procedure InstallDirectXIfNeeded;
var
  DXVersion: string;
  ExecResult: Integer;
begin
  if not RegQueryStringValue(HKLM, 'SOFTWARE\Microsoft\DirectX', 'Version', DXVersion) or
     (CompareStr(DXVersion, '4.09.00.0904') < 0) then
  begin
    MsgBox('DirectX End-User Runtime이 설치되어 있지 않아 설치가 진행됩니다.', mbInformation, MB_OK);
    ShellExec('', ExpandConstant('{app}\Dependencies\directx\DXSETUP.exe'),
      '/silent', '', SW_SHOWNORMAL, ewWaitUntilTerminated, ExecResult);
  end
  else
    MsgBox('DirectX End-User Runtime이 이미 설치되어 있습니다.', mbInformation, MB_OK);
end;


procedure InstallWebView2IfNeeded;
var
  KeyPath: string;
  ExecResult: Integer;
begin
  KeyPath := 'SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}';
  if not RegValueExists(HKLM, KeyPath, 'pv') then
    KeyPath := 'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}';

  if not RegValueExists(HKLM, KeyPath, 'pv') then
  begin
    MsgBox('WebView2 Runtime이 설치되어 있지 않아 설치가 진행됩니다.', mbInformation, MB_OK);
    ShellExec('', ExpandConstant('{app}\Dependencies\MicrosoftEdgeWebview2Setup.exe'),
      '/silent /install', '', SW_SHOWNORMAL, ewWaitUntilTerminated, ExecResult);
  end
  else
    MsgBox('WebView2 Runtime이 이미 설치되어 있습니다.', mbInformation, MB_OK);
end;


procedure InstallDriversIfNeeded();
var
  i: Integer;
  RegPaths, MissingList: array of String;
  Missing: Boolean;
  MessageText: String;
begin
  if not IsWin64 then
  begin
    MsgBox('이 설치 프로그램은 64비트 시스템에서만 드라이버 설치를 지원합니다.', mbInformation, MB_OK);
    Exit;
  end;
  
RegPaths := [
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_26AC&PID_0001',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_26AC&PID_0002',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_26AC&PID_0003',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_26AC&PID_0010',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_26AC&PID_0011',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_26AC&PID_0012',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_26AC&PID_0013',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_03EB&PID_6124',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_1B4F&PID_9207',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_2341&PID_0001',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_2341&PID_0010',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_2341&PID_0036',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_2341&PID_0037',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_2341&PID_0038',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_2341&PID_0039',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_2341&PID_003B',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_2341&PID_003C',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_2341&PID_003D',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_2341&PID_003F',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_2341&PID_0041',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_2341&PID_0042',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_2341&PID_0043',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_2341&PID_0044',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_2341&PID_004D',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_2341&PID_004E',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_2341&PID_E001',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_1209&PID_5741',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_1209&PID_5740&MI_00',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_1209&PID_5740&MI_01',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_1209&PID_5740&MI_02',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_1209&PID_5740',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_2DAE&PID_0001',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_2DAE&PID_0002',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_2DAE&PID_1001',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_2DAE&PID_1002',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_2DAE&PID_1005',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_2DAE&PID_1011',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_2DAE&PID_1017',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_2DAE&PID_1015',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_26AC&PID_0001',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_26AC&PID_0002',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_26AC&PID_0003',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_2DAE&PID_1016&REV_0200',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_2DAE&PID_1026&REV_0200',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_2DAE&PID_1058&MI_00',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_2DAE&PID_1058&MI_01',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_2DAE&PID_1058&MI_02',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_2DAE&PID_1058&REV_0101',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_3162&PID_0047',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_3162&PID_0049',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_3162&PID_004B&MI_00',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_3162&PID_004B&MI_02',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_1FC9&PID_001C',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_26AC&PID_0015',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_26AC&PID_0016',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_26AC&PID_0017',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_26AC&PID_0018',
  'SYSTEM\DriverDatabase\DeviceIds\USB\VID_26AC&PID_0014'];
  
  MissingList := [];
  Missing := False;

  for i := 0 to GetArrayLength(RegPaths) - 1 do
  begin
    if not RegKeyExists(HKLM, RegPaths[i]) then
    begin
      Missing := True;
      SetArrayLength(MissingList, GetArrayLength(MissingList) + 1);
    end;
  end;

  if Missing then
  begin
    MessageText := '드라이버가 설치되어 있지 않습니다:';
    for i := 0 to GetArrayLength(MissingList) - 1 do
      MessageText := MessageText + MissingList[i];

    MsgBox(MessageText + '드라이버 설치를 시작합니다.', mbInformation, MB_OK);
    ShellExec('', ExpandConstant('{app}\Drivers\DPInstx64.exe'), '', '', SW_SHOWNORMAL, ewWaitUntilTerminated, i);
  end
  else
  begin
    MsgBox('모든 드라이버가 이미 설치되어 있습니다.', mbInformation, MB_OK);
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    InstallDriversIfNeeded();
    InstallVC2015To2022IfNeeded();
    InstallWebView2IfNeeded();
    InstallDirectXIfNeeded();
    InstallDotNet47IfNeeded();
  end;
end;

[Files]
; .NET Framework 4.7.2
Source: "Dependencies\dotnetframework472.exe"; DestDir: "{app}\Dependencies"; Flags: ignoreversion

; Visual C++ 2022
Source: "Dependencies\VC_redist.x64.exe"; DestDir: "{app}\Dependencies"; Flags: ignoreversion

; WebView2
Source: "Dependencies\MicrosoftEdgeWebview2Setup.exe"; DestDir: "{app}\Dependencies"; Flags: ignoreversion

; DirectX
Source: "Dependencies\directx\DXSETUP.exe"; DestDir: "{app}\Dependencies\directx"; Flags: ignoreversion

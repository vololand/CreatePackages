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

//의존성 등록
procedure Dependency_Add(const Filename, Parameters, Title, URL, Checksum: String;
  const ForceSuccess, RestartAfter: Boolean);
var
  Dependency: TDependency_Entry;
  DependencyCount: Integer;
begin
  //설치 목록 메모 업데이트
  Dependency_Memo := Dependency_Memo + #13#10 + '%1' + Title;

  Dependency.Filename := Filename;
  Dependency.Parameters := Parameters;
  Dependency.Title := Title;

  //재다운로드 방지
  if FileExists(ExpandConstant('{tmp}{\}') + Filename) then
    Dependency.URL := ''
  else
    Dependency.URL := URL;

  Dependency.Checksum := Checksum;
  Dependency.ForceSuccess := ForceSuccess;
  Dependency.RestartAfter := RestartAfter;

  DependencyCount := GetArrayLength(Dependency_List);
  SetArrayLength(Dependency_List, DependencyCount + 1);
  Dependency_List[DependencyCount] := Dependency;
end;

//이벤트(마법사 초기화)
<event('InitializeWizard')>
procedure Dependency_InitializeWizard;
begin
  Dependency_DownloadPage := CreateDownloadPage(SetupMessage(msgWizardPreparing),
    SetupMessage(msgPreparingDesc), nil);
end;

//이벤트(실제 설치 직전 단계)
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
    // 다운로드 페이지 표시
    Dependency_DownloadPage.Show;

    // 1) 필요한 파일 다운로드
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

    // 2) 다운로드 성공 시, 실행/설치
    if Result = '' then
    begin
      for DependencyIndex := 0 to DependencyCount - 1 do
      begin
        Dependency_DownloadPage.SetText(Dependency_List[DependencyIndex].Title, '');
        Dependency_DownloadPage.SetProgress(DependencyIndex + 1, DependencyCount + 1);

        while True do
        begin
          ResultCode := 0;

          //파일 실행
          if ShellExec(
               '',
               ExpandConstant('{tmp}{\}') + Dependency_List[DependencyIndex].Filename,
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
            else if ResultCode = 1641 then  // ERROR_SUCCESS_REBOOT_INITIATED
            begin
              NeedsRestart := True;
              Result := Dependency_List[DependencyIndex].Title;
              break;
            end
            else if ResultCode = 3010 then  // ERROR_SUCCESS_REBOOT_REQUIRED
            begin
              Dependency_NeedToRestart := True;
              break;
            end;
          end;

          // 실패 시 재시도/무시/중단
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

//이벤트(마법사 완료 직전, Ready Memo 업데이트)
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

//이벤트(NeedRestart)
<event('NeedRestart')>
function Dependency_NeedRestart: Boolean;
begin
  Result := Dependency_NeedToRestart;
end;

//CPU 아키텍처 관련 유틸 함수들
function Dependency_IsX64: Boolean;
begin
  // 강제 x86 모드가 아니고, 64비트 설치 모드라면 True
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
  // 파일명 구분용: _x64 or ''(x86)
  Result := Dependency_String('', '_x64');
end;

function Dependency_ArchTitle: String;
begin
  // 타이틀 표시용: (x86) or (x64)
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
procedure Dependency_AddDotNet47;
begin
  if not IsDotNetInstalled(net472, 0) then
  begin
    Dependency_Add('dotnetfx47.exe',
      '/lcid ' + IntToStr(GetUILanguage) + ' /passive /norestart',
      '.NET Framework 4.7.2',
      'https://go.microsoft.com/fwlink/?LinkId=863262',
      '', False, False);
  end;
end;

// Visual C++ 2015~2022
procedure Dependency_AddVC2015To2022;
begin
  if not IsMsiProductInstalled(
       Dependency_String('{65E5BD06-6392-3027-8C26-853107D3CF1A}', '{36F68A90-239C-34DF-B58C-64B30153CE35}'),
       PackVersionComponents(14, 42, 34433, 0)) then
  begin
    Dependency_Add('vcredist2022' + Dependency_ArchSuffix + '.exe',
      '/passive /norestart',
      'Visual C++ 2015-2022 Redistributable' + Dependency_ArchTitle,
      Dependency_String(
        'https://aka.ms/vs/17/release/vc_redist.x86.exe',
        'https://aka.ms/vs/17/release/vc_redist.x64.exe'
      ),
      '', False, False);
  end;
end;

// DirectX End-User Runtime
procedure Dependency_AddDirectX;
begin
  Dependency_Add('dxwebsetup.exe',
    '/q',
    'DirectX End-User Runtime',
    'https://download.microsoft.com/download/1/7/1/1718CCC4-6315-4D8E-9543-8E28A4E18C4C/dxwebsetup.exe',
    '', True, False);
end;

// WebView2 Runtime
procedure Dependency_AddWebView2;
begin
  if not RegValueExists(HKLM, Dependency_String('SOFTWARE', 'SOFTWARE\WOW6432Node') + '\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}', 'pv') then
  begin
    Dependency_Add('MicrosoftEdgeWebview2Setup.exe',
      '/silent /install',
      'WebView2 Runtime',
      'https://go.microsoft.com/fwlink/p/?LinkId=2124703',
      '', False, False);
  end;
end;
// Driver
procedure InstallDriversIfNeeded();
var
  i: Integer;
  RequiredKeys: array of String;
  MissingDriver: Boolean;
begin
  // 64bit os check
  if not IsWin64 then
  begin
    MsgBox('이 설치 프로그램은 64비트 시스템에서만 드라이버 설치를 지원합니다.', mbInformation, MB_OK);
    Exit;
  end;

  MissingDriver := False;
  RequiredKeys := [
    'SYSTEM\CurrentControlSet\Control\Class\{4D36E978-E325-11CE-BFC1-08002BE10318}', 
    'SYSTEM\CurrentControlSet\Control\Class\{36FC9E60-C465-11CF-8056-444553540000}',
    'SYSTEM\CurrentControlSet\Control\Class\{01105872-BF45-43BE-8B67-3C0F2B8CF0D9}'];

  for i := 0 to GetArrayLength(RequiredKeys) - 1 do
  begin
    if not RegKeyExists(HKLM, RequiredKeys[i]) then
    begin
      MissingDriver := True;
      break;
    end;
  end;

  if MissingDriver then
  begin
    MsgBox('필요한 드라이버가 누락되어 설치를 시작합니다.', mbInformation, MB_OK);
    ShellExec('', ExpandConstant('{app}\Drivers\DPInstx64.exe'), '', '', SW_SHOWNORMAL, ewWaitUntilTerminated, i);
  end
  else
  begin
    MsgBox('모든 드라이버가 이미 설치되어 있습니다.', mbInformation, MB_OK);
  end;
end;



//설치 시작 전 설치 여부 확인 및 알림
function InitializeSetup(): Boolean;
var
  Version: String;
  PackedVersion, DirectXPackedVersion, DirectXMinimumVersion: Int64;
  DirectXVersion: String;
begin
  // .NET Framework 4.7.2
  if IsDotNetInstalled(net472, 0) then
    MsgBox('.NET Framework 4.7.2가 이미 설치되어 있습니다.', mbInformation, MB_OK)
  else
    Dependency_AddDotNet47();

  // Visual C++ 2015-2022
  if IsMsiProductInstalled(
       Dependency_String('{65E5BD06-6392-3027-8C26-853107D3CF1A}', 
                          '{36F68A90-239C-34DF-B58C-64B30153CE35}'),
       PackVersionComponents(14, 42, 34433, 0)) then
    MsgBox('Visual C++ 2015-2022 Redistributable이(가) 이미 설치되어 있습니다.', mbInformation, MB_OK)
  else
    Dependency_AddVC2015To2022();

  // DirectX - 3d hud, 3d flight view etc..
  if RegQueryStringValue(HKLM, 'SOFTWARE\Microsoft\DirectX', 'Version', DirectXVersion)
     and StrToVersion(DirectXVersion, DirectXPackedVersion) then
  begin
    StrToVersion('4.09.00.0904', DirectXMinimumVersion);
    if ComparePackedVersion(DirectXPackedVersion, DirectXMinimumVersion) >= 0 then
      MsgBox('DirectX End-User Runtime이 이미 설치되어 있습니다.', mbInformation, MB_OK)
    else
      Dependency_AddDirectX();
  end
  else
    Dependency_AddDirectX();

  // WebView2 Runtime - UI Web, help, release note etc..
  if RegValueExists(HKLM, Dependency_String('SOFTWARE', 'SOFTWARE\WOW6432Node') + '\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}', 'pv') then
    MsgBox('WebView2 Runtime이 이미 설치되어 있습니다.', mbInformation, MB_OK)
  else
    Dependency_AddWebView2();

  Result := True; 
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    InstallDriversIfNeeded();
  end;
end;

[Files]
#ifdef Dependency_Path_DirectX
Source: "{#Dependency_Path_DirectX}dxwebsetup.exe"; Flags: dontcopy noencryption
#endif

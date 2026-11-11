; Inno Setup Script for Orkeed Clothes ERP
; Automatically checks and installs Microsoft Visual C++ 2015-2022 Redistributable (x64)
; to prevent missing MSVCP140.dll / VCRUNTIME140.dll crashes on client machines.

#define MyAppName "Orkeed Clothes ERP"
#define MyAppArabicName "نظام أوركيد لإدارة محلات الملابس"
#define MyAppVersion "1.0.1"
#define MyAppPublisher "Orkeed ERP"
#define MyAppExeName "clothes_erp.exe"
#define MyAppSourceDir "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{9F82A0E1-4D3B-4921-8172-BD873832B6F1}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\..\build\installer
OutputBaseFilename=OrkeedClothesERP_Setup_v{#MyAppVersion}
SetupIconFile=..\runner\resources\app_icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible
PrivilegesRequired=admin
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; 1. Flutter Release application bundle
Source: "{#MyAppSourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

; 2. Optional bundled VC++ Redistributable (if placed in windows\installer\vc_redist.x64.exe at compile time)
#if FileExists("vc_redist.x64.exe")
Source: "vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall
#endif

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\{#MyAppExeName}"
Name: "{group}\إلغاء تثبيت البرنامج (Uninstall)"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; IconFilename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; Run VC++ Redistributable if needed
#if FileExists("vc_redist.x64.exe")
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; Check: VCRedistNeedsInstall; StatusMsg: "جاري تثبيت حزمة Microsoft Visual C++ Redistributable المطلوبة..."; Flags: waituntilterminated
#else
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; Check: VCRedistNeedsInstallAndDownloaded; StatusMsg: "جاري تثبيت حزمة Microsoft Visual C++ Redistributable المطلوبة..."; Flags: waituntilterminated
#endif

; Launch application after install
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

[Code]
var
  VCDownloaded: Boolean;

// Function to check if VC++ 2015-2022 (x64) is installed via Registry
function VCRedistNeedsInstall: Boolean;
var
  InstalledVal: Cardinal;
  BitnessKey: string;
begin
  Result := True;
  
  // 1. Check registry key for Visual Studio 2015-2022 runtime
  BitnessKey := 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64';
  if RegQueryDWordValue(HKEY_LOCAL_MACHINE, BitnessKey, 'Installed', InstalledVal) then
  begin
    if InstalledVal = 1 then
    begin
      Result := False;
      Exit;
    end;
  end;

  // 2. Check 32-bit registry hive redirection if 64-bit app on WOW64
  BitnessKey := 'SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64';
  if RegQueryDWordValue(HKEY_LOCAL_MACHINE, BitnessKey, 'Installed', InstalledVal) then
  begin
    if InstalledVal = 1 then
    begin
      Result := False;
      Exit;
    end;
  end;

  // 3. Fallback: Check if msvcp140.dll and vcruntime140.dll exist in System32
  if FileExists(ExpandConstant('{sys}\msvcp140.dll')) and FileExists(ExpandConstant('{sys}\vcruntime140.dll')) then
  begin
    Result := False;
    Exit;
  end;
end;

// If VC++ is not bundled, download it during setup preparation
function NextButtonClick(CurPageID: Integer): Boolean;
var
  DownloadPage: TDownloadWizardPage;
begin
  Result := True;

  #if !FileExists("vc_redist.x64.exe")
  if (CurPageID = wpReady) and VCRedistNeedsInstall and not VCDownloaded then
  begin
    DownloadPage := CreateDownloadPage(
      'تثبيت المتطلبات الأساسية (Prerequisites)',
      'جاري تحميل حزمة Microsoft Visual C++ Redistributable...',
      nil
    );
    DownloadPage.Clear;
    DownloadPage.Add('https://aka.ms/vs/17/release/vc_redist.x64.exe', 'vc_redist.x64.exe', '');
    DownloadPage.Show;
    try
      try
        DownloadPage.Download;
        VCDownloaded := True;
      except
        Log('فشل تحميل حزمة Visual C++ تلقائياً: ' + GetExceptionMessage);
        MsgBox('تنبيه: تعذر تحميل حزمة Visual C++ Redistributable تلقائياً. في حال واجهت مشكلة في تشغيل البرنامج، يرجى تثبيتها يدوياً.', mbInformation, MB_OK);
      end;
    finally
      DownloadPage.Hide;
    end;
  end;
  #endif
end;

function VCRedistNeedsInstallAndDownloaded: Boolean;
begin
  Result := VCRedistNeedsInstall and VCDownloaded and FileExists(ExpandConstant('{tmp}\vc_redist.x64.exe'));
end;


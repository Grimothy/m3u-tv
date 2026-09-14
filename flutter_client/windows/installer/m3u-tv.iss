; Inno Setup script for the M3U TV Windows installer.
;
; This produces a standard per-user .exe installer (no admin / UAC prompt) as an
; alternative to the Microsoft Store MSIX. It is unsigned, so first launch after
; download shows a dismissible SmartScreen "unknown publisher" prompt; that is a
; single "Run anyway" click, unlike a self-signed MSIX which is a hard block
; until the user imports the signing certificate. Users who want the fully
; trusted, warning-free experience should install from the Microsoft Store.
;
; Compiled in CI (see .github/workflows/release.yml) with:
;   ISCC /DAppVersion=<x.y.z> /DSourceDir=<path to Release bundle> m3u-tv.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

; Path to the `flutter build windows --release` output bundle. Relative paths are
; resolved against this script's directory.
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

#define AppName "M3U TV"
#define AppPublisher "sparkison"
#define AppExeName "m3u_tv.exe"
#define AppURL "https://github.com/m3ue/m3u-tv"

[Setup]
; Stable per-application GUID. Never change this - it is how upgrades find and
; replace a previous install.
AppId={{6F2A9C74-1E8B-4D3A-B5C2-9A7E4F1D8C36}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}/issues
AppUpdatesURL={#AppURL}/releases
VersionInfoVersion={#AppVersion}

; Per-user install: no elevation, no UAC prompt. Lands in
; %LocalAppData%\Programs\M3U TV ({autopf} resolves there under lowest privileges).
PrivilegesRequired=lowest
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}

; x64-only, matching the Flutter Windows build.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0

; Cleanly close a running instance when upgrading in place.
CloseApplications=yes
RestartApplications=no

SetupIconFile=..\runner\resources\app_icon.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
OutputDir=.
OutputBaseFilename=m3u-tv-setup

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

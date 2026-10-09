; Inno Setup script for the CyberDog Windows installer. Built by scripts/build-windows-installer.ps1,
; which passes the version and the staged bundle directory; see docs/building-windows.md.
;
;   ISCC.exe /DAppVersion=0.1.26 /DBundleDir=<Release bundle> /DOutputDir=<dir> night_drop.iss
;
; Per-user install into %LOCALAPPDATA%\Programs, so no administrator rights and no UAC prompt.

#ifndef AppVersion
  #error Pass /DAppVersion=x.y.z
#endif
#ifndef BundleDir
  #error Pass /DBundleDir=<path to build\windows\x64\runner\Release, plus the VC++ runtime DLLs>
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif

[Setup]
; Never change AppId: Windows matches upgrades and the uninstall entry on it.
AppId={{7C1F4E52-93B8-4D0A-A6E1-5B2F8D3C9A14}
AppName=CyberDog
AppVersion={#AppVersion}
AppVerName=CyberDog {#AppVersion}
AppPublisher=CyberDog
AppPublisherURL=https://relay.dforadar.ru
AppSupportURL=https://github.com/idealhere/nightdrop
AppUpdatesURL=https://relay.dforadar.ru
VersionInfoVersion={#AppVersion}
VersionInfoProductName=CyberDog
VersionInfoDescription=CyberDog installer
DefaultDirName={localappdata}\Programs\CyberDog
DefaultGroupName=CyberDog
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir={#OutputDir}
; A stable name, like NightDrop.apk: the website links /releases/latest/download/NightDropSetup.exe,
; and a versioned name would pin a release (see CLAUDE.md, "A download link must never pin a release tag").
OutputBaseFilename=CyberDogSetup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\night_drop.exe
UninstallDisplayName=CyberDog
; No LicenseFile page: the AGPL needs no acceptance to run the program (only to copy or modify
; it), so a click-through "I accept" would misstate it. LICENSE.txt is installed instead.
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; An upgrade over a running copy: ask to close it rather than failing on locked files.
CloseApplications=yes
RestartApplications=no

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\..\LICENSE"; DestDir: "{app}"; DestName: "LICENSE.txt"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\CyberDog"; Filename: "{app}\night_drop.exe"
Name: "{autodesktop}\CyberDog"; Filename: "{app}\night_drop.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\night_drop.exe"; Description: "{cm:LaunchProgram,CyberDog}"; Flags: nowait postinstall skipifsilent

; Uninstalling removes the program, not your identity and chats: those live in
; %APPDATA%\CyberDog, so reinstalling or upgrading keeps them. To remove them too, use
; the app's own wipe (or delete that folder) before uninstalling.

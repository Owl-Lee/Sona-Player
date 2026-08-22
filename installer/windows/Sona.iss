#define MyAppName "Sona"
#define MyAppVersion "0.5.0"
#define MyAppPublisher "Owl-Lee"
#define MyAppURL "https://sona.yanbaoli.me/"
#define MyAppExeName "sonar_vault.exe"

[Setup]
AppId={{9A7B635B-B65D-46D6-A243-10B616C40C05}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL=https://github.com/Owl-Lee/Sona-Player/issues
AppUpdatesURL=https://github.com/Owl-Lee/Sona-Player/releases/latest
DefaultDirName={autopf}\Sona
DefaultGroupName=Sona
AllowNoIcons=yes
OutputDir=..\..\dist
OutputBaseFilename=Sona-Windows-x64-Setup
SetupIconFile=..\..\windows\runner\resources\sona_cutout.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
MinVersion=10.0.17763
CloseApplications=yes
RestartApplications=no
SetupLogging=yes
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
VersionInfoVersion={#MyAppVersion}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Sona"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\Sona"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,Sona}"; Flags: nowait postinstall skipifsilent

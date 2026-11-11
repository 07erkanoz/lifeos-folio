; LifeOS Ofis: the documents and the editor for anyone. Build with
; build-installer.ps1. Keep AppId stable for in-place upgrades; it is not
; Folio's, and the two install side by side.
#ifndef AppVersion
  #define AppVersion "1.8.3"
#endif
#ifndef BundleDir
  #define BundleDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef InstallerOutput
  #define InstallerOutput "..\..\build\windows\installer-ofis"
#endif

[Setup]
AppId={{7C2B5E0A-3D64-4B19-9A51-6E0F2C8D41B7}
AppName=LifeOS Ofis
AppVersion={#AppVersion}
AppPublisher=LifeOS
AppPublisherURL=https://lifeos.com.tr/ofis
AppSupportURL=https://lifeos.com.tr/ofis
AppUpdatesURL=https://lifeos.com.tr/ofis
DefaultDirName={localappdata}\Programs\LifeOS Ofis
DefaultGroupName=LifeOS Ofis
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; As Folio's: 1903 is where Windows began honouring activeCodePage=UTF-8,
; which the bundled tools rely on for a path with Turkish letters.
MinVersion=10.0.18362
WizardStyle=modern
SetupIconFile=..\..\windows\runner\resources\ofis_icon.ico
UninstallDisplayIcon={app}\lifeos_ofis.exe
LicenseFile=..\..\assets\legal\LICENSE.txt
OutputDir={#InstallerOutput}
OutputBaseFilename=LifeOS-Ofis-{#AppVersion}-Windows-x64-Setup
Compression=lzma2
SolidCompression=yes
ChangesAssociations=yes
CloseApplications=yes
CloseApplicationsFilter=lifeos_ofis.exe,*.dll
RestartApplications=no
UninstallDisplayName=LifeOS Ofis
VersionInfoVersion={#AppVersion}
VersionInfoDescription=LifeOS Ofis Kurulumu

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
turkish.DesktopShortcut=Masaüstü kısayolu oluştur
turkish.RegisterFiles=Desteklenen belgeler için Birlikte aç seçeneğine LifeOS Ofis'i ekle
turkish.LaunchOfis=LifeOS Ofis'i başlat
english.DesktopShortcut=Create a desktop shortcut
english.RegisterFiles=Add LifeOS Ofis to Open with for supported documents
english.LaunchOfis=Launch LifeOS Ofis

[Tasks]
Name: "desktopicon"; Description: "{cm:DesktopShortcut}"
Name: "associations"; Description: "{cm:RegisterFiles}"

[Files]
; Everything beside the programs is shared with Folio's build; Folio's own
; programs are left out.
Source: "{#BundleDir}\*"; DestDir: "{app}"; Excludes: "lifeos_folio.exe,lifeos_editor.exe"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\LifeOS Ofis"; Filename: "{app}\lifeos_ofis.exe"; WorkingDir: "{app}"; AppUserModelID: "com.erkanoz.lifeos.ofis"
Name: "{autodesktop}\LifeOS Ofis"; Filename: "{app}\lifeos_ofis.exe"; WorkingDir: "{app}"; AppUserModelID: "com.erkanoz.lifeos.ofis"; Tasks: desktopicon

[Registry]
; Availability only: Birlikte aç names LifeOS Ofis for what it reads. The
; default application (UserChoice) is never touched.
Root: HKCU; Subkey: "Software\Classes\Applications\lifeos_ofis.exe"; ValueType: string; ValueName: "FriendlyAppName"; ValueData: "LifeOS Ofis"; Flags: uninsdeletekey; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\Applications\lifeos_ofis.exe\DefaultIcon"; ValueType: string; ValueData: """{app}\lifeos_ofis.exe"",0"; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\Applications\lifeos_ofis.exe\shell\open\command"; ValueType: string; ValueData: """{app}\lifeos_ofis.exe"" -- ""%1"""; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\Applications\lifeos_ofis.exe\SupportedTypes"; ValueType: string; ValueName: ".udf"; ValueData: ""; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\.udf\OpenWithList\lifeos_ofis.exe"; ValueType: string; ValueData: ""; Flags: uninsdeletekey; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\Applications\lifeos_ofis.exe\SupportedTypes"; ValueType: string; ValueName: ".docx"; ValueData: ""; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\.docx\OpenWithList\lifeos_ofis.exe"; ValueType: string; ValueData: ""; Flags: uninsdeletekey; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\Applications\lifeos_ofis.exe\SupportedTypes"; ValueType: string; ValueName: ".doc"; ValueData: ""; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\.doc\OpenWithList\lifeos_ofis.exe"; ValueType: string; ValueData: ""; Flags: uninsdeletekey; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\Applications\lifeos_ofis.exe\SupportedTypes"; ValueType: string; ValueName: ".odt"; ValueData: ""; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\.odt\OpenWithList\lifeos_ofis.exe"; ValueType: string; ValueData: ""; Flags: uninsdeletekey; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\Applications\lifeos_ofis.exe\SupportedTypes"; ValueType: string; ValueName: ".rtf"; ValueData: ""; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\.rtf\OpenWithList\lifeos_ofis.exe"; ValueType: string; ValueData: ""; Flags: uninsdeletekey; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\Applications\lifeos_ofis.exe\SupportedTypes"; ValueType: string; ValueName: ".pdf"; ValueData: ""; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\.pdf\OpenWithList\lifeos_ofis.exe"; ValueType: string; ValueData: ""; Flags: uninsdeletekey; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\Applications\lifeos_ofis.exe\SupportedTypes"; ValueType: string; ValueName: ".txt"; ValueData: ""; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\.txt\OpenWithList\lifeos_ofis.exe"; ValueType: string; ValueData: ""; Flags: uninsdeletekey; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\Applications\lifeos_ofis.exe\SupportedTypes"; ValueType: string; ValueName: ".md"; ValueData: ""; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\.md\OpenWithList\lifeos_ofis.exe"; ValueType: string; ValueData: ""; Flags: uninsdeletekey; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\Applications\lifeos_ofis.exe\SupportedTypes"; ValueType: string; ValueName: ".html"; ValueData: ""; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\.html\OpenWithList\lifeos_ofis.exe"; ValueType: string; ValueData: ""; Flags: uninsdeletekey; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\Applications\lifeos_ofis.exe\SupportedTypes"; ValueType: string; ValueName: ".xlsx"; ValueData: ""; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\.xlsx\OpenWithList\lifeos_ofis.exe"; ValueType: string; ValueData: ""; Flags: uninsdeletekey; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\Applications\lifeos_ofis.exe\SupportedTypes"; ValueType: string; ValueName: ".csv"; ValueData: ""; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\.csv\OpenWithList\lifeos_ofis.exe"; ValueType: string; ValueData: ""; Flags: uninsdeletekey; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\Applications\lifeos_ofis.exe\SupportedTypes"; ValueType: string; ValueName: ".tif"; ValueData: ""; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\.tif\OpenWithList\lifeos_ofis.exe"; ValueType: string; ValueData: ""; Flags: uninsdeletekey; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\Applications\lifeos_ofis.exe\SupportedTypes"; ValueType: string; ValueName: ".tiff"; ValueData: ""; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\.tiff\OpenWithList\lifeos_ofis.exe"; ValueType: string; ValueData: ""; Flags: uninsdeletekey; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\Applications\lifeos_ofis.exe\SupportedTypes"; ValueType: string; ValueName: ".png"; ValueData: ""; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\.png\OpenWithList\lifeos_ofis.exe"; ValueType: string; ValueData: ""; Flags: uninsdeletekey; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\Applications\lifeos_ofis.exe\SupportedTypes"; ValueType: string; ValueName: ".jpg"; ValueData: ""; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\.jpg\OpenWithList\lifeos_ofis.exe"; ValueType: string; ValueData: ""; Flags: uninsdeletekey; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\Applications\lifeos_ofis.exe\SupportedTypes"; ValueType: string; ValueName: ".jpeg"; ValueData: ""; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\.jpeg\OpenWithList\lifeos_ofis.exe"; ValueType: string; ValueData: ""; Flags: uninsdeletekey; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\Applications\lifeos_ofis.exe\SupportedTypes"; ValueType: string; ValueName: ".imz"; ValueData: ""; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\.imz\OpenWithList\lifeos_ofis.exe"; ValueType: string; ValueData: ""; Flags: uninsdeletekey; Tasks: associations

[Run]
Filename: "{app}\lifeos_ofis.exe"; Description: "{cm:LaunchOfis}"; Flags: nowait postinstall skipifsilent

; No UninstallDelete: the user's documents and settings are retained.

; Build with build-installer.ps1. Keep AppId stable for in-place upgrades.
#ifndef AppVersion
  #define AppVersion "1.4.0"
#endif
#ifndef BundleDir
  #define BundleDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef InstallerOutput
  #define InstallerOutput "..\..\build\windows\installer"
#endif

[Setup]
AppId={{541D10B5-49E2-4F48-8F71-53D0177D348E}
AppName=LifeOS Folio
AppVersion={#AppVersion}
AppPublisher=Erkan ÖZ
AppPublisherURL=https://erkanoz.com
AppSupportURL=https://lifeos.com.tr
AppUpdatesURL=https://github.com/07erkanoz/lifeos-folio
DefaultDirName={localappdata}\Programs\LifeOS Folio
DefaultGroupName=LifeOS Folio
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; 1903 is where Windows began honouring activeCodePage=UTF-8, which every
; bundled tool relies on to receive a path like "Müvekkil Özlem" intact.
; Below it the setting is ignored and those tools cannot open the file.
MinVersion=10.0.18362
WizardStyle=modern
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\lifeos_folio.exe
LicenseFile=..\..\assets\legal\LICENSE.txt
OutputDir={#InstallerOutput}
OutputBaseFilename=LifeOS-Folio-{#AppVersion}-Windows-x64-Setup
Compression=lzma2
SolidCompression=yes
ChangesAssociations=yes
CloseApplications=yes
CloseApplicationsFilter=lifeos_folio.exe,*.dll
RestartApplications=no
UninstallDisplayName=LifeOS Folio
VersionInfoVersion={#AppVersion}
VersionInfoDescription=LifeOS Folio Kurulumu

[Languages]
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
turkish.DesktopShortcut=Masaüstü kısayolu oluştur
turkish.RegisterFiles=Desteklenen belgeler için Birlikte aç seçeneğine LifeOS Folio'yu ekle
turkish.ContextMenu=Dosyaların sağ tuş menüsüne Folio ile önizle / düzenle seçeneklerini ekle
turkish.LaunchFolio=LifeOS Folio'yu başlat
turkish.EditorShortcut=Masaüstüne LifeOS Editör kısayolu koy (boş UDF ile açılır)
turkish.EditorOpenWith=UDF, DOCX, RTF, ODT ve TXT için Birlikte aç seçeneğine LifeOS Editör'ü ekle
english.DesktopShortcut=Create a desktop shortcut
english.RegisterFiles=Add LifeOS Folio to Open with for supported documents
english.ContextMenu=Add Folio preview / edit commands to file context menus
english.LaunchFolio=Launch LifeOS Folio
english.EditorShortcut=Put a LifeOS Editör shortcut on the desktop (opens a blank UDF)
english.EditorOpenWith=Add LifeOS Editör to Open with for UDF, DOCX, RTF, ODT and TXT

[Tasks]
Name: "desktopicon"; Description: "{cm:DesktopShortcut}"; Flags: unchecked
Name: "associations"; Description: "{cm:RegisterFiles}"
Name: "contextmenu"; Description: "{cm:ContextMenu}"
Name: "editordesktop"; Description: "{cm:EditorShortcut}"
Name: "editoropenwith"; Description: "{cm:EditorOpenWith}"

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\LifeOS Folio"; Filename: "{app}\lifeos_folio.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\LifeOS Folio"; Filename: "{app}\lifeos_folio.exe"; WorkingDir: "{app}"; Tasks: desktopicon
; LifeOS Editör: the editor alone, a blank UDF. The shortcut carries the
; process's own AppUserModelID, so a pinned editor stays apart from Folio.
Name: "{autoprograms}\LifeOS Editör"; Filename: "{app}\lifeos_editor.exe"; WorkingDir: "{app}"; AppUserModelID: "com.erkanoz.lifeos.editor"
Name: "{autodesktop}\LifeOS Editör"; Filename: "{app}\lifeos_editor.exe"; WorkingDir: "{app}"; AppUserModelID: "com.erkanoz.lifeos.editor"; Tasks: editordesktop

[Registry]
; Register availability only. Windows UserChoice/default application is untouched.
Root: HKCU; Subkey: "Software\Classes\LifeOSEvrak.Document"; ValueType: string; ValueData: "LifeOS Folio Belgesi"; Flags: uninsdeletekey; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\LifeOSEvrak.Document\DefaultIcon"; ValueType: string; ValueData: """{app}\lifeos_folio.exe"",0"; Tasks: associations
Root: HKCU; Subkey: "Software\Classes\LifeOSEvrak.Document\shell\open\command"; ValueType: string; ValueData: """{app}\lifeos_folio.exe"" --preview -- ""%1"""; Tasks: associations
Root: HKCU; Subkey: "Software\LifeOSEvrak\Capabilities"; ValueType: string; ValueName: "ApplicationName"; ValueData: "LifeOS Folio"; Flags: uninsdeletekey; Tasks: associations
Root: HKCU; Subkey: "Software\LifeOSEvrak\Capabilities"; ValueType: string; ValueName: "ApplicationDescription"; ValueData: "Belge arama, önizleme ve düzenleme"; Tasks: associations
Root: HKCU; Subkey: "Software\RegisteredApplications"; ValueType: string; ValueName: "LifeOSEvrak"; ValueData: "Software\LifeOSEvrak\Capabilities"; Flags: uninsdeletevalue; Tasks: associations
; Birlikte aç → LifeOS Editör, for what its text editor opens.
Root: HKCU; Subkey: "Software\Classes\Applications\lifeos_editor.exe"; ValueType: string; ValueName: "FriendlyAppName"; ValueData: "LifeOS Editör"; Flags: uninsdeletekey; Tasks: editoropenwith
Root: HKCU; Subkey: "Software\Classes\Applications\lifeos_editor.exe\shell\open\command"; ValueType: string; ValueData: """{app}\lifeos_editor.exe"" -- ""%1"""; Tasks: editoropenwith
Root: HKCU; Subkey: "Software\Classes\Applications\lifeos_editor.exe\SupportedTypes"; ValueType: string; ValueName: ".udf"; ValueData: ""; Tasks: editoropenwith
Root: HKCU; Subkey: "Software\Classes\Applications\lifeos_editor.exe\SupportedTypes"; ValueType: string; ValueName: ".docx"; ValueData: ""; Tasks: editoropenwith
Root: HKCU; Subkey: "Software\Classes\Applications\lifeos_editor.exe\SupportedTypes"; ValueType: string; ValueName: ".rtf"; ValueData: ""; Tasks: editoropenwith
Root: HKCU; Subkey: "Software\Classes\Applications\lifeos_editor.exe\SupportedTypes"; ValueType: string; ValueName: ".odt"; ValueData: ""; Tasks: editoropenwith
Root: HKCU; Subkey: "Software\Classes\Applications\lifeos_editor.exe\SupportedTypes"; ValueType: string; ValueName: ".txt"; ValueData: ""; Tasks: editoropenwith
Root: HKCU; Subkey: "Software\Classes\.udf\OpenWithList\lifeos_editor.exe"; ValueType: string; ValueData: ""; Flags: uninsdeletekey; Tasks: editoropenwith
Root: HKCU; Subkey: "Software\Classes\.docx\OpenWithList\lifeos_editor.exe"; ValueType: string; ValueData: ""; Flags: uninsdeletekey; Tasks: editoropenwith
#include "file-associations.iss"

[Run]
Filename: "{app}\lifeos_folio.exe"; Description: "{cm:LaunchFolio}"; Flags: nowait postinstall skipifsilent

; No UninstallDelete: user documents, index, settings and history are retained.

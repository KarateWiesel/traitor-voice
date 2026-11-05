; Traitor Voice – installer for players (Inno Setup 6)
; SPDX-License-Identifier: MIT
;
; Installs the GMod client module into garrysmod\lua\bin and the TeamSpeak 3 plugin into
; %APPDATA%\TS3Client\plugins. Build: iscc /DAppVersion=0.1.0 /DBinDir=<folder with the 4 DLLs> traitorvoice.iss

#ifndef AppVersion
  #define AppVersion "0.0.0-dev"
#endif
#ifndef BinDir
  #define BinDir "..\dist"
#endif

[Setup]
AppId={{A8000DDF-65B2-4497-9163-BAF35337A0AB}
AppName=Traitor Voice
AppVersion={#AppVersion}
AppPublisher=Traitor Voice contributors
AppPublisherURL=https://github.com/KarateWiesel/traitor-voice
AppSupportURL=https://github.com/KarateWiesel/traitor-voice/issues
; {app} is the "garrysmod" folder of the Garry's Mod installation
DefaultDirName={code:GetGModDir}
AppendDefaultDirName=no
DirExistsWarning=no
UsePreviousAppDir=yes
DisableProgramGroupPage=yes
; Steam libraries can live in Program Files
PrivilegesRequired=admin
UsedUserAreasWarning=no
UninstallFilesDir={commonappdata}\TraitorVoice
UninstallDisplayName=Traitor Voice
LicenseFile=..\LICENSE
OutputDir=..\out
OutputBaseFilename=TraitorVoice-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
SetupLogging=yes

[Languages]
Name: "de"; MessagesFile: "compiler:Languages\German.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Messages]
de.SelectDirLabel3=Traitor Voice wird in den Ordner „garrysmod“ deiner Garry's-Mod-Installation installiert. Der Ordner wurde automatisch gesucht – bitte prüfen.
de.SelectDirBrowseLabel=Stimmt der Ordner, klicke auf „Weiter“. Sonst wähle ...\steamapps\common\GarrysMod\garrysmod aus.
en.SelectDirLabel3=Traitor Voice is installed into the "garrysmod" folder of your Garry's Mod installation. The folder was detected automatically – please check it.
en.SelectDirBrowseLabel=If the folder is correct, click Next. Otherwise select ...\steamapps\common\GarrysMod\garrysmod.
de.FinishedLabel=Traitor Voice ist installiert.%n%n1. TeamSpeak 3 neu starten. Unter Extras › Optionen › Addons muss „Traitor Voice“ aktiv sein.%n2. In TeamSpeak unter Optionen › Aufnahme „Sprachaktivierung“ oder „Dauerhaft senden“ wählen – das Spiel steuert, wann gesendet wird.%n3. TeamSpeak-Server betreten, dann den GMod-Server.
en.FinishedLabel=Traitor Voice is installed.%n%n1. Restart TeamSpeak 3. Under Tools › Options › Addons, "Traitor Voice" must be enabled.%n2. In TeamSpeak under Options › Capture choose "Voice activation" or "Continuous transmission" – the game decides when you send.%n3. Join the TeamSpeak server, then the GMod server.

[CustomMessages]
de.NoGMod=Im gewählten Ordner wurde keine Garry's-Mod-Installation gefunden (gameinfo.txt fehlt).%n%nTrotzdem dorthin installieren?
en.NoGMod=No Garry's Mod installation was found in the selected folder (gameinfo.txt is missing).%n%nInstall there anyway?
de.NoTS3=TeamSpeak 3 scheint nicht installiert zu sein (der Ordner AppData\Roaming\TS3Client fehlt).%n%nDownload-Seite von TeamSpeak öffnen? Die Installation läuft danach trotzdem weiter.
en.NoTS3=TeamSpeak 3 does not seem to be installed (the folder AppData\Roaming\TS3Client is missing).%n%nOpen the TeamSpeak download page? Setup continues afterwards.

[Files]
Source: "{#BinDir}\gmcl_traitorvoice_win32.dll"; DestDir: "{app}\lua\bin"; Flags: ignoreversion
Source: "{#BinDir}\gmcl_traitorvoice_win64.dll"; DestDir: "{app}\lua\bin"; Flags: ignoreversion
Source: "{#BinDir}\traitorvoice_win32.dll"; DestDir: "{userappdata}\TS3Client\plugins"; Flags: ignoreversion
Source: "{#BinDir}\traitorvoice_win64.dll"; DestDir: "{userappdata}\TS3Client\plugins"; Flags: ignoreversion

[Code]
function IsGModDir(const Dir: String): Boolean;
begin
  Result := FileExists(AddBackslash(Dir) + 'gameinfo.txt');
end;

function SteamPath(): String;
begin
  Result := '';
  if not RegQueryStringValue(HKCU, 'Software\Valve\Steam', 'SteamPath', Result) then
    if not RegQueryStringValue(HKLM, 'SOFTWARE\WOW6432Node\Valve\Steam', 'InstallPath', Result) then
      Result := ExpandConstant('{autopf32}\Steam');
  StringChangeEx(Result, '/', '\', True);
end;

// Steam libraries are listed in steamapps\libraryfolders.vdf as lines like:  "path"  "D:\\SteamLibrary"
function FindGModInLibraries(const Steam: String): String;
var
  Lines: TArrayOfString;
  I, P: Integer;
  Line, Lib, Candidate: String;
begin
  Result := '';
  Candidate := AddBackslash(Steam) + 'steamapps\common\GarrysMod\garrysmod';
  if IsGModDir(Candidate) then begin
    Result := Candidate;
    Exit;
  end;
  if not LoadStringsFromFile(AddBackslash(Steam) + 'steamapps\libraryfolders.vdf', Lines) then
    Exit;
  for I := 0 to GetArrayLength(Lines) - 1 do begin
    Line := Trim(Lines[I]);
    if Pos('"path"', Lowercase(Line)) = 1 then begin
      Lib := Trim(Copy(Line, 7, Length(Line)));
      P := Pos('"', Lib);
      if P = 1 then begin
        Lib := Copy(Lib, 2, Length(Lib) - 2);
        StringChangeEx(Lib, '\\', '\', True);
        Candidate := AddBackslash(Lib) + 'steamapps\common\GarrysMod\garrysmod';
        if IsGModDir(Candidate) then begin
          Result := Candidate;
          Exit;
        end;
      end;
    end;
  end;
end;

function GetGModDir(Param: String): String;
var
  Steam: String;
begin
  Steam := SteamPath();
  Result := FindGModInLibraries(Steam);
  if Result = '' then
    Result := AddBackslash(Steam) + 'steamapps\common\GarrysMod\garrysmod';
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  ErrorCode: Integer;
begin
  Result := True;
  if CurPageID = wpSelectDir then begin
    if not IsGModDir(WizardDirValue()) then
      Result := MsgBox(CustomMessage('NoGMod'), mbConfirmation, MB_YESNO) = IDYES;
  end else if CurPageID = wpReady then begin
    if not DirExists(ExpandConstant('{userappdata}\TS3Client')) then
      if MsgBox(CustomMessage('NoTS3'), mbConfirmation, MB_YESNO) = IDYES then
        ShellExec('open', 'https://www.teamspeak.com/en/downloads/#ts3client', '', '', SW_SHOWNORMAL, ewNoWait, ErrorCode);
  end;
end;

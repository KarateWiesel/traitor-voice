# Traitor Voice – Testanleitung (M0)

Ziel von M0: Prüfen, dass die Kette **GMod → DLL → TeamSpeak-Plugin** funktioniert und die
Lautstärke eines Mitspielers live der Entfernung folgt. Dafür braucht es 2 Personen.

## 1. Dateien holen

GitHub → [Releases](https://github.com/KarateWiesel/traitor-voice/releases) → neuestes Release. Darin:

| Datei | Für wen |
| --- | --- |
| `TraitorVoice-Setup-….exe` | jeder Spieler |
| `traitor-voice-server-addon-….zip` | den GMod-Server |
| `traitor-voice-windows-manual-….zip` | nur falls der Installer nicht geht (DLLs zum Kopieren) |

## 2. Spieler (beide Tester)

1. `TraitorVoice-Setup-….exe` ausführen. Windows zeigt evtl. „Der Computer wurde durch Windows geschützt“ →
   **Weitere Informationen → Trotzdem ausführen** (der Installer ist nicht kostenpflichtig signiert).
2. Der Installer findet Garry's Mod selbst. Er legt das Modul nach `garrysmod\lua\bin\` und das Plugin nach
   `%APPDATA%\TS3Client\plugins\`.
3. TeamSpeak 3 neu starten → **Extras → Optionen → Addons**: „Traitor Voice“ muss aktiv sein.
4. In TeamSpeak unter **Optionen → Aufnahme** „Sprachaktivierung“ oder „Dauerhaft senden“ einstellen
   (nicht TeamSpeaks eigenes Push-to-Talk). Ab jetzt steuert das Spiel, wann gesendet wird.
5. Beide in **denselben** TS-Channel.

Die Spieler brauchen **nichts aus dem Workshop**: Die Lua-Dateien schickt der GMod-Server beim Beitreten
automatisch mit.

Ohne Installer: aus dem Manual-ZIP `gmod-lua-bin\*.dll` nach `…\GarrysMod\garrysmod\lua\bin\` (Ordner `bin`
ggf. anlegen) und `teamspeak-plugins\*.dll` nach `%APPDATA%\TS3Client\plugins\` kopieren.

## 3. Server

1. `traitor-voice-server-addon-….zip` entpacken und den Ordner `traitor-voice` nach `garrysmod/addons/`
   auf den GMod-Server legen (Linux ist ok – serverseitig läuft nur Lua).
2. Server starten. Die Config entsteht unter `garrysmod/data/traitorvoice/config.json`.
3. `teamspeak.address` eintragen, in der Server-Konsole `traitorvoice_reload`.

## 4. Test

1. Beide auf den Server. Nach max. 20 s muss jeder **ohne** schwarze Sperr-Einblendung spielen können.
2. Server-Konsole: `traitorvoice_status` → beide Spieler mit `ok=true` und einer `ts-id`.
3. Taste **V** halten und sprechen (Belegung änderbar: F1 → Tastenbelegung → Traitor Voice).
4. Auseinanderlaufen: Ab ca. 3 m wird die Stimme leiser, bei 12 m (Stufe „Normal“) ist sie weg.
5. **Bild↑ / Bild↓** wechselt die Sprechstufe (Anzeige links am Bildschirm).
6. Hinter eine Wand gehen: Stimme wird dumpf.
7. **Caps Lock** halten: Funk – überall auf der Map hörbar, mit Funk-Klang.
8. Einer stirbt: Der Tote hört den Lebenden weiter; der Lebende hört den Toten nicht.

## Was mir zurückmelden?

- Welche Schritte klappen, welche nicht
- Bei Problemen: GMod-Konsole (Zeilen mit `[Traitor Voice]`), Ausgabe von `traitorvoice_status`,
  TeamSpeak **Extras → Client-Log** (Zeilen mit `TraitorVoice`)

## Bekannte Grenzen von M0

- Keine Klick-Sounds beim Funk, keine Lautstärke pro Spieler
- Nur Windows für Spieler

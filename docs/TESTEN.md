# Traitor Voice – Testanleitung (M0)

Ziel von M0: Prüfen, dass die Kette **GMod → DLL → TeamSpeak-Plugin** funktioniert und die
Lautstärke eines Mitspielers live der Entfernung folgt. Dafür braucht es 2 Personen.

## 1. Dateien holen

GitHub → Tab **Actions** → letzter Lauf von „Build“ → Artefakt **traitor-voice-windows** herunterladen
und entpacken. Darin:

| Ordner | Inhalt |
| --- | --- |
| `gmod-lua-bin/` | `gmcl_traitorvoice_win32.dll`, `gmcl_traitorvoice_win64.dll` |
| `teamspeak-plugins/` | `traitorvoice_win32.dll`, `traitorvoice_win64.dll` |

(Ein Installer kommt in M6. Bis dahin von Hand kopieren.)

## 2. Spieler (beide Tester)

1. Beide `gmcl_traitorvoice_*.dll` nach
   `…\Steam\steamapps\common\GarrysMod\garrysmod\lua\bin\` kopieren (Ordner `bin` ggf. anlegen).
2. Beide `traitorvoice_*.dll` nach `%APPDATA%\TS3Client\plugins\` kopieren.
3. TeamSpeak 3 neu starten → **Extras → Optionen → Addons**: „Traitor Voice“ muss aktiv sein.
4. In TeamSpeak unter **Optionen → Aufnahme** „Sprachaktivierung“ oder „Dauerhaft senden“ einstellen
   (nicht TeamSpeaks eigenes Push-to-Talk). Ab jetzt steuert das Spiel, wann gesendet wird.
5. Beide in **denselben** TS-Channel.

## 3. Server

1. Ordner `addon/` aus dem Repo nach `garrysmod/addons/traitor-voice/` auf den GMod-Server kopieren
   (Linux ist ok – serverseitig läuft nur Lua).
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

- Kein Installer, keine Klick-Sounds beim Funk, keine Lautstärke pro Spieler
- Nur Windows für Spieler

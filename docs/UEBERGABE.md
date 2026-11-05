# Traitor Voice – Übergabe an die nächste Claude-Sitzung

Stand: 2026-11-05 · Repo: https://github.com/KarateWiesel/traitor-voice · Sprache mit dem Nutzer: **Deutsch**

Dieses Dokument enthält alles, was eine neue Sitzung braucht, um ohne Rückfragen weiterzuarbeiten.
Kurzfassung des Konzepts: [KONZEPT.md](KONZEPT.md). Testanleitung: [TESTEN.md](TESTEN.md).

---

## 1. Worum es geht

Positionsabhängiger Voice-Chat für **Garry's Mod TTT2** über **TeamSpeak 3**, nach dem Prinzip von
**ACRE 2** (Arma 3). Spieler hören sich in der Spielwelt (Entfernung, Richtung, Wände), haben ab
Rundenbeginn ein Funkgerät, und Tote hören Lebende, aber nicht umgekehrt.

## 2. Feste Entscheidungen des Nutzers (nicht neu diskutieren)

| Thema | Entscheidung |
| --- | --- |
| Name | Traitor Voice |
| Repo | `KarateWiesel/traitor-voice` (persönlicher Account), öffentlich, MIT |
| Gspeak | **Kein Fork.** Neu schreiben, Gspeak als Vorlage; übernommener Code behält Credit + steht in THIRD_PARTY_NOTICES. Gspeak muss immer klar als Quelle genannt sein. |
| ACRE 2 | nur Konzeptvorbild, GPL-3.0 → **kein ACRE-Code** |
| TeamSpeak | **ausschließlich TeamSpeak 3** (TS6 hat kein 3D-Audio) |
| TS-Channels | **Niemand wird verschoben.** Alle in einem Channel. Keine ServerQuery/WebQuery. |
| Tote | hören Lebende; Lebende hören keine Toten (Plugin der Lebenden schaltet Tote stumm, wie ACRE) |
| Funk | **ein** globaler Kanal für alle, über die ganze Map; kein Team-/Traitor-Funk, kein Whisper. Mehr Kanäle evtl. später. |
| Sprechstufen | 4 Stufen: Flüstern 2 m, Leise 6 m, Normal 12 m, Schreien 30 m – per Config live änderbar |
| Ohne TeamSpeak | bildschirmfüllende Sperr-Einblendung (so nervig, dass man nicht spielen kann), **kein Kick** |
| Plattformen | Spieler: nur Windows. GMod-Server läuft unter **Linux** → serverseitig nur Lua, keine Binärmodule |
| TS-Server | läuft auf anderer Maschine als GMod; Nutzer hat ServerQuery-Admin, soll aber nicht nötig sein |
| Einfachheit | Installation für Spieler und Serverinhaber so einfach wie möglich (Ziel: ein Installer) |

## 3. Architektur

```
GMod-Client (Lua) ──► gmcl_traitorvoice_winXX.dll ══ Shared Memory "Local\TraitorVoice_v1" ══► TS3-Plugin
        ▲                                                                                     (Klang)
        │ net (Roster, Positionen, Config)
GMod-Server (Lua, data/traitorvoice/config.json)        GMod-Server ↔ TS-Server: KEINE Verbindung
```

- **Server-Lua** entscheidet pro Hörer, wie jeder Sprecher gehört wird („Roster“: PROXIMITY / DIRECT / MUTED,
  Funk ja/nein, Sprechstufe) und ordnet SteamID ↔ TS-Client-ID zu (Client meldet seine TS-ID, die das
  Plugin über die DLL liefert).
- **Client-Lua** rechnet jeden Frame Gain (Distanz + Stufe), relative Position (Meter, x rechts / y oben /
  z vorne), Wanddämpfung (Traces, 10 Hz) und schreibt alles per `traitorvoice.Update()` in die DLL.
- **DLL** schreibt nur Shared Memory (Seqlock), keine Netzwerkverbindung.
- **TS3-Plugin** liest 50 Hz, setzt TS-3D-Positionen (`channelset3DAttributes`, Listener im Ursprung),
  schaltet TS-eigene Distanzdämpfung ab (`onCustom3dRolloffCalculationClientEvent` → 1.0), bearbeitet Audio
  in `onEditPostProcessVoiceDataEvent` (Gain, Tiefpass für Wände, Funk-Bandpass/Verzerrung/Rauschen,
  Stummschalten), steuert Push-to-Talk über `CLIENT_INPUT_DEACTIVATED`.

## 4. Was erledigt ist

### Planung
- Konzept & Planung als Claude-Doc: https://claude.ai/artifact/Jwd7uw4tfZYw4ZBXNQWhFM (mit Architektur-Diagramm,
  Entscheidungstabelle). Kurzfassung in `docs/KONZEPT.md`.
- Lizenzen geprüft: Gspeak MIT (Lizenzdateien der Teilprojekte tragen den Vermerk „Scott Chacon and others“ –
  so im Original), ACRE 2 GPL-3.0, TS3-SDK und gmod-module-base ohne Open-Source-Lizenz → werden beim Build per
  CMake `FetchContent` an festen Commits geladen, nicht ins Repo kopiert.
- ACRE-Quellcode angesehen: Zuschauer werden in `addons/sys_core/fnc_muting.sqf` von Lebenden stummgeschaltet,
  alle bleiben im selben Channel. Genau so umgesetzt.

### Code (Meilenstein M0, große Teile von M1–M4 als erste Version)

| Datei | Inhalt |
| --- | --- |
| `shared/traitorvoice_protocol.h` | Shared-Memory-Layout (32/64-Bit-sicher, `#pragma pack(4)`, static_asserts), Seqlock-Helfer |
| `module/gmcl_traitorvoice.cpp` | GMod-Modul: `traitorvoice.Update/Release/GetStatus`, `VERSION`, `PROTOCOL` |
| `ts3plugin/traitorvoice_plugin.cpp` | TS3-Plugin (API 26): Worker-Thread, 3D, Filter, PTT, Mikropegel, Sprecherliste |
| `CMakeLists.txt` | baut beide DLLs für win32/win64, statische CRT, lädt SDKs per FetchContent |
| `addon/lua/autorun/traitorvoice_init.lua` | Lade-Reihenfolge, AddCSLuaFile |
| `addon/lua/traitorvoice/sh_shared.lua` | Konstanten, Default-Config, Gain-Kurve, Rundenhelfer |
| `addon/lua/traitorvoice/sv_config.lua` | `config.json` anlegen/laden/validieren, `traitorvoice_reload` |
| `addon/lua/traitorvoice/sv_main.lua` | natives Voice aus, Reports, Roster (2 Hz + bei Änderung), Positionen dormanter Spieler (10 Hz, nur in Hörweite), `traitorvoice_status` |
| `addon/lua/traitorvoice/cl_main.lua` | Modul laden, Binds (TTT2 `bind.Register`), Gain/Position/Wände, Funk-Logik, Status + Report |
| `addon/lua/traitorvoice/cl_hud.lua` | HUD (Stufe, Funk, Mikropegel, wer spricht), Sperr-Einblendung mit Buttons |
| `addon/lua/terrortown/menus/gamemode/addons/traitorvoice.lua` | F1-Seite: Status, Lautstärke-Slider, Optionen |
| `.github/workflows/build.yml` | MSVC-Build win32+x64, Lua-Syntaxcheck, ZIP-Paket, Release bei Tag `v*` |
| `README.md`, `THIRD_PARTY_NOTICES.md`, `LICENSE` | Credits (Gspeak zuerst), MIT |
| `docs/TESTEN.md` | Schritt-für-Schritt-Test für M0 mit 2 Personen |

**Geprüft:** alle Lua-Dateien mit `luac5.1 -p`; DLL und Plugin kompilieren fehlerfrei mit mingw (i686 + x86_64);
Gain-Kurve per Lua-Test; MSVC-Build in GitHub Actions (win32 + x64) grün, Artefakt `traitor-voice-windows`
entsteht. **Nicht geprüft:** alles im Spiel.

### Standard-Tasten
`V` = Sprechen (Nahbereich), `Caps Lock` = Funk, `Bild↑/Bild↓` = Sprechstufe (Abweichung vom Konzept, das Alt+Mausrad
vorsah – TTT2-Binds kennen keine Kombinationen). Änderbar unter F1 → Tastenbelegung → Traitor Voice.

## 5. Offene Punkte, Annahmen und Risiken (bitte beim Testen im Blick behalten)

1. **MSVC-Build** läuft seit dem ersten Commit fehlerfrei. Neue Build-Fehler beheben, nicht die Architektur ändern.
2. **gmod-module-base ist alt.** `LUA_FUNCTION` wird lokal definiert; es wird nur der vordere, stabile Teil der
   `ILuaBase`-vtable benutzt. Falls GMod abstürzt: auf `danielga/garrysmod_common` Header wechseln.
3. **Push-to-Talk:** TeamSpeak muss auf „Sprachaktivierung“ oder „Dauerhaft senden“ stehen; das Plugin schaltet
   `CLIENT_INPUT_DEACTIVATED`. Beim Verlassen des Spiels wird der alte Zustand wiederhergestellt – prüfen.
4. **Funk-Start-Latenz:** Funkstatus geht über den GMod-Server (Roundtrip). Erste Silbe kann fehlen. Falls
   störend: Funkstatus zusätzlich per TS-Plugin-Command verteilen.
5. **Unbekannte TS-Nutzer im Channel** werden stummgeschaltet, solange das Spiel aktiv ist (`muteUnknown`).
6. **Positionen dormanter Spieler** werden im Umkreis der größten Reichweite (+2 m) an den Client geschickt –
   bewusst begrenztes Info-Leck.
7. **Tote Zuschauer:** Hörposition = eigene Kamera bzw. Augen des beobachteten Spielers (In-Eye).
8. **Gain-Kurve** ist quadratisch ab 25 % der Reichweite; bei Flüstern (2 m) evtl. zu steil → per Test justieren.
9. **Sample-Rate** im Plugin fest 48 kHz angenommen.
10. **TTT2-F1-Menü:** Datei liegt unter `menus/gamemode/addons/` und wird zusätzlich per AddCSLuaFile verteilt –
    prüfen, dass TTT2 sie lädt.
11. **Sperr-Einblendung** nutzt `MakePopup` (fängt die Maus). Prüfen, dass ESC/Konsole erreichbar bleiben.
12. **Whisper-Härtung** (Tote sprechen per TS-Whisper nur zu Toten, damit manipulierte Plugins Lebender nichts
    empfangen) ist **nicht** umgesetzt – erst testen, ob TS-Standardrechte Whisper erlauben.

## 6. Nächste Schritte (in dieser Reihenfolge)

1. ~~Ersten Stand pushen, GitHub-Actions-Lauf prüfen~~ – erledigt am 2026-11-05.
2. **M0-Test** mit dem Nutzer nach `docs/TESTEN.md` (2 Personen). Rückmeldungen und Logs einsammeln
   (GMod-Konsole `[Traitor Voice]`, `traitorvoice_status`, TS-Client-Log `TraitorVoice`).
3. **Fehler aus dem Test beheben**, Werte justieren (Gain-Kurve, Wanddämpfung, Funk-Effekt).
4. **Funk fertigstellen (M3):** Klick-Sounds bei Start/Ende fremder Funksprüche (Lua, anhand der Sprecherliste vom
   Plugin), ggf. Start-Latenz verbessern.
5. **Bedienung (M5):** Lautstärke/Stumm pro Spieler (Scoreboard-Rechtsklick → neues Feld im Shared Memory oder
   Gain in Lua), Symbol „nicht im TeamSpeak“ über Köpfen/Scoreboard (`NW2Bool TraitorVoice_OK` ist schon gesetzt),
   Sprachdateien (de/en) statt fester deutscher Strings, HUD-Feinschliff.
6. **Whisper-Härtung testen** und, falls möglich, standardmäßig aktivieren.
7. **Veröffentlichung (M6):** Installer (Inno Setup): GMod über `libraryfolders.vdf` finden, DLLs nach
   `garrysmod/lua/bin`, TS3-Plugin als `.ts3_plugin`-Paket oder nach `%APPDATA%\TS3Client\plugins`; Release per Tag
   `v0.1.0`; Workshop-Upload des `addon/`-Ordners (`gmad` + `gmpublish`, macht der Nutzer).
8. **Konzept-Doc aktualisieren**, wenn sich Entscheidungen ändern.

## 7. Arbeitsweise mit dem Nutzer

- Antworten auf Deutsch, knapp. Der Nutzer will Ergebnisse, kein Hin und Her.
- Der Nutzer testet auf seinem Server; Claude kann GMod/TeamSpeak nicht selbst ausführen.
- Gspeak immer als Quelle nennen; bei übernommenem Code Herkunft im Code + THIRD_PARTY_NOTICES vermerken.
- Commit-Messages mit Co-Author-Zeile laut Session-Vorgaben.
- Arbeitsordner `C:\Users\Justus\Documents\traitor-voice-m0` ist ein git-Repo mit Remote `origin` = GitHub.
  Commit + Push direkt per `git push` (Anmeldung über Git Credential Manager ist gespeichert). Der
  GitHub-Connector im Claude-Account liefert bei jedem Aufruf 404 – nicht darauf verlassen.
- Actions-Status ohne Anmeldung abfragbar: `https://api.github.com/repos/KarateWiesel/traitor-voice/actions/runs`.

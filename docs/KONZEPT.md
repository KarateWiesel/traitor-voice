# Traitor Voice – Konzept (Kurzfassung)

Ausführliche Fassung: Claude-Doc „Traitor Voice – Konzept & Planung“ (Projekt-Dokument).

## Entscheidungen

| Thema | Entscheidung |
| --- | --- |
| Name | Traitor Voice |
| Repo | `KarateWiesel/traitor-voice`, MIT |
| Gspeak | kein Fork; neu geschrieben mit Gspeak als Vorlage, übernommene Teile mit Credit |
| ACRE 2 | nur Konzeptvorbild (GPL-3.0, kein Code) |
| TeamSpeak | ausschließlich TeamSpeak 3 |
| TS-Channels | niemand wird verschoben; alle im selben Channel (ACRE-Prinzip) |
| Tote | hören Lebende; Lebende hören keine Toten |
| Funk | ein globaler Kanal für alle; kein Team-/Traitor-Funk (mehr Kanäle später möglich) |
| Sprechstufen | 4 Stufen: 2 / 6 / 12 / 30 m, per Config live änderbar |
| Ohne TeamSpeak | bildschirmfüllende Sperr-Einblendung, kein Kick |
| Plattformen | Spieler: Windows. GMod-Server: auch Linux (serverseitig nur Lua) |
| TS-Server | keine Änderungen, keine ServerQuery nötig |

## Architektur

1. **TTT2-Addon (Lua)** – Server: Rundenlogik, Tot/Lebend, Zuordnung SteamID ↔ TS-Client-ID,
   Positionen entfernter Spieler, Config. Client: berechnet pro Mitspieler Lautstärke, Richtung,
   Wanddämpfung, Funk; schreibt jeden Frame in die DLL.
2. **Client-DLL `gmcl_traitorvoice`** – Shared Memory `Local\TraitorVoice_v1`, keine Netzwerkverbindung.
3. **TS3-Plugin** – liest den Shared Memory, setzt TS-3D-Positionen, regelt Lautstärke, Filter,
   Stummschaltung, Push-to-Talk (über `CLIENT_INPUT_DEACTIVATED`).

### Zuordnung Spieler ↔ TS-Client (wie ACRE)

Plugin meldet eigene TS-Client-ID + Server-Kennung → DLL → Lua → GMod-Server → verteilt die Tabelle
an alle Clients → Shared Memory → Plugin weiß, welche Stimme zu welchem Spieler gehört.

## Meilensteine

1. **M0 Machbarkeit:** DLL lädt, Plugin liest Shared Memory, Lautstärke folgt der Distanz
2. **M1 Proximity:** Zuordnung, vier Sprechstufen, PTT, natives Voice aus, Config + Live-Reload
3. **M2 Raumklang:** Panning, Wanddämpfung
4. **M3 Funk:** globaler Kanal, Funk-Klang, Klicks
5. **M4 TTT2-Regeln:** Tote/Lebende, Rundenphasen
6. **M5 Bedienung:** F1-Menü, HUD, Status, Sperr-Einblendung
7. **M6 Veröffentlichung:** Installer, Releases, Workshop
8. **M7 Praxistest**

Der aktuelle Code deckt M0 und große Teile von M1–M4 als erste Version ab; Feinschliff folgt nach Tests.

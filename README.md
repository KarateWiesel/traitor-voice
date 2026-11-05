# Traitor Voice

Positionsabhängiger Voice-Chat für **Garry's Mod TTT2** über **TeamSpeak 3** – nach dem Prinzip von ACRE 2.

> **Credits zuerst:** Traitor Voice ist inspiriert von [Gspeak](https://github.com/Thendon/Gspeak)
> (Thendon und Mitwirkende, MIT-Lizenz) und vom Konzept von [ACRE 2](https://github.com/IDI-Systems/acre2)
> (IDI-Systems). Gspeak diente als Vorlage; Teile, die direkt aus Gspeak übernommen werden, sind im Code
> gekennzeichnet und in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) gelistet.
> Aus ACRE 2 (GPL-3.0) wird kein Code übernommen, nur Ideen.

## Was es kann (Ziel)

- Spieler hören sich in der Spielwelt: Entfernung, Richtung, Dämpfung durch Wände
- Vier Sprechstufen: Flüstern, Leise, Normal, Schreien (Reichweiten per Config)
- Ein Funkgerät für jeden Spieler ab Rundenbeginn, ein gemeinsamer Kanal über die ganze Map
- Tote hören Lebende, Lebende hören keine Toten – alle bleiben im selben TeamSpeak-Channel
- Geräte, Pegel und Rauschfilter stellt jeder wie gewohnt in TeamSpeak ein

## Wie es funktioniert

```
GMod-Client (Lua) ──► gmcl_traitorvoice.dll ══ Shared Memory ══► TS3-Plugin ──► Klang
        ▲
        │ Spielzustand (net)
GMod-Server (Lua, config.json)
```

- Das **Lua-Addon** berechnet für jeden Mitspieler Lautstärke, Richtung und Funk-Status.
- Die **Client-DLL** übergibt diese Daten lokal per Shared Memory an TeamSpeak (unter 1 ms).
- Das **TS3-Plugin** bearbeitet die Stimme jedes Sprechers (Lautstärke, 3D, Filter, Stummschalten).
- Der GMod-Server spricht nie mit dem TeamSpeak-Server. Am TS-Server muss nichts eingerichtet werden.

## Status

Frühe Entwicklung – Meilenstein **M0 (Machbarkeit)**. Siehe [docs/KONZEPT.md](docs/KONZEPT.md) und
[docs/TESTEN.md](docs/TESTEN.md).

## Installation

Alles liegt unter [Releases](https://github.com/KarateWiesel/traitor-voice/releases):

- **Spieler:** `TraitorVoice-Setup-….exe` ausführen. Er installiert das GMod-Modul und das TeamSpeak-Plugin.
  Aus dem Workshop braucht ein Spieler nichts, die Lua-Dateien kommen beim Beitreten vom Server.
- **Server:** `traitor-voice-server-addon-….zip` nach `garrysmod/addons/` entpacken, Server starten,
  `teamspeak.address` in `garrysmod/data/traitorvoice/config.json` eintragen, `traitorvoice_reload`.

## Projektstruktur

| Ordner | Inhalt |
| --- | --- |
| `addon/` | GMod-Addon (Lua) für den Server, `garrysmod/addons` (später auch Workshop) |
| `module/` | `gmcl_traitorvoice` – Client-DLL für GMod (C++, Windows win32/win64) |
| `ts3plugin/` | TeamSpeak-3-Plugin (C++, Windows) |
| `shared/` | Gemeinsames Protokoll von DLL und Plugin |
| `installer/` | Installer für Spieler (Inno Setup) |
| `docs/` | Konzept, Testanleitung |

## Bauen

GitHub Actions baut bei jedem Push DLLs, Installer und Server-ZIP (Tab **Actions** → Artefakt).
Ein Tag `v*` veröffentlicht daraus ein Release; Tags mit Bindestrich (`v0.1.0-test.1`) als Vorabversion.
Lokal mit Visual Studio 2022 und CMake:

```
cmake -S . -B build -A x64   && cmake --build build --config Release
cmake -S . -B build32 -A Win32 && cmake --build build32 --config Release
```

Die TeamSpeak-SDK-Header und die GMod-Lua-Header werden beim Konfigurieren automatisch geladen
(sie stehen nicht unter einer Open-Source-Lizenz und liegen deshalb nicht im Repo).

## Lizenz

MIT – siehe [LICENSE](LICENSE).

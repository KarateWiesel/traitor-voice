# Third-Party Notices

## Gspeak

- Projekt: https://github.com/Thendon/Gspeak
  (Teilprojekte GspeakGarrysmodPlugin, GspeakServerAddon, GspeakTeamspeakPlugin)
- Autoren laut Projekt: Thendon; Credits: Sanuye, Rataj (Plugin), Nockich (Lua), Zigi (Installer),
  El-Marto (Artworks), Kuro (Models)
- Lizenz: MIT. Die Lizenzdateien der Teilprojekte enthalten den Copyright-Vermerk
  „Copyright (c) 2012-2023 Scott Chacon and others“ (so im Original vorhanden).

Verwendung in Traitor Voice: Gspeak dient als Vorlage für die Architektur
(GMod-Modul ↔ Shared Memory ↔ TeamSpeak-Plugin, Nutzung der TeamSpeak-3D-Funktionen,
Stummschalten unbekannter Sprecher). Stand M0 wurde **kein Code wörtlich übernommen**; die Umsetzung
ist neu geschrieben. Wird künftig Code übernommen, wird er hier mit Datei und Herkunft aufgeführt
und behält im Quelltext den originalen Lizenzhinweis.

## ACRE 2

- Projekt: https://github.com/IDI-Systems/acre2 – Lizenz GPL-3.0
- Verwendung: nur als Konzeptvorbild (z. B. Zuschauer werden von Lebenden stummgeschaltet,
  alle bleiben im selben Channel). Kein Code übernommen.

## Build-Abhängigkeiten (nicht im Repository enthalten)

- TeamSpeak 3 Client Plugin SDK – https://github.com/TeamSpeak-Systems/ts3client-pluginsdk
  (© TeamSpeak Systems GmbH, wird beim Build heruntergeladen)
- gmod-module-base – https://github.com/Facepunch/gmod-module-base
  (© Facepunch Studios, wird beim Build heruntergeladen)

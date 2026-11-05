--- @ignore
-- Traitor Voice – settings page in the TTT2 F1 menu (Addons > Traitor Voice)

CLGAMEMODESUBMENU.base = "base_gamemodesubmenu"
CLGAMEMODESUBMENU.title = "Traitor Voice"

function CLGAMEMODESUBMENU:Populate(parent)
    local TV = TraitorVoice
    local st = (TV and TV.State and TV.State.status) or {}

    local status = vgui.CreateTTT2Form(parent, "Status")
    local function line(ok, text)
        status:MakeHelp({ label = (ok and "[OK]  " or "[FEHLT]  ") .. text })
    end
    line(st.moduleLoaded, "Modul geladen (Installer ausgeführt)")
    line(st.pluginRunning, "TeamSpeak 3 läuft, Plugin aktiv")
    line(st.connected, "Mit TeamSpeak-Server verbunden")
    line(st.ok, st.ok and "Alles bereit" or tostring(st.problem or "Status unbekannt"))
    status:MakeHelp({ label = "TeamSpeak-Server: " .. tostring(TV and TV.Config.teamspeak.address or "?") })

    local volume = vgui.CreateTTT2Form(parent, "Lautstärke")
    volume:MakeSlider({ label = "Stimmen gesamt", convar = "traitorvoice_master_volume", min = 0, max = 2, decimal = 2 })
    volume:MakeSlider({ label = "Funk", convar = "traitorvoice_radio_volume", min = 0, max = 2, decimal = 2 })
    volume:MakeSlider({ label = "Funk-Effekt", convar = "traitorvoice_radio_effect", min = 0, max = 1, decimal = 2 })

    local speech = vgui.CreateTTT2Form(parent, "Sprechen")
    speech:MakeCheckBox({ label = "Sprachaktivierung statt Push-to-Talk (Nahbereich)", convar = "traitorvoice_voice_activation" })
    speech:MakeCheckBox({ label = "HUD anzeigen", convar = "traitorvoice_hud" })
    speech:MakeHelp({ label = "Tasten: F1 > Tastenbelegung > Traitor Voice. Mikrofon, Ausgabegerät und Rauschfilter stellst du in TeamSpeak ein (Extras > Optionen > Aufnahme / Wiedergabe)." })
end

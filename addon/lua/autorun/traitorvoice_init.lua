-- Traitor Voice – positional voice for TTT2 via TeamSpeak 3
-- https://github.com/KarateWiesel/traitor-voice (MIT). Inspired by Gspeak and ACRE 2.

TraitorVoice = TraitorVoice or {}

local files = {
    shared = { "traitorvoice/sh_shared.lua" },
    server = { "traitorvoice/sv_config.lua", "traitorvoice/sv_main.lua" },
    client = { "traitorvoice/cl_main.lua", "traitorvoice/cl_hud.lua" },
}

if SERVER then
    for _, f in ipairs(files.shared) do
        AddCSLuaFile(f)
        include(f)
    end
    for _, f in ipairs(files.client) do
        AddCSLuaFile(f)
    end
    -- F1 menu page (loaded on the client by TTT2 itself)
    AddCSLuaFile("terrortown/menus/gamemode/addons/traitorvoice.lua")
    for _, f in ipairs(files.server) do
        include(f)
    end
else
    for _, f in ipairs(files.shared) do
        include(f)
    end
    for _, f in ipairs(files.client) do
        include(f)
    end
end

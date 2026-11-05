-- Traitor Voice – server logic
-- Decides who hears whom (ACRE principle: everyone stays in one TS channel, the plugins of
-- living players mute the dead) and maps players to their TeamSpeak client IDs.

util.AddNetworkString("TraitorVoice_Hello")    -- client -> server: Lua is loaded, please send the config
util.AddNetworkString("TraitorVoice_Report")   -- client -> server: plugin status, TS client ID
util.AddNetworkString("TraitorVoice_Transmit") -- client -> server: talking mode + voice level
util.AddNetworkString("TraitorVoice_Roster")   -- server -> client: who to hear and how
util.AddNetworkString("TraitorVoice_Pos")      -- server -> client: positions of dormant speakers

local TV = TraitorVoice

-- The native GMod voice chat is replaced completely.
hook.Add("PlayerCanHearPlayersVoice", "TraitorVoice", function()
    return false, false
end)

-- Net messages sent in PlayerInitialSpawn can arrive before the client's Lua is loaded,
-- so the client asks for the config once it is ready.
net.Receive("TraitorVoice_Hello", function(_, ply)
    local now = CurTime()
    if (ply.tvLastHello or 0) > now - 2 then return end
    ply.tvLastHello = now
    TV.SendConfig(ply)
end)

---------------------------------------------------------------------------------------------
-- Reports from clients
---------------------------------------------------------------------------------------------

net.Receive("TraitorVoice_Report", function(_, ply)
    local now = CurTime()
    if (ply.tvLastReport or 0) > now - 0.5 then return end
    ply.tvLastReport = now

    local r = {
        moduleLoaded = net.ReadBool(),
        pluginRunning = net.ReadBool(),
        connected = net.ReadBool(),
        tsId = net.ReadUInt(16),
        serverUid = string.sub(net.ReadString(), 1, 64),
        pluginVersion = net.ReadUInt(16),
        ok = net.ReadBool(),
    }
    if not (r.pluginRunning and r.connected) then
        r.tsId = nil
    end
    ply.tvReport = r
    ply:SetNW2Bool("TraitorVoice_OK", r.ok)
end)

net.Receive("TraitorVoice_Transmit", function(_, ply)
    local mode = net.ReadUInt(2)
    local level = TV.ClampLevel(net.ReadUInt(4))
    if mode == TV.TX_RADIO then
        local canRadio = TV.Config.radio.enabled and TV.IsAlive(ply)
        if not canRadio then mode = TV.TX_PROXIMITY end
    end
    ply.tvTx = mode
    ply.tvLevel = level
    TV.MarkRosterDirty()
end)

---------------------------------------------------------------------------------------------
-- Roster: for every listener, how each speaker is heard
---------------------------------------------------------------------------------------------

local function hearMode(listener, speaker)
    local cfg = TV.Config
    if TV.IsPostRound() and not cfg.postround_proximity then
        return TV.HEAR_DIRECT
    end
    if not TV.IsRoundActive() then
        return TV.HEAR_PROXIMITY -- waiting / preparing: everyone is together
    end

    local listenerAlive = TV.IsAlive(listener)
    local speakerAlive = TV.IsAlive(speaker)

    if listenerAlive then
        if speakerAlive then return TV.HEAR_PROXIMITY end
        return TV.HEAR_MUTED -- living players never hear the dead
    end
    -- listener is dead / spectating
    if not speakerAlive then return TV.HEAR_DIRECT end
    if cfg.dead.hear_alive then return TV.HEAR_PROXIMITY end
    return TV.HEAR_MUTED
end

local function sameTeamspeak(a, b)
    local ra, rb = a.tvReport, b.tvReport
    return ra and rb and ra.tsId and rb.tsId and ra.serverUid == rb.serverUid
end

local function sendRoster(listener)
    local entries = {}
    for _, speaker in ipairs(player.GetHumans()) do
        if speaker ~= listener and sameTeamspeak(listener, speaker) then
            local mode = hearMode(listener, speaker)
            local radio = speaker.tvTx == TV.TX_RADIO and TV.IsAlive(speaker)
            if radio and not TV.IsAlive(listener) and not TV.Config.dead.hear_radio then
                radio = false
            end
            entries[#entries + 1] = {
                ent = speaker:EntIndex(),
                ts = speaker.tvReport.tsId,
                mode = mode,
                radio = radio,
                level = speaker.tvLevel or TV.Config.default_level,
            }
        end
    end

    net.Start("TraitorVoice_Roster")
    net.WriteUInt(#entries, 8)
    for _, e in ipairs(entries) do
        net.WriteUInt(e.ent, 8)
        net.WriteUInt(e.ts, 16)
        net.WriteUInt(e.mode, 2)
        net.WriteBool(e.radio)
        net.WriteUInt(e.level, 4)
    end
    net.Send(listener)
end

local rosterDirty = true
function TV.MarkRosterDirty()
    rosterDirty = true
end

local nextFullRoster = 0
hook.Add("Think", "TraitorVoice_Roster", function()
    local now = CurTime()
    if not rosterDirty and now < nextFullRoster then return end
    rosterDirty = false
    nextFullRoster = now + 0.5
    for _, ply in ipairs(player.GetHumans()) do
        sendRoster(ply)
    end
end)

for _, h in ipairs({ "PlayerDeath", "PlayerSpawn", "PlayerSilentDeath", "PlayerDisconnected",
                     "TTTBeginRound", "TTTEndRound", "TTTPrepareRound" }) do
    hook.Add(h, "TraitorVoice_Dirty", function() TV.MarkRosterDirty() end)
end

hook.Add("TTTPrepareRound", "TraitorVoice_ResetTx", function()
    for _, ply in ipairs(player.GetAll()) do
        ply.tvLevel = TV.Config.default_level
    end
end)

---------------------------------------------------------------------------------------------
-- Positions: clients do not receive updates for players outside their PVS (dormant).
-- Send those positions, but only for speakers within hearing range of the listener.
---------------------------------------------------------------------------------------------

local function maxRangeUnits()
    local best = 0
    for _, lv in ipairs(TV.Config.voice_levels) do
        best = math.max(best, tonumber(lv.range_m) or 0)
    end
    return (best + 2) * TV.UNITS_PER_METER
end

local nextPos = 0
hook.Add("Think", "TraitorVoice_Pos", function()
    local now = CurTime()
    if now < nextPos then return end
    nextPos = now + 0.1

    local players = player.GetHumans()
    local range = maxRangeUnits()
    local rangeSqr = range * range
    for _, listener in ipairs(players) do
        local origin = listener:EyePos()
        local list = {}
        for _, speaker in ipairs(players) do
            if speaker ~= listener and TV.IsAlive(speaker) then
                local pos = speaker:EyePos()
                if pos:DistToSqr(origin) <= rangeSqr then
                    list[#list + 1] = { ent = speaker:EntIndex(), pos = pos }
                end
            end
        end
        if #list > 0 then
            net.Start("TraitorVoice_Pos", true) -- unreliable: the next update follows in 100 ms
            net.WriteUInt(#list, 8)
            for _, e in ipairs(list) do
                net.WriteUInt(e.ent, 8)
                net.WriteVector(e.pos)
            end
            net.Send(listener)
        end
    end
end)

---------------------------------------------------------------------------------------------
-- Admin helpers
---------------------------------------------------------------------------------------------

concommand.Add("traitorvoice_status", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    local function out(s)
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, s) else print(s) end
    end
    out("[Traitor Voice] " .. TV.VERSION .. " – Spieler:")
    for _, p in ipairs(player.GetHumans()) do
        local r = p.tvReport
        if r then
            out(string.format("  %-24s ok=%s modul=%s plugin=%s ts-id=%s server-uid=%s",
                p:Nick(), tostring(r.ok), tostring(r.moduleLoaded), tostring(r.pluginRunning),
                tostring(r.tsId or "-"), r.serverUid ~= "" and r.serverUid or "-"))
        else
            out(string.format("  %-24s noch keine Meldung", p:Nick()))
        end
    end
end)

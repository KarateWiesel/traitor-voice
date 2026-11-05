-- Traitor Voice – client logic
-- Computes, for every speaker, gain / position / occlusion and hands it to the
-- gmcl_traitorvoice module, which passes it to the TeamSpeak 3 plugin via shared memory.

local TV = TraitorVoice
local UPM = TV.UNITS_PER_METER

TV.State = TV.State or {
    level = nil,
    pttDown = false,
    radioDown = false,
    lastSentTx = -1,
    lastSentLevel = -1,
    roster = {},       -- [entIndex] = { ts, mode, radio, level }
    serverPos = {},    -- [entIndex] = { pos, time }
    status = {},
    configReceived = false,
    joinTime = CurTime(),
    occlusion = {},    -- [entIndex] = { value, nextCheck }
}
local S = TV.State

local cvMaster = CreateClientConVar("traitorvoice_master_volume", "1", true, false, "Lautstärke aller Stimmen", 0, 2)
local cvRadio = CreateClientConVar("traitorvoice_radio_volume", "1", true, false, "Lautstärke des Funks", 0, 2)
local cvRadioFx = CreateClientConVar("traitorvoice_radio_effect", "0.6", true, false, "Stärke des Funk-Effekts", 0, 1)
local cvVA = CreateClientConVar("traitorvoice_voice_activation", "0", true, false,
    "Sprachaktivierung (TeamSpeak) statt Push-to-Talk für den Nahbereich", 0, 1)
CreateClientConVar("traitorvoice_hud", "1", true, false, "HUD von Traitor Voice anzeigen", 0, 1)

---------------------------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------------------------

S.moduleLoaded = false
if system.IsWindows() then
    local ok, err = pcall(require, "traitorvoice")
    S.moduleLoaded = ok and istable(traitorvoice) and traitorvoice.Update ~= nil
    if not S.moduleLoaded then
        print("[Traitor Voice] Modul nicht geladen: " .. tostring(err))
    end
end

---------------------------------------------------------------------------------------------
-- Config from the server
---------------------------------------------------------------------------------------------

net.Receive("TraitorVoice_Config", function()
    TV.Config = net.ReadTable()
    S.configReceived = true
    if not S.level then S.level = TV.Config.default_level end
    S.level = TV.ClampLevel(S.level)
end)

hook.Add("TTTPrepareRound", "TraitorVoice_ResetLevel", function()
    S.level = TV.Config.default_level
end)

---------------------------------------------------------------------------------------------
-- Transmit mode
---------------------------------------------------------------------------------------------

function TV.GetTransmit()
    local ply = LocalPlayer()
    if S.radioDown and TV.Config.radio.enabled and TV.IsAlive(ply) then
        return TV.TX_RADIO
    end
    if S.pttDown or cvVA:GetBool() then
        return TV.TX_PROXIMITY
    end
    return TV.TX_NONE
end

local function sendTransmit()
    local tx = TV.GetTransmit()
    local level = S.level or TV.Config.default_level
    if tx == S.lastSentTx and level == S.lastSentLevel then return end
    S.lastSentTx = tx
    S.lastSentLevel = level
    net.Start("TraitorVoice_Transmit")
    net.WriteUInt(tx, 2)
    net.WriteUInt(level, 4)
    net.SendToServer()
end

function TV.ChangeLevel(delta)
    S.level = TV.ClampLevel((S.level or TV.Config.default_level) + delta)
    sendTransmit()
    surface.PlaySound("buttons/lightswitch2.wav")
end

---------------------------------------------------------------------------------------------
-- Key bindings (TTT2 bind system; console commands as fallback)
---------------------------------------------------------------------------------------------

local function registerBinds()
    local category = "Traitor Voice"
    if bind and bind.Register then
        bind.Register("traitorvoice_talk",
            function() S.pttDown = true; sendTransmit() return true end,
            function() S.pttDown = false; sendTransmit() return true end,
            category, "Sprechen (Nahbereich)", KEY_V)
        bind.Register("traitorvoice_radio",
            function() S.radioDown = true; sendTransmit(); surface.PlaySound("buttons/blip1.wav") return true end,
            function() S.radioDown = false; sendTransmit() return true end,
            category, "Funken", KEY_CAPSLOCK)
        bind.Register("traitorvoice_level_up",
            function() TV.ChangeLevel(1) return true end, nil,
            category, "Lauter sprechen (Stufe hoch)", KEY_PAGEUP)
        bind.Register("traitorvoice_level_down",
            function() TV.ChangeLevel(-1) return true end, nil,
            category, "Leiser sprechen (Stufe runter)", KEY_PAGEDOWN)
    end
end
hook.Add("InitPostEntity", "TraitorVoice_Binds", registerBinds)
if IsValid(LocalPlayer()) then registerBinds() end

concommand.Add("+traitorvoice_talk", function() S.pttDown = true; sendTransmit() end)
concommand.Add("-traitorvoice_talk", function() S.pttDown = false; sendTransmit() end)
concommand.Add("+traitorvoice_radio", function() S.radioDown = true; sendTransmit() end)
concommand.Add("-traitorvoice_radio", function() S.radioDown = false; sendTransmit() end)
concommand.Add("traitorvoice_level_up", function() TV.ChangeLevel(1) end)
concommand.Add("traitorvoice_level_down", function() TV.ChangeLevel(-1) end)

---------------------------------------------------------------------------------------------
-- Roster and positions from the server
---------------------------------------------------------------------------------------------

net.Receive("TraitorVoice_Roster", function()
    local roster = {}
    for _ = 1, net.ReadUInt(8) do
        local ent = net.ReadUInt(8)
        roster[ent] = {
            ts = net.ReadUInt(16),
            mode = net.ReadUInt(2),
            radio = net.ReadBool(),
            level = net.ReadUInt(4),
        }
    end
    S.roster = roster
end)

net.Receive("TraitorVoice_Pos", function()
    local now = CurTime()
    for _ = 1, net.ReadUInt(8) do
        local ent = net.ReadUInt(8)
        S.serverPos[ent] = { pos = net.ReadVector(), time = now }
    end
end)

local function speakerPos(ply, entIndex)
    if IsValid(ply) and not ply:IsDormant() then
        return ply:EyePos()
    end
    local p = S.serverPos[entIndex]
    if p and CurTime() - p.time < 1 then
        return p.pos
    end
    return nil
end

---------------------------------------------------------------------------------------------
-- Listener (own head, or the spectated player / free camera when dead)
---------------------------------------------------------------------------------------------

local function listenerView()
    local ply = LocalPlayer()
    if not TV.IsAlive(ply) then
        local target = ply:GetObserverTarget()
        if IsValid(target) and target:IsPlayer() and ply:GetObserverMode() == OBS_MODE_IN_EYE then
            return target:EyePos(), target:EyeAngles(), target
        end
    end
    return ply:EyePos(), ply:EyeAngles(), nil
end

---------------------------------------------------------------------------------------------
-- Occlusion: count walls between listener and speaker (cached, 10 per second per speaker)
---------------------------------------------------------------------------------------------

local function countWalls(from, to, filter, maxWalls)
    local dir = to - from
    local len = dir:Length()
    if len < 1 then return 0 end
    dir:Normalize()
    local walls = 0
    local start = from
    for _ = 1, maxWalls + 1 do
        local tr = util.TraceLine({ start = start, endpos = to, filter = filter, mask = MASK_SOLID })
        if tr.StartSolid then
            -- we are inside a wall: jump to where the trace left it
            local leave = tr.FractionLeftSolid or 1
            if leave >= 1 then break end
            start = LerpVector(leave, start, to) + dir * 2
        elseif tr.Hit then
            walls = walls + 1
            if walls >= maxWalls then break end
            start = tr.HitPos + dir * 2
        else
            break
        end
    end
    return walls
end

local function occlusionFor(entIndex, from, to, filter)
    local cfg = TV.Config.occlusion
    if not cfg.enabled then return 0 end
    local now = CurTime()
    local c = S.occlusion[entIndex]
    if c and now < c.nextCheck then return c.value end
    local maxWalls = cfg.max_walls
    local walls = countWalls(from, to, filter, maxWalls)
    local value = math.Clamp(walls / maxWalls, 0, 1)
    S.occlusion[entIndex] = { value = value, nextCheck = now + 0.1 }
    return value
end

---------------------------------------------------------------------------------------------
-- Per-frame update to the module
---------------------------------------------------------------------------------------------

local clientsBuffer = {}

local function buildClients()
    local listenerPos, listenerAng, viewTarget = listenerView()
    local right, up, fwd = listenerAng:Right(), listenerAng:Up(), listenerAng:Forward()

    local n = 0
    for entIndex, r in pairs(S.roster) do
        local ply = Entity(entIndex)
        local entry
        if r.mode == TV.HEAR_MUTED then
            entry = { ts = r.ts, gain = 0, x = 0, y = 0, z = 0, occ = 0, flags = TV.CF_MUTED }
        elseif r.mode == TV.HEAR_DIRECT then
            entry = { ts = r.ts, gain = 1, x = 0, y = 0, z = 0, occ = 0, flags = TV.CF_NO3D }
        else
            local pos = speakerPos(ply, entIndex)
            local gain, x, y, z, occ = 0, 0, 0, 0, 0
            if pos then
                local d = pos - listenerPos
                local distM = d:Length() / UPM
                gain = TV.DistanceGain(distM, r.level)
                if gain > 0 then
                    local traceFilter = { LocalPlayer() }
                    if IsValid(viewTarget) then traceFilter[#traceFilter + 1] = viewTarget end
                    if IsValid(ply) then traceFilter[#traceFilter + 1] = ply end
                    occ = occlusionFor(entIndex, listenerPos, pos, traceFilter)
                    if occ >= 1 then
                        gain = 0
                    else
                        gain = gain * (1 - 0.4 * occ)
                    end
                end
                x, y, z = d:Dot(right) / UPM, d:Dot(up) / UPM, d:Dot(fwd) / UPM
            end

            if r.radio and gain < 0.3 then
                -- far away (or behind walls): heard over the radio instead
                entry = { ts = r.ts, gain = 1, x = 0, y = 0, z = 0, occ = 0, flags = TV.CF_RADIO }
            else
                entry = { ts = r.ts, gain = gain, x = x, y = y, z = z, occ = occ, flags = 0 }
            end
        end
        n = n + 1
        clientsBuffer[n] = entry
    end
    for i = n + 1, #clientsBuffer do clientsBuffer[i] = nil end
    return clientsBuffer
end

local function isActive()
    return S.moduleLoaded and S.configReceived and IsValid(LocalPlayer())
end

local updateState = {}
hook.Add("Think", "TraitorVoice_Update", function()
    if not isActive() then return end
    updateState.active = true
    updateState.voiceActivation = cvVA:GetBool()
    updateState.muteUnknown = true
    updateState.transmit = TV.GetTransmit()
    updateState.masterVolume = cvMaster:GetFloat()
    updateState.radioVolume = cvRadio:GetFloat()
    updateState.radioEffect = cvRadioFx:GetFloat()
    updateState.serverUid = TV.Config.teamspeak.server_uid or ""
    updateState.clients = buildClients()
    traitorvoice.Update(updateState)
end)

hook.Add("ShutDown", "TraitorVoice_Release", function()
    if S.moduleLoaded and traitorvoice.Release then traitorvoice.Release() end
end)

---------------------------------------------------------------------------------------------
-- Status (for the HUD, the blocking overlay and the server)
---------------------------------------------------------------------------------------------

function TV.ComputeStatus()
    local st = { windows = system.IsWindows(), moduleLoaded = S.moduleLoaded }
    if S.moduleLoaded then
        local p = traitorvoice.GetStatus()
        st.pluginRunning = p.pluginRunning
        st.protocolOk = p.protocolOk
        st.connected = p.connected
        st.active = p.active
        st.tsId = p.clientId
        st.serverUid = p.serverUid or ""
        st.pluginVersion = p.pluginVersion or 0
        st.micLevel = p.micLevel or 0
        st.talking = p.talking or {}
    end

    local wantUid = TV.Config.teamspeak.server_uid or ""
    local minVersion = TV.VersionNumber(TV.Config.min_plugin_version)
    if not st.windows then
        st.problem = "Traitor Voice unterstützt bisher nur Windows."
    elseif not st.moduleLoaded then
        st.problem = "Das Traitor-Voice-Modul fehlt. Bitte den Installer ausführen."
    elseif not st.pluginRunning then
        st.problem = "TeamSpeak 3 läuft nicht oder das Traitor-Voice-Plugin ist deaktiviert (TeamSpeak > Extras > Optionen > Addons)."
    elseif not st.protocolOk or st.pluginVersion < minVersion then
        st.problem = "Plugin/Modul ist veraltet. Bitte die neueste Version installieren."
    elseif not st.connected then
        st.problem = "Du bist mit keinem TeamSpeak-Server verbunden."
    elseif wantUid ~= "" and st.serverUid ~= wantUid then
        st.problem = "Du bist mit dem falschen TeamSpeak-Server verbunden."
    end
    st.ok = st.problem == nil
    return st
end

local nextReport = 0
local lastOk = nil
hook.Add("Think", "TraitorVoice_Status", function()
    local now = CurTime()
    if now < nextReport then return end
    nextReport = now + 1
    if not S.configReceived then return end

    local st = TV.ComputeStatus()
    S.status = st

    -- report every 2 s or when the result changes
    if lastOk ~= st.ok or (S.nextReportSend or 0) < now then
        lastOk = st.ok
        S.nextReportSend = now + 2
        net.Start("TraitorVoice_Report")
        net.WriteBool(st.moduleLoaded and true or false)
        net.WriteBool(st.pluginRunning and true or false)
        net.WriteBool(st.connected and true or false)
        net.WriteUInt(math.Clamp(tonumber(st.tsId) or 0, 0, 65535), 16)
        net.WriteString(st.serverUid or "")
        net.WriteUInt(math.Clamp(tonumber(st.pluginVersion) or 0, 0, 65535), 16)
        net.WriteBool(st.ok)
        net.SendToServer()
    end
    sendTransmit()
end)

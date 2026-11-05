-- Traitor Voice – shared definitions

TraitorVoice.VERSION = "0.1.0"
TraitorVoice.PROTOCOL = 1
TraitorVoice.UNITS_PER_METER = 52.5
TraitorVoice.DOWNLOAD_URL = "https://github.com/KarateWiesel/traitor-voice/releases"

-- Transmit modes (must match shared/traitorvoice_protocol.h)
TraitorVoice.TX_NONE = 0
TraitorVoice.TX_PROXIMITY = 1
TraitorVoice.TX_RADIO = 2

-- Client flags (must match shared/traitorvoice_protocol.h)
TraitorVoice.CF_MUTED = 1
TraitorVoice.CF_RADIO = 2
TraitorVoice.CF_NO3D = 4

-- How a listener hears a speaker (decided by the server, sent in the roster)
TraitorVoice.HEAR_PROXIMITY = 0 -- positional, distance and walls
TraitorVoice.HEAR_DIRECT = 1    -- full volume, no position (dead <-> dead, post round)
TraitorVoice.HEAR_MUTED = 2     -- not at all (dead speaker while listener is alive)

-- Defaults; the server overrides them with garrysmod/data/traitorvoice/config.json
TraitorVoice.DefaultConfig = {
    teamspeak = {
        address = "ts.example.com:9987",
        server_uid = "",
    },
    voice_levels = {
        { name = "Flüstern", range_m = 2 },
        { name = "Leise", range_m = 6 },
        { name = "Normal", range_m = 12 },
        { name = "Schreien", range_m = 30 },
    },
    default_level = 3,
    full_volume_share = 0.25,
    occlusion = { enabled = true, max_walls = 3 },
    radio = { enabled = true },
    dead = { hear_alive = true, hear_radio = true },
    postround_proximity = false,
    require_teamspeak = { blocking_overlay = true, grace_seconds = 20 },
    min_plugin_version = "0.1.0",
}

TraitorVoice.Config = table.Copy(TraitorVoice.DefaultConfig)

-- "0.1.0" -> 100
function TraitorVoice.VersionNumber(str)
    local a, b, c = string.match(tostring(str or ""), "^(%d+)%.(%d+)%.(%d+)")
    if not a then return 0 end
    return tonumber(a) * 10000 + tonumber(b) * 100 + tonumber(c)
end

function TraitorVoice.LevelCount()
    return #TraitorVoice.Config.voice_levels
end

function TraitorVoice.ClampLevel(level)
    return math.Clamp(math.floor(tonumber(level) or 1), 1, math.max(1, TraitorVoice.LevelCount()))
end

-- Distance gain 0..1 for a speaker at distance (metres) talking at the given level.
function TraitorVoice.DistanceGain(distM, level)
    local cfg = TraitorVoice.Config
    local lv = cfg.voice_levels[TraitorVoice.ClampLevel(level)]
    if not lv then return 0 end
    local range = math.max(0.1, tonumber(lv.range_m) or 1)
    local full = range * math.Clamp(tonumber(cfg.full_volume_share) or 0.25, 0, 0.95)
    if distM <= full then return 1 end
    if distM >= range then return 0 end
    local t = (distM - full) / (range - full)
    return (1 - t) * (1 - t)
end

-- TTT2 round helper (works without TTT2, treats everything as an active round)
function TraitorVoice.RoundState()
    if isfunction(GetRoundState) then
        return GetRoundState()
    end
    return 3
end

function TraitorVoice.IsRoundActive()
    return ROUND_ACTIVE == nil or TraitorVoice.RoundState() == ROUND_ACTIVE
end

function TraitorVoice.IsPostRound()
    return ROUND_POST ~= nil and TraitorVoice.RoundState() == ROUND_POST
end

-- Alive in the TTT sense (not a spectator, not dead)
function TraitorVoice.IsAlive(ply)
    if not IsValid(ply) then return false end
    if ply.IsTerror then return ply:IsTerror() end
    return ply:Alive()
end

-- Traitor Voice – server config: garrysmod/data/traitorvoice/config.json
-- Edit the file, then run "traitorvoice_reload" in the server console. No restart needed.

util.AddNetworkString("TraitorVoice_Config")

local DIR = "traitorvoice"
local PATH = DIR .. "/config.json"

-- Fill missing keys from defaults, keep everything the admin set.
local function merge(defaults, values)
    local out = table.Copy(defaults)
    if not istable(values) then return out end
    for k, v in pairs(values) do
        if istable(v) and istable(out[k]) and k ~= "voice_levels" then
            out[k] = merge(out[k], v)
        else
            out[k] = v
        end
    end
    return out
end

local function validate(cfg)
    local levels = {}
    if istable(cfg.voice_levels) then
        for _, lv in ipairs(cfg.voice_levels) do
            if istable(lv) and tonumber(lv.range_m) then
                levels[#levels + 1] = { name = tostring(lv.name or ("Stufe " .. (#levels + 1))), range_m = tonumber(lv.range_m) }
            end
        end
    end
    if #levels == 0 then
        levels = table.Copy(TraitorVoice.DefaultConfig.voice_levels)
    end
    cfg.voice_levels = levels
    cfg.default_level = math.Clamp(math.floor(tonumber(cfg.default_level) or 3), 1, #levels)
    cfg.full_volume_share = math.Clamp(tonumber(cfg.full_volume_share) or 0.25, 0, 0.95)
    cfg.occlusion.max_walls = math.max(1, math.floor(tonumber(cfg.occlusion.max_walls) or 3))
    cfg.require_teamspeak.grace_seconds = math.max(0, tonumber(cfg.require_teamspeak.grace_seconds) or 20)
    cfg.teamspeak.address = tostring(cfg.teamspeak.address or "")
    cfg.teamspeak.server_uid = tostring(cfg.teamspeak.server_uid or "")
    return cfg
end

function TraitorVoice.SaveDefaultConfig()
    file.CreateDir(DIR)
    file.Write(PATH, util.TableToJSON(TraitorVoice.DefaultConfig, true))
end

function TraitorVoice.LoadConfig()
    if not file.Exists(PATH, "DATA") then
        TraitorVoice.SaveDefaultConfig()
        print("[Traitor Voice] Config angelegt: garrysmod/data/" .. PATH)
    end
    local raw = file.Read(PATH, "DATA")
    local parsed = raw and util.JSONToTable(raw) or nil
    if not parsed then
        print("[Traitor Voice] FEHLER: config.json ist kein gültiges JSON – Standardwerte werden benutzt.")
    end
    TraitorVoice.Config = validate(merge(TraitorVoice.DefaultConfig, parsed))
end

-- Clients get the whole config (it contains nothing secret).
function TraitorVoice.SendConfig(target)
    net.Start("TraitorVoice_Config")
    net.WriteTable(TraitorVoice.Config)
    if target then
        net.Send(target)
    else
        net.Broadcast()
    end
end

concommand.Add("traitorvoice_reload", function(ply)
    if IsValid(ply) and not ply:IsSuperAdmin() then return end
    TraitorVoice.LoadConfig()
    TraitorVoice.SendConfig()
    local msg = "[Traitor Voice] Config neu geladen."
    if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) end
    print(msg)
end)

TraitorVoice.LoadConfig()

-- Traitor Voice – HUD and the blocking overlay shown when TeamSpeak is not ready

local TV = TraitorVoice
local S = TV.State

surface.CreateFont("TraitorVoice_Big", { font = "Roboto", size = 34, weight = 800 })
surface.CreateFont("TraitorVoice_Text", { font = "Roboto", size = 20, weight = 500 })
surface.CreateFont("TraitorVoice_Small", { font = "Roboto", size = 16, weight = 500 })

---------------------------------------------------------------------------------------------
-- Small HUD: voice level, radio, microphone, who is talking
---------------------------------------------------------------------------------------------

local function playerByTsId(tsId)
    for entIndex, r in pairs(S.roster) do
        if r.ts == tsId then
            local ply = Entity(entIndex)
            if IsValid(ply) then return ply, r end
        end
    end
    return nil
end

hook.Add("HUDPaint", "TraitorVoice_HUD", function()
    if not S.configReceived or not GetConVar("traitorvoice_hud"):GetBool() then return end
    local st = S.status or {}
    local x, y = 20, ScrH() * 0.45

    local level = TV.Config.voice_levels[TV.ClampLevel(S.level or TV.Config.default_level)]
    local tx = TV.GetTransmit and TV.GetTransmit() or 0

    local label = level and (level.name .. " (" .. level.range_m .. " m)") or "?"
    local color = Color(220, 220, 220)
    if tx == TV.TX_RADIO then
        label = "FUNK"
        color = Color(255, 190, 60)
    elseif tx == TV.TX_PROXIMITY then
        color = Color(120, 230, 120)
    end

    draw.RoundedBox(6, x - 8, y - 6, 210, 54, Color(0, 0, 0, 160))
    draw.SimpleText(label, "TraitorVoice_Text", x, y, color)
    -- microphone level bar
    local mic = math.Clamp(st.micLevel or 0, 0, 1)
    surface.SetDrawColor(60, 60, 60, 200)
    surface.DrawRect(x, y + 28, 190, 8)
    surface.SetDrawColor(color.r, color.g, color.b, 230)
    surface.DrawRect(x, y + 28, 190 * mic, 8)

    -- talking players (only those this player is allowed to hear)
    local ty = y + 60
    for _, tsId in ipairs(st.talking or {}) do
        local ply, r = playerByTsId(tsId)
        if ply and r and r.mode ~= TV.HEAR_MUTED then
            local name = ply:Nick() .. (r.radio and "  [Funk]" or "")
            draw.SimpleText(name, "TraitorVoice_Small", x, ty, r.radio and Color(255, 190, 60) or Color(255, 255, 255))
            ty = ty + 18
        end
    end
end)

---------------------------------------------------------------------------------------------
-- Blocking overlay: covers the whole screen and grabs the mouse until everything is green
---------------------------------------------------------------------------------------------

local overlay

local function closeOverlay()
    if IsValid(overlay) then overlay:Remove() end
    overlay = nil
end

local function openOverlay()
    if IsValid(overlay) then return end
    overlay = vgui.Create("DPanel")
    overlay:SetSize(ScrW(), ScrH())
    overlay:SetPos(0, 0)
    overlay:MakePopup()
    overlay:SetKeyboardInputEnabled(false)
    overlay.Paint = function(_, w, h)
        surface.SetDrawColor(10, 10, 14, 250)
        surface.DrawRect(0, 0, w, h)
        local st = S.status or {}
        draw.SimpleText("Traitor Voice: TeamSpeak ist nicht bereit", "TraitorVoice_Big", w / 2, h * 0.3,
            Color(255, 90, 90), TEXT_ALIGN_CENTER)
        draw.SimpleText(st.problem or "Status wird geprüft …", "TraitorVoice_Text", w / 2, h * 0.3 + 60,
            Color(255, 255, 255), TEXT_ALIGN_CENTER)
        draw.SimpleText("TeamSpeak-Server: " .. tostring(TV.Config.teamspeak.address), "TraitorVoice_Text",
            w / 2, h * 0.3 + 100, Color(200, 200, 200), TEXT_ALIGN_CENTER)
        draw.SimpleText("Ohne TeamSpeak kannst du auf diesem Server nicht mitspielen. Das Fenster verschwindet automatisch.",
            "TraitorVoice_Small", w / 2, h * 0.3 + 140, Color(160, 160, 160), TEXT_ALIGN_CENTER)
    end

    local copy = vgui.Create("DButton", overlay)
    copy:SetText("TS-Adresse kopieren")
    copy:SetSize(240, 40)
    copy:SetPos(ScrW() / 2 - 250, ScrH() * 0.3 + 190)
    copy.DoClick = function()
        SetClipboardText(tostring(TV.Config.teamspeak.address))
        surface.PlaySound("buttons/button14.wav")
    end

    local dl = vgui.Create("DButton", overlay)
    dl:SetText("Installer herunterladen")
    dl:SetSize(240, 40)
    dl:SetPos(ScrW() / 2 + 10, ScrH() * 0.3 + 190)
    dl.DoClick = function() gui.OpenURL(TV.DOWNLOAD_URL) end
end

hook.Add("Think", "TraitorVoice_Overlay", function()
    if not S.configReceived then return end
    local req = TV.Config.require_teamspeak
    local st = S.status
    local grace = CurTime() - (S.joinTime or 0) < (req.grace_seconds or 20)
    if req.blocking_overlay and st and st.ok == false and not grace then
        openOverlay()
    elseif overlay then
        closeOverlay()
    end
end)

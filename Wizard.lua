-- Watchdog: wizard de primeiro contato (boas-vindas em 4 passos).
local _, WD = ...
local L = WD.L

local W            -- janela
local STEPS = 4

local function Kit() return WD.UIKit end

local function ClassLine()
    local ok, cname, cfile = pcall(UnitClass, "player")
    if not (ok and cname and cfile) then return nil end
    local col = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cfile]
    local hex = col and string.format("%02x%02x%02x", math.floor(col.r * 255), math.floor(col.g * 255), math.floor(col.b * 255)) or "ffffff"
    return string.format(L.w_class, "|cff" .. hex .. cname .. "|r")
end

local function Build(step)
    local K = Kit()
    if not K then return nil end
    local C, Flat, FS, MakeChip, BT, MEDIA = K.C, K.Flat, K.FS, K.MakeChip, K.BT, K.MEDIA
    local cfg = WD:Cfg()

    local f = CreateFrame("Frame", "WatchdogWizardFrame", UIParent, BT)
    f:SetSize(560, 400)
    f:SetPoint("CENTER", 0, 20)
    Flat(f, C.bg, C.border, 0.98)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f.step = step or 1

    local mark = f:CreateTexture(nil, "BACKGROUND")
    mark:SetTexture(MEDIA .. "emblem")
    mark:SetSize(170, 170)
    mark:SetPoint("BOTTOMRIGHT", -14, 40)
    mark:SetAlpha(0.07)

    local wm = f:CreateTexture(nil, "ARTWORK")
    wm:SetTexture(MEDIA .. "wordmark")
    wm:SetSize(136, 17)
    wm:SetPoint("TOPLEFT", 24, -22)

    local stepFS = FS(f, 11, C.dim, "RIGHT")
    stepFS:SetPoint("TOPRIGHT", -24, -24)

    local title = FS(f, 22, C.text, "LEFT", "")
    title:SetPoint("TOPLEFT", 24, -58)

    local body = CreateFrame("Frame", nil, f)
    body:SetPoint("TOPLEFT", 24, -100)
    body:SetPoint("BOTTOMRIGHT", -24, 60)

    local function Text(parent, size, color, y, str, width)
        local fs = FS(parent, size, color, "LEFT")
        fs:SetPoint("TOPLEFT", 0, -y)
        fs:SetWidth(width or 510)
        fs:SetJustifyH("LEFT")
        fs:SetText(str)
        return fs
    end

    local pages = {}
    -- 1) boas-vindas + idioma
    do
        local p = CreateFrame("Frame", nil, body); p:SetAllPoints(); pages[1] = p
        Text(p, 13, C.text, 0, L.w_body1)
        Text(p, 12, C.dim, 100, L.w_lang)
        local cur = WD.activeLocale
        local x = 0
        for _, lc in ipairs({ { "enUS", "English" }, { "ptBR", "Português" } }) do
            local b = MakeChip(p, lc[2], 110)
            b:SetPoint("TOPLEFT", x, -122)
            b:SetActive(cur == lc[1])
            b:SetScript("OnClick", function()
                WatchdogDB.locale = lc[1]
                WD:SetLocale(lc[1])
                local s = f.step
                f:Hide(); W = nil
                WD:ShowWizard(true, s)
            end)
            x = x + 118
        end
    end
    -- 2) o que rastreia
    do
        local p = CreateFrame("Frame", nil, body); p:SetAllPoints(); pages[2] = p
        local y = 0
        for _, k in ipairs({ "w_l_pve", "w_l_xp", "w_l_pvp", "w_l_hist", "w_l_black" }) do
            local dot = p:CreateTexture(nil, "ARTWORK")
            dot:SetSize(6, 6); dot:SetPoint("TOPLEFT", 0, -y - 5)
            dot:SetColorTexture(C.red[1], C.red[2], C.red[3], 1)
            local fs = FS(p, 13, C.text, "LEFT")
            fs:SetPoint("TOPLEFT", 16, -y); fs:SetWidth(494); fs:SetJustifyH("LEFT")
            fs:SetText(L[k])
            y = y + (k == "w_l_hist" and 48 or 30)
        end
    end
    -- 3) avisos (liga/desliga)
    do
        local p = CreateFrame("Frame", nil, body); p:SetAllPoints(); pages[3] = p
        Text(p, 12, C.dim, 0, L.w_body3)
        local items = {
            { "cfg_sound",     function() return cfg.sound end,        function(v) cfg.sound = v end },
            { "cfg_buffs_on",  function() return cfg.buff.on end,      function(v) cfg.buff.on = v end },
            { "cfg_repair_on", function() return cfg.repair.on end,    function(v) cfg.repair.on = v end },
            { "cfg_food_on",   function() return cfg.food.on end,      function(v) cfg.food.on = v end },
        }
        local y = 28
        for _, it in ipairs(items) do
            local lbl = FS(p, 13, C.text, "LEFT")
            lbl:SetPoint("TOPLEFT", 0, -y - 4); lbl:SetText(L[it[1]])
            local b = MakeChip(p, "", 60)
            b:SetPoint("TOPRIGHT", 0, -y)
            local function paint()
                local on = it[2]() and true or false
                b.text:SetText(on and L.w_on or L.w_off)
                b:SetActive(on)
            end
            b:SetScript("OnClick", function() it[3](not it[2]()); paint(); if WD.RefreshConfig then WD:RefreshConfig() end end)
            paint()
            y = y + 30
        end
        local cl = ClassLine()
        if cl then Text(p, 12, C.dim, y + 6, cl) end
    end
    -- 4) pronto
    do
        local p = CreateFrame("Frame", nil, body); p:SetAllPoints(); pages[4] = p
        local y = 0
        for _, k in ipairs({ "w_tip1", "w_tip2", "w_tip3", "w_tip4", "w_tip5" }) do
            local dot = p:CreateTexture(nil, "ARTWORK")
            dot:SetSize(6, 6); dot:SetPoint("TOPLEFT", 0, -y - 5)
            dot:SetColorTexture(C.green[1], C.green[2], C.green[3], 1)
            local fs = FS(p, 13, C.text, "LEFT")
            fs:SetPoint("TOPLEFT", 16, -y); fs:SetWidth(494); fs:SetJustifyH("LEFT")
            fs:SetText(L[k])
            y = y + ((k == "w_tip4") and 44 or 30)
        end
    end

    -- rodape
    local skip = MakeChip(f, L.w_skip, 80)
    skip:SetPoint("BOTTOMLEFT", 24, 20)
    local back = MakeChip(f, L.w_back, 90)
    back:SetPoint("BOTTOMRIGHT", -24 - 100, 20)
    local nxt = MakeChip(f, L.w_next, 120)
    nxt:SetPoint("BOTTOMRIGHT", -24, 20)

    local titles = { L.w_title1, L.w_title2, L.w_title3, L.w_title4 }
    local function Show(n)
        f.step = math.max(1, math.min(STEPS, n))
        for i, pg in ipairs(pages) do pg:SetShown(i == f.step) end
        title:SetText(titles[f.step])
        stepFS:SetText(string.format(L.w_step, f.step, STEPS))
        back:SetShown(f.step > 1)
        nxt.text:SetText(f.step == STEPS and L.w_finish or L.w_next)
        skip:SetShown(f.step < STEPS)
    end
    local function Close()
        WatchdogDB.wizardDone = true
        f:Hide()
    end
    back:SetScript("OnClick", function() Show(f.step - 1) end)
    nxt:SetScript("OnClick", function()
        if f.step == STEPS then Close(); if WD.Toggle then WD:Toggle() end else Show(f.step + 1) end
    end)
    skip:SetScript("OnClick", Close)
    nxt.text:SetText(L.w_next)
    Show(f.step)
    return f
end

function WD:ShowWizard(force, step)
    if W and W:IsShown() and not force then return end
    if W then W:Hide() end
    W = Build(step)
    if W then W:Show() end
end

-- Mostra sozinho so na instalacao nova.
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    if WD.freshInstall and WatchdogDB and not WatchdogDB.wizardDone then
        C_Timer.After(4, function() pcall(WD.ShowWizard, WD) end)
    end
end)

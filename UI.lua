-- Watchdog: janela principal, botao do minimapa e comandos.
local _, WD = ...

local PERIODS = {
    { key = "all",     label = "Total" },
    { key = "month",   label = "Mes" },
    { key = "week",    label = "Semana" },
    { key = "day",     label = "Dia" },
    { key = "session", label = "Sessao" },
}

local ROW_H = 18
local state = { tab = "pve", period = "session", mob = nil }
local frame
local ui = {}
local rows = {}

local Num = BreakUpLargeNumbers or tostring

local function White(text)
    return "|cffffffff" .. tostring(text) .. "|r"
end

local function Gray(text)
    return "|cff888888" .. tostring(text) .. "|r"
end

local function QualityColor(quality)
    local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if c and c.hex then return c.hex end
    return "|cffffffff"
end

local function FormatDuration(seconds)
    if not seconds or seconds ~= seconds or seconds == math.huge then return "-" end
    seconds = math.floor(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    if h > 0 then return string.format("%dh %02dm", h, m) end
    if m > 0 then return string.format("%dm", m) end
    return string.format("%ds", seconds)
end

---------------------------------------------------------------------------
-- Linhas da lista
---------------------------------------------------------------------------
local function GetRow(i)
    local r = rows[i]
    if r then return r end

    r = CreateFrame("Button", nil, ui.content)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", ui.content, "TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetPoint("RIGHT", ui.content, "RIGHT", 0, 0)
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    r.right = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    r.right:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r.right:SetJustifyH("RIGHT")

    r.left = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.left:SetPoint("LEFT", r, "LEFT", 4, 0)
    r.left:SetPoint("RIGHT", r.right, "LEFT", -8, 0)
    r.left:SetJustifyH("LEFT")
    r.left:SetWordWrap(false)

    r:SetScript("OnClick", function(self)
        if self.onClick then self.onClick(self) end
    end)
    r:SetScript("OnEnter", function(self)
        if self.itemID then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. self.itemID)
            GameTooltip:Show()
        elseif self.hint then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.hint, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)

    rows[i] = r
    return r
end

local function SetRow(i, left, right, onClick, itemID, hint)
    local r = GetRow(i)
    r.left:SetText(left)
    r.right:SetText(right)
    r.onClick = onClick
    r.itemID = itemID
    r.hint = hint
    r:Show()
end

---------------------------------------------------------------------------
-- Render
---------------------------------------------------------------------------
local function SortedKeys(t, valueOf)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local va, vb = valueOf(a), valueOf(b)
        if va ~= vb then return va > vb end
        return tostring(a) < tostring(b)
    end)
    return keys
end

local function PeriodLabel()
    for _, p in ipairs(PERIODS) do
        if p.key == state.period then
            if p.key == "session" and WatchdogCharDB.sessionStart then
                return "Sessao (desde " .. date("%H:%M", WatchdogCharDB.sessionStart) .. ")"
            end
            return p.label
        end
    end
    return ""
end

local function RenderPvP(data)
    local p = data.pvp
    local kd = p.deaths > 0 and (p.kills / p.deaths) or p.kills
    ui.summary:SetText(PeriodLabel())
    ui.infoText:SetText(
        "Kills:  " .. White(Num(p.kills)) .. "\n\n" ..
        "Mortes:  " .. White(Num(p.deaths)) .. "\n\n" ..
        "K/D:  " .. White(string.format("%.2f", kd)) .. "\n\n" ..
        "Honra ganha:  " .. White(Num(p.honor))
    )
end

local function RenderXP(data)
    local s = WD:GetXPStats()
    ui.summary:SetText(PeriodLabel())
    local lines = {
        "XP ganha no periodo:  " .. White(Num(data.xp or 0)),
        "",
        Gray("Sessao atual (" .. FormatDuration(s.elapsed) .. ")"),
        "XP na sessao:  " .. White(Num(s.sessionXP)),
        "XP/hora:  " .. White(Num(math.floor(s.perHour))),
        "Niveis ganhos:  " .. White(s.levels),
        "",
    }
    if s.maxLevel then
        lines[#lines + 1] = "Nivel " .. White(s.level) .. "  -  nivel maximo"
    else
        local pct = s.max > 0 and (s.cur / s.max * 100) or 0
        lines[#lines + 1] = "Nivel " .. White(s.level) .. ":  " .. White(Num(s.cur)) .. " / " ..
            White(Num(s.max)) .. "  (" .. string.format("%.1f%%", pct) .. ")"
        lines[#lines + 1] = "Falta para upar:  " .. White(Num(s.remaining))
        lines[#lines + 1] = "Tempo para upar:  " .. White(FormatDuration(s.timeToLevel))
        lines[#lines + 1] = "Kills para upar:  " ..
            White(s.killsToLevel and Num(s.killsToLevel) or "-") ..
            (s.avgKill and Gray("  (~" .. Num(math.floor(s.avgKill)) .. " XP/kill)") or "")
        if s.rested and s.rested > 0 then
            lines[#lines + 1] = "XP descansada:  " .. White(Num(s.rested))
        end
    end
    ui.infoText:SetText(table.concat(lines, "\n"))
end

local function RenderPvE(data)
    local n = 0
    local mob = state.mob and data.mobs[state.mob]
    if state.mob and mob then
        ui.back:Show()
        ui.summary:SetText("|cffffd100" .. state.mob .. "|r  -  " .. White(Num(mob.kills)) .. " mortos")
        local ids = SortedKeys(mob.loot, function(id) return mob.loot[id] end)
        for _, id in ipairs(ids) do
            local name, quality = WD:GetItemDisplay(id)
            n = n + 1
            SetRow(n, QualityColor(quality) .. name .. "|r", Num(mob.loot[id]) .. " dropados", nil, id)
        end
        if n == 0 then
            n = 1
            SetRow(n, Gray("Nenhum drop registrado ainda."), "")
        end
    else
        state.mob = nil
        ui.back:Hide()
        local total = 0
        for _, m in pairs(data.mobs) do total = total + m.kills end
        ui.summary:SetText(PeriodLabel() .. "  -  " .. White(Num(total)) .. " kills")
        local names = SortedKeys(data.mobs, function(name) return data.mobs[name].kills end)
        for _, name in ipairs(names) do
            n = n + 1
            SetRow(n, name, Num(data.mobs[name].kills) .. " mortos", function()
                state.mob = name
                ui.scroll:SetVerticalScroll(0)
                WD:Render()
            end, nil, "Clique para ver os drops")
        end
        if n == 0 then
            n = 1
            SetRow(n, Gray("Nenhuma kill registrada nesse periodo."), "")
        end
    end
    return n
end

function WD:Render()
    if not frame or not frame:IsShown() then return end

    for _, b in ipairs(ui.periodButtons) do
        if b.key == state.period then b:LockHighlight() else b:UnlockHighlight() end
    end
    for key, b in pairs(ui.tabs) do
        if key == state.tab then b:LockHighlight() else b:UnlockHighlight() end
    end

    local data = WD:Aggregate(state.period)
    local n = 0

    if state.tab == "pve" then
        ui.infoText:Hide()
        ui.scroll:Show()
        n = RenderPvE(data)
    else
        ui.scroll:Hide()
        ui.back:Hide()
        ui.infoText:Show()
        if state.tab == "pvp" then RenderPvP(data) else RenderXP(data) end
    end

    for i = n + 1, #rows do rows[i]:Hide() end
    ui.content:SetHeight(math.max(1, n * ROW_H))
end

local pending = false
function WD:Refresh()
    if not frame or not frame:IsShown() or pending then return end
    pending = true
    C_Timer.After(0.2, function()
        pending = false
        WD:Render()
    end)
end

---------------------------------------------------------------------------
-- Janela
---------------------------------------------------------------------------
local function MakeButton(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    return b
end

local function SavePosition(f)
    local point, _, relPoint, x, y = f:GetPoint()
    WatchdogDB.pos = { point, relPoint, x, y }
end

local function CreateMainFrame()
    local f = CreateFrame("Frame", "WatchdogFrame", UIParent, "BackdropTemplate")
    f:SetSize(380, 460)
    local pos = WatchdogDB.pos
    if pos then
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        f:SetPoint("CENTER")
    end
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition(self)
    end)
    f:SetScript("OnShow", function() WD:Render() end)
    f:Hide()
    tinsert(UISpecialFrames, "WatchdogFrame") -- ESC fecha

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("Watchdog")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    -- Abas PvE / PvP / EXP
    ui.tabs = {}
    local prevTab
    for _, t in ipairs({ { "pve", "PvE" }, { "pvp", "PvP" }, { "xp", "EXP" } }) do
        local key = t[1]
        local b = MakeButton(f, t[2], 80)
        if prevTab then
            b:SetPoint("LEFT", prevTab, "RIGHT", 6, 0)
        else
            b:SetPoint("TOPLEFT", 22, -44)
        end
        b:SetScript("OnClick", function() state.tab = key; WD:Render() end)
        ui.tabs[key] = b
        prevTab = b
    end

    -- Periodos
    ui.periodButtons = {}
    local prev
    for _, p in ipairs(PERIODS) do
        local b = MakeButton(f, p.label, 64)
        b.key = p.key
        if prev then
            b:SetPoint("LEFT", prev, "RIGHT", 2, 0)
        else
            b:SetPoint("TOPLEFT", 22, -72)
        end
        b:SetScript("OnClick", function()
            state.period = p.key
            WD:Render()
        end)
        ui.periodButtons[#ui.periodButtons + 1] = b
        prev = b
    end

    ui.summary = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.summary:SetPoint("TOPLEFT", 24, -104)
    ui.summary:SetPoint("RIGHT", f, "RIGHT", -96, 0)
    ui.summary:SetJustifyH("LEFT")
    ui.summary:SetWordWrap(false)

    ui.back = MakeButton(f, "< Voltar", 70)
    ui.back:SetPoint("TOPRIGHT", -22, -98)
    ui.back:SetScript("OnClick", function() state.mob = nil; WD:Render() end)

    -- Lista com rolagem (PvE)
    ui.scroll = CreateFrame("ScrollFrame", "WatchdogScroll", f, "UIPanelScrollFrameTemplate")
    ui.scroll:SetPoint("TOPLEFT", 20, -126)
    ui.scroll:SetPoint("BOTTOMRIGHT", -40, 22)
    ui.content = CreateFrame("Frame", nil, ui.scroll)
    ui.content:SetSize(310, 1)
    ui.scroll:SetScrollChild(ui.content)
    ui.scroll:SetScript("OnSizeChanged", function(_, w)
        ui.content:SetWidth(w)
    end)

    -- Texto das abas PvP e EXP
    ui.infoText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.infoText:SetPoint("TOPLEFT", 30, -136)
    ui.infoText:SetPoint("RIGHT", f, "RIGHT", -30, 0)
    ui.infoText:SetJustifyH("LEFT")
    ui.infoText:SetJustifyV("TOP")
    ui.infoText:SetSpacing(3)

    frame = f
end

function WD:Toggle()
    if not frame then CreateMainFrame() end
    frame:SetShown(not frame:IsShown())
end

---------------------------------------------------------------------------
-- Botao do minimapa
---------------------------------------------------------------------------
local function CreateMinimapButton()
    local mb = CreateFrame("Button", "WatchdogMinimapButton", Minimap)
    mb:SetSize(31, 31)
    mb:SetFrameStrata("MEDIUM")
    mb:SetFrameLevel(8)
    mb:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    mb:RegisterForClicks("LeftButtonUp")
    mb:RegisterForDrag("LeftButton")

    local icon = mb:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\Ability_EyeOfTheOwl")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 7, -5)

    local border = mb:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    local function UpdatePosition()
        local a = math.rad(WatchdogDB.minimapAngle or 210)
        mb:ClearAllPoints()
        mb:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * 80, math.sin(a) * 80)
    end

    mb:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            WatchdogDB.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            UpdatePosition()
        end)
    end)
    mb:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    mb:SetScript("OnClick", function() WD:Toggle() end)
    mb:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Watchdog")
        GameTooltip:AddLine("Clique: abrir/fechar", 1, 1, 1)
        GameTooltip:AddLine("Arrastar: mover botao", 1, 1, 1)
        GameTooltip:Show()
    end)
    mb:SetScript("OnLeave", function() GameTooltip:Hide() end)

    if WatchdogDB.hideMinimap then mb:Hide() end
    UpdatePosition()
    ui.minimap = mb
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    CreateMinimapButton()
end)

---------------------------------------------------------------------------
-- Comandos
---------------------------------------------------------------------------
SLASH_WATCHDOG1 = "/wd"
SLASH_WATCHDOG2 = "/watchdog"
SlashCmdList.WATCHDOG = function(msg)
    msg = strtrim((msg or ""):lower())
    if msg == "nova" then
        WD:StartNewSession()
        print("|cffffd100Watchdog:|r nova sessao iniciada.")
    elseif msg == "minimapa" then
        WatchdogDB.hideMinimap = not WatchdogDB.hideMinimap
        if ui.minimap then ui.minimap:SetShown(not WatchdogDB.hideMinimap) end
    elseif msg == "ajuda" then
        print("|cffffd100Watchdog|r comandos:")
        print("  /wd - abre/fecha a janela")
        print("  /wd nova - comeca uma nova sessao")
        print("  /wd minimapa - mostra/esconde o botao do minimapa")
    else
        WD:Toggle()
    end
end

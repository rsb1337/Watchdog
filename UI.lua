-- Watchdog: janela principal (visual do app Watchdog), barras flutuantes, avisos,
-- relatorio, botao do minimapa e comandos.
local _, WD = ...
local L = WD.L

local MEDIA = "Interface\\AddOns\\Watchdog\\Media\\"
local BT = BackdropTemplateMixin and "BackdropTemplate" or nil
local FONT = STANDARD_TEXT_FONT

---------------------------------------------------------------------------
-- Paleta (mesma do app Watchdog)
---------------------------------------------------------------------------
local C = {
    bg      = { 0.043, 0.055, 0.075 },
    card    = { 0.082, 0.102, 0.137 },
    tile    = { 0.118, 0.141, 0.188 },
    border  = { 0.176, 0.208, 0.271 },
    text    = { 0.953, 0.957, 0.965 },
    dim     = { 0.612, 0.639, 0.686 },
    mute    = { 0.420, 0.447, 0.502 },
    green   = { 0.063, 0.725, 0.506 },
    red     = { 0.937, 0.267, 0.267 },
    gold    = { 0.984, 0.749, 0.141 },
    purple  = { 0.486, 0.227, 0.929 },
    blue    = { 0.400, 0.600, 1.000 },
}

local PERIODS = {
    { key = "all",     labelK = "period_all" },
    { key = "month",   labelK = "period_month" },
    { key = "week",    labelK = "period_week" },
    { key = "day",     labelK = "period_day" },
    { key = "session", labelK = "period_session" },
}

local TABS = {
    { key = "pve",    titleK = "title_pve" },
    { key = "xp",     titleK = "title_xp" },
    { key = "inv",    titleK = "title_inv" },
    { key = "hist",   titleK = "title_hist" },
    { key = "pvp",    titleK = "title_pvp" },
    { key = "alerts", titleK = "title_alerts" },
    { key = "black",  titleK = "title_black" },
    { key = "buttons", titleK = "title_buttons" },
    { key = "ah", titleK = "title_ah" },
}
-- Menu lateral: grupos. O grupo PvE tem sub-menu (mobs / EXP / inventario / historico).
local GROUPS = {
    { key = "pve",    labelK = "tab_pve" },
    { key = "pvp",    labelK = "tab_pvp" },
    { key = "alerts", labelK = "tab_alerts" },
    { key = "black",  labelK = "tab_black" },
    { key = "buttons", labelK = "tab_buttons" },
    { key = "ah", labelK = "tab_ah" },
}
local PVE_SUBS = {
    { key = "pve",  labelK = "sub_mobs" },
    { key = "xp",   labelK = "tab_xp" },
    { key = "inv",  labelK = "tab_inv" },
    { key = "hist", labelK = "tab_hist" },
}
local function GroupOf(tab)
    if tab == "pve" or tab == "xp" or tab == "inv" or tab == "hist" then return "pve" end
    return tab
end

local SORTS = {
    { key = "kills",   labelK = "sort_kills" },
    { key = "value",   labelK = "sort_value" },
    { key = "perkill", labelK = "sort_perkill" },
    { key = "hit",     labelK = "sort_hit" },
    { key = "recent",  labelK = "sort_recent" },
}

local INV_VIEWS = {
    { key = "bag",  labelK = "inv_bag" },
    { key = "list", labelK = "inv_list" },
}

local FRAME_W, FRAME_H = 740, 498
local SIDE_W = 170
local PAD = 20
local CONTENT_W = FRAME_W - SIDE_W - PAD * 2   -- 470
local ROW_H = 28
local GAP = 10
local SLOT = 34
local SLOT_GAP = 3
local SLOT_COLS = 12

local state = { tab = "pve", period = "session", mob = nil, sort = "kills", invView = "bag" }
local frame
local ui = {}
local BuildBlackPanel -- definido mais abaixo (usado por WD:Render)
local BuildButtonsPanel -- idem
local BuildAHPanel -- idem
local rows = {}
local tiles = {}
local slots = {}
local contentH = 1
WD.state, WD.ui = state, ui   -- util para depuracao

local Num = BreakUpLargeNumbers or tostring

local function Hex(c)
    return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

local function White(text) return "|cffffffff" .. tostring(text) .. "|r" end
local function Gray(text) return Hex(C.dim) .. tostring(text) .. "|r" end

local function QualityColor(quality)
    local c = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if c and type(c.hex) == "string" then return c.hex end
    return "|cffffffff"
end

-- Valor em moedas (ouro/prata/cobre com icones), a partir de cobre.
local ICON_G = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t"
local ICON_S = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t"
local ICON_C = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t"

local function Coins(copper)
    copper = math.floor(copper or 0)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local out = {}
    if g > 0 then out[#out + 1] = g .. ICON_G end
    if g > 0 or s > 0 then out[#out + 1] = s .. ICON_S end
    out[#out + 1] = c .. ICON_C
    return table.concat(out, " ")
end

local function FormatClock(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    return string.format("%02d:%02d:%02d", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60), seconds % 60)
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

local function UpdateTimer()
    if not ui.timer then return end
    local start = WatchdogCharDB and WatchdogCharDB.sessionStart
    ui.timer:SetText(start and FormatClock(time() - start) or "--:--:--")
end

-- Ouro por hora da sessao atual (itens + dinheiro / tempo de sessao).
local function SessionGoldPerHour()
    local total = WD:SessionProbable()
    local elapsed = math.max(60, time() - (WatchdogCharDB.sessionStart or time()))
    return total / elapsed * 3600, total
end

local function SessionKills(bucket)
    local k = 0
    for _, m in pairs(bucket.mobs) do k = k + (m.kills or 0) end
    return k
end

---------------------------------------------------------------------------
-- Helpers visuais
---------------------------------------------------------------------------
-- 1 pixel fisico da tela em unidades do frame (evita borda de 1px sumir em escalas fracionadas)
local function PixelSize(f)
    local h
    if GetPhysicalScreenSize then h = select(2, GetPhysicalScreenSize()) end
    local es = f.GetEffectiveScale and f:GetEffectiveScale()
    if type(h) ~= "number" or h < 100 or type(es) ~= "number" or es <= 0 then return 1 end
    return (768 / h) / es
end

local function Flat(f, bg, border, alpha)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = PixelSize(f),
    })
    f:SetBackdropColor(bg[1], bg[2], bg[3], alpha or 1)
    local b = border or bg
    f:SetBackdropBorderColor(b[1], b[2], b[3], 1)
end

local function FS(parent, size, color, justify, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, size, flags or "")
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

local function MakeChip(parent, text, width)
    local b = CreateFrame("Button", nil, parent, BT)
    b:SetSize(width, 24)
    Flat(b, C.card, C.border, 0.9)
    b.text = FS(b, 12, C.dim, "CENTER")
    b.text:SetPoint("CENTER", 0, 0)
    b.text:SetText(text)
    b.SetActive = function(self, on)
        self.active = on
        if on then
            Flat(self, C.tile, C.red, 1)
            self.text:SetTextColor(1, 1, 1)
        else
            Flat(self, C.card, C.card, 0.9)   -- sem borda: so o selecionado "acende"
            self.text:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
        end
    end
    b:SetScript("OnEnter", function(self)
        if not self.active then self.text:SetTextColor(C.text[1], C.text[2], C.text[3]) end
    end)
    b:SetScript("OnLeave", function(self)
        if not self.active then self.text:SetTextColor(C.dim[1], C.dim[2], C.dim[3]) end
    end)
    return b
end

-- Kit visual compartilhado com outros modulos (menu de configuracao do Assistente).
WD.UIKit = { C = C, Flat = Flat, FS = FS, MakeChip = MakeChip, BT = BT, FONT = FONT, MEDIA = MEDIA, SIDE_W = SIDE_W, PAD = PAD }

---------------------------------------------------------------------------
-- Lista (linhas)
---------------------------------------------------------------------------
local function GetRow(i)
    local r = rows[i]
    if r then return r end

    r = CreateFrame("Button", nil, ui.content)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", ui.content, "TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetPoint("RIGHT", ui.content, "RIGHT", 0, 0)

    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()

    r.bar = r:CreateTexture(nil, "BORDER")
    r.bar:SetPoint("TOPLEFT")
    r.bar:SetPoint("BOTTOMLEFT")
    r.bar:SetColorTexture(C.red[1], C.red[2], C.red[3], 0.16)

    r.hl = r:CreateTexture(nil, "HIGHLIGHT")
    r.hl:SetAllPoints()
    r.hl:SetColorTexture(1, 1, 1, 0.06)

    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(18, 18)
    r.icon:SetPoint("LEFT", 8, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    r.right = FS(r, 12, C.dim, "RIGHT")
    r.right:SetPoint("RIGHT", -10, 0)

    r.left = FS(r, 13, C.text, "LEFT")
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
            GameTooltip:SetText(self.hint, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)

    rows[i] = r
    return r
end

local function SetRow(i, o)
    local r = GetRow(i)
    if i % 2 == 0 then
        r.bg:SetColorTexture(C.card[1], C.card[2], C.card[3], 0.55)
    else
        r.bg:SetColorTexture(C.card[1], C.card[2], C.card[3], 0.25)
    end

    r.left:ClearAllPoints()
    if o.icon then
        r.icon:SetTexture(o.icon)
        r.icon:Show()
        r.left:SetPoint("LEFT", r, "LEFT", 34, 0)
    else
        r.icon:Hide()
        r.left:SetPoint("LEFT", r, "LEFT", 12, 0)
    end
    r.left:SetPoint("RIGHT", r.right, "LEFT", -8, 0)

    r.left:SetText(o.left or "")
    r.right:SetText(o.right or "")
    r.onClick = o.onClick
    r.itemID = o.itemID
    r.hint = o.hint

    local pct = o.pct or 0
    if pct > 0 then
        r.bar:SetWidth(math.max(1, CONTENT_W * math.min(1, pct)))
        r.bar:Show()
    else
        r.bar:Hide()
    end
    r:Show()
end

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
                return L.session_since .. date("%H:%M", WatchdogCharDB.sessionStart) .. ")"
            end
            return L[p.labelK]
        end
    end
    return ""
end

---------------------------------------------------------------------------
-- Slots da bolsa (aba Inventario, modo Bolsa)
---------------------------------------------------------------------------
local function GetSlot(i)
    local b = slots[i]
    if b then return b end
    b = CreateFrame("Button", nil, ui.content, BT)
    b:SetSize(SLOT, SLOT)
    Flat(b, C.card, C.border, 0.9)

    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 2, -2)
    b.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    b.count = FS(b, 11, C.text, "RIGHT", "OUTLINE")
    b.count:SetPoint("BOTTOMRIGHT", -3, 3)

    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.12)

    b:SetScript("OnEnter", function(self)
        if not self.link then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(self.link)
        if self.value and self.value > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Valor: " .. Coins(self.value) ..
                ((self.countN or 1) > 1 and ("  (" .. self.countN .. "x)") or ""), 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    slots[i] = b
    return b
end

local function SetSlot(i, entry)
    local b = GetSlot(i)
    local col = (i - 1) % SLOT_COLS
    local row = math.floor((i - 1) / SLOT_COLS)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", ui.content, "TOPLEFT", col * (SLOT + SLOT_GAP), -row * (SLOT + SLOT_GAP))

    if entry.icon then
        b.icon:SetTexture(entry.icon)
        b.icon:Show()
        b.count:SetText((entry.count or 1) > 1 and entry.count or "")
        local qc = entry.quality and entry.quality >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[entry.quality]
        local vc = entry.itemID and WD:ItemBorderColor(entry.itemID, entry.bound)
        b.icon:SetAlpha((entry.itemID and WD:BorderOpt().on and WD:ItemDimmed(entry.itemID, entry.bound)) and 0.3 or 1)
        if vc then
            Flat(b, C.card, vc, 1)
        elseif qc then
            Flat(b, C.card, { qc.r, qc.g, qc.b }, 1)
        else
            Flat(b, C.card, C.border, 1)
        end
        b.link, b.value, b.countN = entry.link, entry.value, entry.count
    else
        b.icon:Hide()
        b.count:SetText("")
        Flat(b, C.card, C.border, 0.45)
        b.link, b.value, b.countN = nil, nil, nil
    end
    b:Show()
end

---------------------------------------------------------------------------
-- Tiles (PvP / EXP)
---------------------------------------------------------------------------
local function GetTile(i)
    local t = tiles[i]
    if t then return t end
    t = CreateFrame("Frame", nil, ui.info, BT)
    t:SetHeight(62)
    Flat(t, C.tile, C.border, 1)

    t.accent = t:CreateTexture(nil, "OVERLAY")
    t.accent:SetPoint("TOPLEFT", 1, -1)
    t.accent:SetPoint("TOPRIGHT", -1, -1)
    t.accent:SetHeight(2)

    t.value = FS(t, 22, C.text, "LEFT", "OUTLINE")
    t.value:SetPoint("TOPLEFT", 12, -10)
    t.label = FS(t, 10, C.dim, "LEFT")
    t.label:SetPoint("BOTTOMLEFT", 12, 9)
    t.sub = FS(t, 10, C.mute, "RIGHT")
    t.sub:SetPoint("BOTTOMRIGHT", -12, 9)

    tiles[i] = t
    return t
end

local function SetTile(i, col, cols, y, label, value, color, sub, compact)
    local t = GetTile(i)
    t:SetHeight(compact and 52 or 62)
    t.value:SetFont(FONT, compact and 18 or 22, "OUTLINE")
    local w = (CONTENT_W - (cols - 1) * GAP) / cols
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", ui.info, "TOPLEFT", (col - 1) * (w + GAP), -y)
    t:SetWidth(w)
    color = color or C.text
    t.value:SetText(value)
    t.value:SetTextColor(color[1], color[2], color[3])
    t.accent:SetColorTexture(color[1], color[2], color[3], 0.85)
    t.label:SetText(label)
    t.sub:SetText(sub or "")
    t:Show()
end

local function HideInfo()
    for _, t in pairs(tiles) do t:Hide() end
    ui.xpBar:Hide()
    ui.xpLabel:Hide()
    ui.xpPct:Hide()
end

---------------------------------------------------------------------------
-- Render por aba
---------------------------------------------------------------------------
local function RenderPvP(data)
    local p = data.pvp
    local kd = p.deaths > 0 and (p.kills / p.deaths) or p.kills
    ui.summary:SetText(PeriodLabel())
    SetTile(1, 1, 2, 0,  L.t_kills,  Num(p.kills),  C.green)
    SetTile(2, 2, 2, 0,  L.t_deaths, Num(p.deaths), C.red)
    SetTile(3, 1, 2, 72, "K/D",      string.format("%.2f", kd), C.text)
    SetTile(4, 2, 2, 72, L.t_honor,  Num(p.honor),  C.gold)
end

local function RenderXP(data)
    local s = WD:GetXPStats()
    ui.summary:SetText(WatchdogCharDB.sessionStart and (L.session_since .. date("%H:%M", WatchdogCharDB.sessionStart) .. ")") or L.period_session)

    SetTile(1, 1, 3, 0, L.t_xp_session, Num(s.sessionXP), C.text)
    SetTile(2, 2, 3, 0, L.t_xp_hour,    Num(math.floor(s.perHour)), C.green, FormatDuration(s.elapsed))
    SetTile(3, 3, 3, 0, L.t_levels,     tostring(s.levels), C.gold)

    ui.xpLabel:Show()
    ui.xpBar:Show()
    ui.xpPct:Show()
    ui.xpLabel:SetText(L.level_prefix .. White(s.level))
    local barW = CONTENT_W - 2
    if s.maxLevel then
        ui.xpFill:SetWidth(barW)
        ui.xpPct:SetText(L.max_level)
    else
        local frac = s.max > 0 and (s.cur / s.max) or 0
        ui.xpFill:SetWidth(math.max(1, barW * math.min(1, frac)))
        ui.xpPct:SetText(string.format("%s / %s  (%.1f%%)", Num(s.cur), Num(s.max), frac * 100))

        local rested = (s.rested and s.rested > 0) and (L.rested_prefix .. Num(s.rested)) or nil
        SetTile(5, 1, 3, 130, L.t_remaining,  Num(s.remaining), C.text, rested)
        SetTile(6, 2, 3, 130, L.t_time_level,  FormatDuration(s.timeToLevel), C.text)
        SetTile(7, 3, 3, 130, L.t_kills_level,  s.killsToLevel and Num(s.killsToLevel) or "-", C.text,
            s.avgKill and ("~" .. Num(math.floor(s.avgKill)) .. " XP/kill") or nil)
    end
end

local function RareTag(name)
    if WatchdogDB.rareNames and WatchdogDB.rareNames[name] then
        return Hex(C.blue) .. L.rare_tag .. "|r"
    end
    return ""
end

local function RenderPvE(data)
    local n = 0
    local mob = state.mob and data.mobs[state.mob]
    if state.mob and mob then
        ui.back:Show()
        local ids = SortedKeys(mob.loot, function(id) return mob.loot[id] end)
        local top = ids[1] and mob.loot[ids[1]] or 1
        local itemsValue = 0
        for _, id in ipairs(ids) do
            local name, quality, sell = WD:GetItemDisplay(id)
            local qty = mob.loot[id]
            local right = White(Num(qty)) .. Gray(L.dropped_suffix)

            -- Taxa de drop: corpos que dropararam o item / kills.
            local drops = mob.lootN and mob.lootN[id]
            if drops and mob.kills > 0 then
                local rate = math.min(100, drops / mob.kills * 100)
                local col = rate >= 50 and C.green or (rate >= 15 and C.text or C.dim)
                right = right .. "  " .. Hex(col) .. string.format("%.0f%%", rate) .. "|r"
            end

            if sell and sell > 0 then
                itemsValue = itemsValue + sell * qty
                right = right .. "   " .. Coins(sell * qty)
            elseif sell == 0 then
                right = right .. "   " .. Gray(L.no_value)
            end
            n = n + 1
            SetRow(n, {
                left = QualityColor(quality) .. name .. "|r",
                right = right,
                itemID = id,
                icon = GetItemIcon and GetItemIcon(id) or nil,
                pct = qty / top,
            })
        end

        local money = mob.money or 0
        if money > 0 then
            n = n + 1
            SetRow(n, {
                left = L.money_dropped,
                right = Coins(money),
                icon = "Interface\\Icons\\INV_Misc_Coin_01",
            })
        end

        local total = itemsValue + money
        ui.summary:SetText("|cffffd100" .. state.mob .. "|r  ·  " .. White(Num(mob.kills)) .. L.killed_suffix ..
            (total > 0 and ("  ·  " .. L.worth_prefix .. Coins(total)) or ""))

        if n > 0 then
            n = n + 1
            SetRow(n, {
                left = Hex(C.gold) .. L.total_items_money .. "|r",
                right = total > 0 and Coins(total) or Gray(L.no_value),
            })
        else
            n = 1
            SetRow(n, { left = Gray(L.no_drops) })
        end
    else
        state.mob = nil
        ui.back:Hide()
        local total = 0
        local entries = {}
        for name, m in pairs(data.mobs) do
            local v = WD:MobValue(m)
            total = total + (m.kills or 0)
            entries[#entries + 1] = {
                name = name, m = m, kills = m.kills or 0, value = v,
                per = (m.kills or 0) > 0 and (v / m.kills) or 0,
                hit = (m.kills or 0) > 0 and math.min(1, (m.hit or 0) / m.kills) or 0,
                last = m.last or 0,
            }
            -- Ranking por drop % so conta mobs com amostra minima (>= 5 kills).
            entries[#entries].hitr = (m.kills or 0) >= 5 and entries[#entries].hit or 0
        end
        local metric = state.sort == "value" and "value" or (state.sort == "perkill" and "per")
            or (state.sort == "hit" and "hitr") or (state.sort == "recent" and "last") or "kills"
        table.sort(entries, function(a, b)
            if a[metric] ~= b[metric] then return a[metric] > b[metric] end
            if metric == "hitr" and a.per ~= b.per then return a.per > b.per end
            if a.kills ~= b.kills then return a.kills > b.kills end
            return a.name < b.name
        end)

        ui.summary:SetText(PeriodLabel() .. "  ·  " .. White(Num(total)) .. L.kills_word)
        local top = entries[1] and entries[1][metric] or 0
        if metric == "last" then    -- na ordem por recencia a barra mostra o valor, nao o horario
            top = 0
            for _, e in ipairs(entries) do if e.value > top then top = e.value end end
        end
        if top <= 0 then top = 1 end
        for _, e in ipairs(entries) do
            n = n + 1
            local right = White(Num(e.kills)) .. Gray(L.killed_suffix)
            if e.value > 0 then
                if state.sort == "perkill" or state.sort == "hit" then
                    right = right .. "   " .. Coins(e.per) .. Gray("/kill")
                    if e.kills >= 5 then
                        right = right .. Gray("  " .. math.floor(e.hit * 100 + 0.5) .. "% drop")
                    end
                else
                    right = right .. "   " .. Coins(e.value)
                end
            end
            local name = e.name
            SetRow(n, {
                left = RareTag(name) .. name,
                right = right,
                onClick = function()
                    state.mob = name
                    ui.scroll:SetVerticalScroll(0)
                    WD:Render()
                end,
                hint = L.click_drops,
                pct = (metric == "last" and e.value or e[metric]) / top,
            })
        end
        if n == 0 then
            n = 1
            SetRow(n, { left = Gray(L.no_kills) })
        end
    end
    return n
end

-- Aba Inventario: retorna numero de linhas (modo lista) ou 0 (modo bolsa, usa slots).
local function RenderInv()
    local scan = WD:ScanBags()
    ui.summary:SetText(L.bags_label .. Coins(scan.value) .. "  ·  " .. White(scan.used) ..
        Gray("/" .. scan.total .. L.slots_word))

    if state.invView == "bag" then
        for i, entry in ipairs(scan.slots) do SetSlot(i, entry) end
        for i = #scan.slots + 1, #slots do slots[i]:Hide() end
        local nRows = math.ceil(#scan.slots / SLOT_COLS)
        contentH = math.max(1, nRows * (SLOT + SLOT_GAP))
        return 0
    end

    -- Lista: itens agrupados por ID, valor stackado.
    local agg, order = {}, {}
    for _, s in ipairs(scan.slots) do
        if s.itemID then
            local a = agg[s.itemID]
            if not a then
                a = { id = s.itemID, name = s.name, quality = s.quality, icon = s.icon,
                      count = 0, value = 0, sell = s.sell }
                agg[s.itemID] = a
                order[#order + 1] = a
            end
            a.count = a.count + (s.count or 1)
            a.value = a.value + (s.value or 0)
        end
    end
    table.sort(order, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return (a.name or "") < (b.name or "")
    end)

    local n = 0
    local top = order[1] and order[1].value or 0
    if top <= 0 then top = 1 end
    for _, a in ipairs(order) do
        n = n + 1
        local right
        if a.value > 0 then
            right = Coins(a.value)
        elseif a.sell == nil then
            right = Gray("?")
        else
            right = Gray(L.no_value)
        end
        SetRow(n, {
            left = QualityColor(a.quality) .. (a.name or ("Item #" .. a.id)) .. "|r" ..
                (a.count > 1 and Gray("  ×" .. Num(a.count)) or ""),
            right = right,
            itemID = a.id,
            icon = a.icon,
            pct = a.value / top,
        })
    end
    if n == 0 then
        n = 1
        SetRow(n, { left = Gray(L.bags_empty) })
    end
    contentH = math.max(1, n * ROW_H)
    return n
end

-- Aba Historico: sessao atual + sessoes salvas (mais recentes primeiro).
local function SessionLine(i, o)
    local dur = math.max(1, o.dur)
    local xph = o.xp / dur * 3600
    local gph = o.value / dur * 3600
    local right = White(Num(o.kills)) .. Gray(L.kills_word .. "  ·  ") ..
        White(Num(math.floor(xph))) .. Gray(L.hist_line_mid) .. Coins(gph) .. Gray(L.hist_line_end)
    local hint = string.format(L.hist_tooltip,
        FormatDuration(dur), Num(o.kills), Num(o.xp), o.levels or 0,
        WD:CoinText(o.value), WD:CoinText(o.money or 0),
        o.pvpKills or 0, o.deaths or 0, Num(o.honor or 0))
    SetRow(i, {
        left = o.label .. Gray("  ·  " .. FormatDuration(dur)),
        right = right,
        hint = hint,
        onClick = o.onClick,
    })
end

local RenderDetail

-- Ouro em uma unica unidade ("28.7g"), sem prata/cobre.
local function GoldFmt(copper, signed)
    copper = copper or 0
    local g = copper / 10000
    local s
    if math.abs(g) >= 1000 then s = Num(math.floor(math.abs(g) + 0.5)) .. "g" else s = string.format("%.1fg", math.abs(g)) end
    if g < 0 then s = "-" .. s elseif signed then s = "+" .. s end
    return s
end

local function Pct(a, b)
    if not a or not b or b <= 0 then return "" end
    return string.format("%d%%", math.floor(a / b * 100 + 0.5))
end

RenderDetail = function(r, isWin)
    HideInfo()
    local dur = math.max(1, r.dur or 0)
    local dash = "-"
    local function D(sec) return sec and FormatDuration(sec) or dash end
    -- cabecalho
    if isWin then
        local hrs = r.window or 24
        local label = hrs % 24 == 0 and (hrs / 24 == 1 and L.win_24h or string.format(L.win_days, hrs / 24)) or (hrs .. "h")
        local txt = string.format(L.win_title, label) .. Gray("  ·  " .. string.format(L.win_sessions_n, r.sessions or 0))
        if (r.unknown or 0) > 60 then txt = txt .. Gray("  ·  " .. string.format(L.d_note_unknown, FormatDuration(r.unknown))) end
        ui.summary:SetText(txt)
    else
        ui.summary:SetText(date("%d/%m %H:%M", r.start) .. Gray(" -> ") .. date("%H:%M", r.stop))
    end

    -- 1) tempo / mobs / K/D
    SetTile(1, 1, 3, 0, L.d_time, D(isWin and r.dur or r.dur), C.text, isWin and (L.d_online) or nil, true)
    SetTile(2, 2, 3, 0, L.d_mobs, Num(r.kills), C.text, string.format(L.d_per_hour, Num(math.floor(r.kills / dur * 3600))), true)
    local kd = r.deaths > 0 and (r.pvpKills / r.deaths) or r.pvpKills
    SetTile(3, 3, 3, 0, L.d_kd, string.format("%.2f", kd),
        (r.pvpKills == 0 and r.deaths == 0) and C.text or (kd < 1 and C.red or C.green), r.pvpKills .. " / " .. r.deaths, true)

    -- 2) EXP (mob x quest)
    local part = (r.unknown or 0) > 60 and L.d_partial or nil
    local mobXP, questXP = r.killXP, r.questXP
    SetTile(4, 1, 3, 58, L.d_xp, Num(r.xp), C.purple,
        string.format(L.d_per_hour, Num(math.floor(r.xp / dur * 3600))) .. ((r.levels or 0) > 0 and ("  " .. string.format(L.d_levels, r.levels)) or ""), true)
    SetTile(5, 2, 3, 58, L.d_xp_mob, mobXP and Num(mobXP) or dash, C.purple, part or (mobXP and Pct(mobXP, r.xp) or L.d_nodata), true)
    SetTile(6, 3, 3, 58, L.d_xp_quest, questXP and Num(questXP) or dash, C.purple,
        part or (r.quests and string.format(L.d_quests_n, r.quests) or L.d_nodata), true)

    -- 3) Ouro: coletado (puro + itens no vendor) / leilao (AH) / provavel
    local g = WD:GoldSummary(r)
    if g.legacy then
        SetTile(7, 1, 3, 116, L.d_gold_coll, dash, C.gold, nil, true)
        SetTile(8, 2, 3, 116, L.d_gold_ah, dash, C.gold, nil, true)
        SetTile(9, 3, 3, 116, L.d_gold_prob, GoldFmt(g.probable), C.gold, L.d_gold_legacy, true)
    else
        SetTile(7, 1, 3, 116, L.d_gold_coll, GoldFmt(g.coin + g.invV), C.gold, nil, true)
        SetTile(8, 2, 3, 116, L.d_gold_ah, GoldFmt(g.ah), C.gold, nil, true)
        SetTile(9, 3, 3, 116, L.d_gold_prob, GoldFmt(g.probable), C.gold, r.goldPartial and L.d_partial or nil, true)
    end

    -- 4) Grind x fora do grind
    local t = r.t
    local off
    if t then off = (t.flight or 0) + (t.afk or 0) + (t.craft or 0) + (t.dead or 0) + (t.other or 0) end
    local classified = t and ((t.grind or 0) + off) or nil
    SetTile(10, 1, 3, 174, L.d_grind, t and D(t.grind) or dash, C.green, part or (classified and Pct(t.grind, classified) or L.d_nodata), true)
    SetTile(11, 2, 3, 174, L.d_off, t and D(off) or dash, C.red, part or (classified and Pct(off, classified) or L.d_nodata), true)
    if isWin then
        if (r.unknown or 0) > 60 then
            SetTile(12, 3, 3, 174, L.d_offline, dash, C.dim, L.d_nodata_old, true)
        else
            SetTile(12, 3, 3, 174, L.d_offline, D(r.offline), C.dim, Pct(r.offline, r.span), true)
        end
    else
        SetTile(12, 3, 3, 174, L.d_quests, r.quests and Num(r.quests) or dash, C.purple, nil, true)
    end

    -- 5) Detalhe do tempo fora do grind (craft entra em "Outros")
    local other = t and ((t.other or 0) + (t.dead or 0) + (t.craft or 0)) or nil
    SetTile(13, 1, 3, 232, L.d_flight, t and D(t.flight) or dash, C.text, nil, true)
    SetTile(14, 2, 3, 232, L.d_afk, t and D(t.afk) or dash, C.text, nil, true)
    SetTile(16, 3, 3, 232, L.d_other, t and D(other) or dash, C.text,
        (t and (t.dead or 0) > 0) and string.format(L.d_dead_sub, FormatDuration(t.dead)) or nil, true)
end

local function RenderHist()
    local hist = WatchdogCharDB.history or {}
    ui.summary:SetText(White(#hist) .. Gray(L.sessions_saved))
    local n = 0

    local s = WatchdogCharDB.session
    local start = WatchdogCharDB.sessionStart or time()
    n = n + 1
    local pvp = s.pvp or {}
    SessionLine(n, {
        label = Hex(C.gold) .. L.current_session .. "|r",
        dur = time() - start,
        kills = SessionKills(s),
        xp = s.xp or 0,
        levels = s.levels or 0,
        value = WD:SessionProbable(),
        money = s.money or 0,
        pvpKills = pvp.kills, deaths = pvp.deaths, honor = pvp.honor,
        onClick = function() state.histView = "current"; ui.scroll:SetVerticalScroll(0); WD:Render() end,
    })

    for i = #hist, 1, -1 do
        local h = hist[i]
        n = n + 1
        SessionLine(n, {
            label = date("%d/%m %H:%M", h.start),
            dur = (h.stop or h.start) - h.start,
            kills = h.kills or 0,
            xp = h.xp or 0,
            levels = h.levels or 0,
            value = (h.income ~= nil) and WD:GoldSummary(WD:RecordOf(h)).probable or (h.value or 0),
            money = h.money or 0,
            pvpKills = h.pvpKills, deaths = h.deaths, honor = h.honor,
            onClick = function() state.histView = i; ui.scroll:SetVerticalScroll(0); WD:Render() end,
        })
    end
    return n
end

local function SetChipVisibility()
    ui.histChips = ui.histChips or {}
    local grp = GroupOf(state.tab)
    local inPeriodTab = state.tab == "pve" or state.tab == "pvp"
    local rowY = (grp == "pve") and -106 or -76
    local left = SIDE_W + PAD
    if ui.periodButtons[1] then ui.periodButtons[1]:ClearAllPoints(); ui.periodButtons[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", left, rowY) end
    if ui.viewButtons[1] then ui.viewButtons[1]:ClearAllPoints(); ui.viewButtons[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", left, rowY) end
    ui.sortBtn:ClearAllPoints(); ui.sortBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, rowY)
    ui.info:ClearAllPoints()
    ui.info:SetPoint("TOPLEFT", frame, "TOPLEFT", left, (grp == "pve" and state.tab ~= "xp") and -146 or -116)
    ui.info:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD + 38)
    for _, b in ipairs(ui.periodButtons) do b:SetShown(inPeriodTab) end
    for _, b in ipairs(ui.viewButtons) do b:SetShown(state.tab == "inv") end
    ui.sortBtn:SetShown(state.tab == "pve" and not state.mob)
    if ui.borderBtn then
        ui.borderBtn:ClearAllPoints(); ui.borderBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, rowY)
        ui.borderBtn:SetShown(state.tab == "inv")
        local bon = WD:BorderOpt().on
        ui.borderBtn.text:SetText(L.inv_borders .. ": " .. (bon and L.cfg_on or L.cfg_off))
        ui.borderBtn:SetActive(bon)
    end
    for _, b in ipairs(ui.subChips) do b:SetShown(grp == "pve"); b:SetActive(b.key == state.tab) end
    ui.back:ClearAllPoints(); ui.back:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, rowY)   -- na linha do segundo menu
    for _, b in ipairs(ui.histChips) do
        b:SetShown(state.tab == "hist")
        local v = state.histView
        local on
        if b.key == "list" then on = (v == nil or v == "current" or type(v) == "number") else on = (v == b.key) end
        b:SetActive(on)
    end
end

function WD:Render()
    if not frame or not frame:IsShown() then return end

    for _, b in ipairs(ui.periodButtons) do b:SetActive(b.key == state.period) end
    for _, b in ipairs(ui.viewButtons) do b:SetActive(b.key == state.invView) end
    local grp = GroupOf(state.tab)
    if grp == "pve" then state.lastPve = state.tab end
    for key, b in pairs(ui.tabs) do b:SetActive(key == grp) end
    for _, t in ipairs(TABS) do
        if t.key == state.tab then ui.title:SetText(L[t.titleK]) end
    end
    for _, s in ipairs(SORTS) do
        if s.key == state.sort then ui.sortBtn.text:SetText(L[s.labelK]) end
    end

    UpdateTimer()
    local perHour, sessionTotal = SessionGoldPerHour()
    ui.gph:SetText(Coins(perHour) .. Gray(L.per_hour))
    ui.gphTotal:SetText(Gray(L.session_colon) .. Coins(sessionTotal))

    local n = 0
    local showSlots = false
    contentH = 1

    local isPanel = (state.tab == "alerts" or state.tab == "black" or state.tab == "buttons" or state.tab == "ah")
    ui.foot:SetShown(not isPanel)
    if ui.cfgHost then ui.cfgHost:SetShown(state.tab == "alerts") end
    if ui.blackHost then ui.blackHost:SetShown(state.tab == "black") end
    if ui.buttonsHost then ui.buttonsHost:SetShown(state.tab == "buttons") end
    if ui.ahHost then ui.ahHost:SetShown(state.tab == "ah") end
    if state.tab == "alerts" then
        if not ui.cfgHost and WD.CreateConfigPanel then ui.cfgHost = WD:CreateConfigPanel(frame, SIDE_W + PAD) end
        ui.scroll:Hide(); ui.back:Hide(); ui.info:Hide()
        if ui.cfgHost then ui.cfgHost:Show() end
        local okc, cname, cfile = pcall(UnitClass, "player")
        local txt = L.cfg_title or ""
        if okc and cname and cfile then
            local col = RAID_CLASS_COLORS and RAID_CLASS_COLORS[cfile]
            local hex = col and string.format("%02x%02x%02x", math.floor(col.r * 255), math.floor(col.g * 255), math.floor(col.b * 255)) or "ffffff"
            txt = (L.cfg_class or "Class") .. ": |cff" .. hex .. cname .. "|r"
        end
        ui.summary:SetText(txt)
    elseif state.tab == "black" then
        if not ui.blackHost then ui.blackHost = BuildBlackPanel(frame) end
        ui.scroll:Hide(); ui.back:Hide(); ui.info:Hide()
        ui.blackHost:Show()
        ui.summary:SetText(White(#WD:WatchList("pve")) .. Gray(" PvE  ·  ") .. White(#WD:WatchList("pvp")) .. Gray(" PvP"))
    elseif state.tab == "buttons" then
        if not ui.buttonsHost then ui.buttonsHost = BuildButtonsPanel(frame) end
        ui.scroll:Hide(); ui.back:Hide(); ui.info:Hide()
        ui.buttonsHost:Show()
        ui.summary:SetText(Gray(L.btn_summary))
    elseif state.tab == "ah" then
        if not ui.ahHost then ui.ahHost = BuildAHPanel(frame) end
        ui.scroll:Hide(); ui.back:Hide(); ui.info:Hide()
        ui.ahHost:Show()
        ui.summary:SetText(Gray(L.ah_summary))
        if WD.RefreshAHTab then WD:RefreshAHTab() end
    elseif state.tab == "pve" then
        ui.info:Hide()
        ui.scroll:Show()
        n = RenderPvE(WD:Aggregate(state.period))
        contentH = math.max(1, n * ROW_H)
    elseif state.tab == "inv" then
        ui.info:Hide()
        ui.scroll:Show()
        ui.back:Hide()
        n = RenderInv()
        showSlots = state.invView == "bag"
    elseif state.tab == "hist" then
        local v, rec, isWin = state.histView, nil, false
        if v == "current" then
            rec = WD:CurrentRecord()
        elseif type(v) == "number" then
            rec = WD:HistoryRecord(v)
        elseif type(v) == "string" and v:sub(1, 1) == "w" then
            rec = WD:WindowRecord(tonumber(v:sub(2)) or 24); isWin = true
        end
        if rec then
            ui.scroll:Hide()
            ui.back:Show()
            ui.info:Show()
            RenderDetail(rec, isWin)
        else
            state.histView = nil
            ui.info:Hide()
            ui.scroll:Show()
            ui.back:Hide()
            n = RenderHist()
            contentH = math.max(1, n * ROW_H)
        end
    else
        ui.scroll:Hide()
        ui.back:Hide()
        ui.info:Show()
        HideInfo()
        if state.tab == "pvp" then RenderPvP(WD:Aggregate(state.period)) else RenderXP(WD:Aggregate("session")) end
    end

    if not showSlots then
        for i = 1, #slots do slots[i]:Hide() end
    end
    for i = n + 1, #rows do rows[i]:Hide() end
    SetChipVisibility()

    ui.content:SetHeight(contentH)
    local maxScroll = math.max(0, contentH - ui.scroll:GetHeight())
    if ui.scroll:GetVerticalScroll() > maxScroll then ui.scroll:SetVerticalScroll(maxScroll) end
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
-- Aviso na tela (drop raro / mob raro)
---------------------------------------------------------------------------
local toast
local TOAST_COLORS = { drop = C.gold, rare = C.blue, rarekill = C.green }

local function CreateToast()
    local t = CreateFrame("Frame", "WatchdogToast", UIParent, BT)
    t:SetSize(350, 50)
    t:SetPoint("TOP", UIParent, "TOP", 0, -220)
    t:SetFrameStrata("FULLSCREEN_DIALOG")
    Flat(t, C.bg, C.border, 0.95)
    t:Hide()

    t.accent = t:CreateTexture(nil, "ARTWORK")
    t.accent:SetPoint("TOPLEFT", 1, -1)
    t.accent:SetPoint("BOTTOMLEFT", 1, 1)
    t.accent:SetWidth(4)

    t.icon = t:CreateTexture(nil, "ARTWORK")
    t.icon:SetSize(34, 34)
    t.icon:SetPoint("LEFT", 14, 0)
    t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    t.title = FS(t, 11, C.gold, "LEFT")
    t.title:SetPoint("TOPLEFT", 58, -9)
    t.text = FS(t, 14, C.text, "LEFT")
    t.text:SetPoint("BOTTOMLEFT", 58, 9)
    t.text:SetPoint("RIGHT", t, "RIGHT", -10, 0)
    t.text:SetWordWrap(false)

    t.elapsed = 0
    t:SetScript("OnUpdate", function(self, dt)
        self.elapsed = self.elapsed + dt
        if self.elapsed < 4.5 then
            self:SetAlpha(1)
        elseif self.elapsed < 5.5 then
            self:SetAlpha(1 - (self.elapsed - 4.5))
        else
            self:Hide()
        end
    end)
    return t
end

function WD:ShowAlert(kind, title, text, icon)
    if not toast then toast = CreateToast() end
    local col = TOAST_COLORS[kind] or C.gold
    toast.accent:SetColorTexture(col[1], col[2], col[3], 1)
    toast.title:SetText(title or "")
    toast.title:SetTextColor(col[1], col[2], col[3])
    toast.text:SetText(text or "")
    if icon then
        toast.icon:SetTexture(icon)
    else
        toast.icon:SetTexture(MEDIA .. "emblem_icon")
    end
    toast.elapsed = 0
    toast:SetAlpha(1)
    toast:Show()
    print("|cffffd100Watchdog:|r " .. (title or "") .. " " .. (text or ""))
    if WatchdogDB.alerts and WatchdogDB.alerts.sound then
        WD:PlayAlertSound(kind)
    end
end

---------------------------------------------------------------------------
-- Relatorio para colar
---------------------------------------------------------------------------
local function BuildReport()
    local s = WatchdogCharDB.session
    local start = WatchdogCharDB.sessionStart or time()
    local elapsed = math.max(1, time() - start)
    local data = WD:Aggregate("session")
    local xp = WD:GetXPStats()
    local total = WD:BucketValue(data)
    local money = data.money or 0
    local kills = SessionKills(data)
    local p = data.pvp

    local lines = {}
    lines[#lines + 1] = string.format(L.report_header, date("%d/%m %H:%M", start), FormatDuration(elapsed))
    lines[#lines + 1] = string.format(L.report_kills,
        Num(kills), Num(xp.sessionXP), Num(math.floor(xp.perHour)), xp.levels or 0)
    lines[#lines + 1] = string.format(L.report_gold,
        WD:CoinText(total), WD:CoinText(total / elapsed * 3600), WD:CoinText(money), WD:CoinText(total - money))
    if (p.kills or 0) > 0 or (p.deaths or 0) > 0 or (p.honor or 0) > 0 then
        lines[#lines + 1] = string.format(L.report_pvp, p.kills, p.deaths, Num(p.honor))
    end

    local entries = {}
    for name, m in pairs(data.mobs) do
        local v = WD:MobValue(m)
        entries[#entries + 1] = { name = name, kills = m.kills or 0, value = v }
    end
    table.sort(entries, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return a.kills > b.kills
    end)
    if #entries > 0 then
        lines[#lines + 1] = L.report_topmobs
        for i = 1, math.min(5, #entries) do
            local e = entries[i]
            lines[#lines + 1] = string.format(L.report_mobline, i, e.name, e.kills,
                WD:CoinText(e.value), WD:CoinText(e.kills > 0 and e.value / e.kills or 0))
        end
    end
    return table.concat(lines, "\n")
end

local reportFrame
function WD:ShowReport()
    if not reportFrame then
        local f = CreateFrame("Frame", "WatchdogReportFrame", UIParent, BT)
        f:SetSize(500, 290)
        f:SetPoint("CENTER")
        Flat(f, C.bg, C.border, 0.98)
        f:SetFrameStrata("DIALOG")
        f:SetToplevel(true)
        f:HookScript("OnShow", function(self) self:Raise() end)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:Hide()
        tinsert(UISpecialFrames, "WatchdogReportFrame")

        local title = FS(f, 16, C.text, "LEFT")
        title:SetPoint("TOPLEFT", 18, -16)
        title:SetText(L.report_title)
        local hint = FS(f, 11, C.dim, "LEFT")
        hint:SetPoint("TOPLEFT", 18, -40)
        hint:SetText(L.report_hint)

        local box = CreateFrame("Frame", nil, f, BT)
        box:SetPoint("TOPLEFT", 16, -62)
        box:SetPoint("BOTTOMRIGHT", -16, 52)
        Flat(box, C.card, C.border, 1)

        local eb = CreateFrame("EditBox", nil, box)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(true)
        eb:SetFont(FONT, 12, "")
        eb:SetTextColor(C.text[1], C.text[2], C.text[3])
        eb:SetPoint("TOPLEFT", 8, -8)
        eb:SetPoint("BOTTOMRIGHT", -8, 8)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        f.edit = eb

        local close = MakeChip(f, L.btn_close, 90)
        close:SetPoint("BOTTOMRIGHT", -16, 16)
        close:SetScript("OnClick", function() f:Hide() end)
        local refresh = MakeChip(f, L.btn_refresh, 90)
        refresh:SetPoint("RIGHT", close, "LEFT", -8, 0)
        refresh:SetScript("OnClick", function()
            f.edit:SetText(BuildReport())
            f.edit:HighlightText()
            f.edit:SetFocus()
        end)

        reportFrame = f
    end
    reportFrame:Show()
    reportFrame.edit:SetText(BuildReport())
    reportFrame.edit:HighlightText()
    reportFrame.edit:SetFocus()
end

---------------------------------------------------------------------------
-- Lista premium: nameplates destacadas + gerenciador
---------------------------------------------------------------------------
-- Cor do nome na nameplate: pinta o proprio nome da Blizzard (so quando o mob esta na lista).
-- Nao ha gancho em CompactUnitFrame_UpdateName (rodava codigo do addon em todos os frames);
-- em vez disso a cor e refeita a cada 0.5s e quando a nameplate aparece.
local function NameplateNameFS(np)
    local uf = np and np.UnitFrame
    if not uf then return nil end
    if uf.name then return uf.name end
    if uf.NameText then return uf.NameText end
    if uf.Name then return uf.Name end
    -- Fallback: procura o primeiro FontString do frame (nome flutuante).
    if uf.GetRegions then
        for _, r in ipairs({ uf:GetRegions() }) do
            if r and r.GetObjectType and r:GetObjectType() == "FontString" then
                return r
            end
        end
    end
    return nil
end

-- nameplates com nome na lista: [np] = { fs = texto, col = cor }. Repintadas a cada quadro
-- (a Blizzard reescreve o nome em branco de tempos em tempos; sem gancho, so repintando rapido some a piscada).
local watchedPlates = {}
local paintFrame = CreateFrame("Frame")
paintFrame:SetScript("OnUpdate", function()
    for np, e in pairs(watchedPlates) do
        if np.IsShown and not np:IsShown() then
            watchedPlates[np] = nil
        else
            pcall(e.fs.SetVertexColor, e.fs, e.col[1], e.col[2], e.col[3])
        end
    end
end)

function WD:ColorOneNameplate(unit, np)
    if not unit or not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then return end
    np = np or C_NamePlate.GetNamePlateForUnit(unit)
    if not np then return end
    local kind = WD:IsUnitWatched(unit)
    if not kind then watchedPlates[np] = nil; return end   -- fora da lista: nao encosta na nameplate
    local fs = NameplateNameFS(np)
    if not fs or not fs.SetVertexColor then return end
    local col = (kind == "pvp") and (WatchdogDB.watchColorPvp or C.purple) or (WatchdogDB.watchColor or C.blue)
    watchedPlates[np] = { fs = fs, col = col }
    fs:SetVertexColor(col[1], col[2], col[3])
end

function WD:OnNameplateAdded(unit)
    pcall(WD.ColorOneNameplate, WD, unit)
end

function WD:RefreshNameplates()
    if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
    local ok, list = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(list) ~= "table" then return end
    local active = {}
    for _, np in ipairs(list) do
        active[np] = true
        local unit = WD.Clean(np.namePlateUnitToken or (np.UnitFrame and np.UnitFrame.unit))
        if type(unit) == "string" then pcall(WD.ColorOneNameplate, WD, unit, np) end
    end
    for np in pairs(watchedPlates) do
        if not active[np] then watchedPlates[np] = nil end
    end
end

-- Liga nomes de inimigos e joga o alcance das nameplates no maximo,
-- para o nome azul aparecer de mais longe possivel.
function WD:MaxNameplateRange()
    -- SetCVar de nameplate e protegido em combate: nunca chamar la
    -- (causaria ADDON_ACTION_FORBIDDEN). Adia para quando sair do combate.
    if InCombatLockdown and InCombatLockdown() then
        WD._cvarPending = true
        return
    end
    WD._cvarPending = false
    local function set(k, v)
        local cur = GetCVar and GetCVar(k)
        if cur ~= nil and tonumber(cur) == tonumber(v) then return end
        pcall(SetCVar, k, v)
    end
    set("nameplateShowEnemies", 1)
    set("nameplateMaxDistance", 41)
    if WD.RefreshNameplates then WD:RefreshNameplates() end
end

-- (removido) O gancho em CompactUnitFrame_UpdateName causava taint; ver comentario acima.
local function HookNameplateName() end

-- Aba BLACK LIST: duas colunas (PvE / PvP), nomes vistos recentemente e lista.
local SEEN_ROWS, LIST_ROWS = 4, 8
function BuildBlackPanel(host)
    local left = SIDE_W + PAD
    local p = CreateFrame("Frame", nil, host)
    p:SetPoint("TOPLEFT", host, "TOPLEFT", left, -76)
    p:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -PAD, PAD)
    p:Hide()

    local hint = FS(p, 11, C.dim, "LEFT")
    hint:SetPoint("TOPLEFT", p, "TOPLEFT", 2, 0)
    hint:SetWidth(CONTENT_W - 4)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.black_hint)

    -- Botao da macro (a macro leva so os nomes marcados com "M" na lista)
    local macroChip = MakeChip(p, L.black_macro, 110)
    macroChip:SetPoint("TOPLEFT", p, "TOPLEFT", 2, -37)
    macroChip:SetScript("OnClick", function()
        local ok, why = WD:PickupTargetMacro()
        if ok then
            print("|cff7ec8ffWatchdog:|r " .. L.black_macro_ok .. (WD.macroDropped and WD.macroDropped > 0 and (" " .. string.format(L.black_macro_cut, WD.macroDropped)) or ""))
        else
            print("|cff7ec8ffWatchdog:|r " .. (why == "combat" and L.black_macro_combat or L.black_macro_full))
        end
    end)
    local macroHint = FS(p, 11, C.dim, "LEFT")
    macroHint:SetPoint("LEFT", macroChip, "RIGHT", 10, 0)
    macroHint:SetText(L.black_macro_hint)

    local colW = math.floor((CONTENT_W - 12) / 2)
    p.cols = {}
    for i, kind in ipairs({ "pve", "pvp" }) do
        local accent = kind == "pvp" and C.purple or C.blue
        local col = CreateFrame("Frame", nil, p, BT)
        col:SetPoint("TOPLEFT", p, "TOPLEFT", (i - 1) * (colW + 12), -66)
        col:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", (i - 1) * (colW + 12), 0)
        col:SetWidth(colW)
        Flat(col, C.card, C.border, 0.9)
        col.kind, col.offset, col.pick = kind, 0, nil

        local bar = col:CreateTexture(nil, "ARTWORK")
        bar:SetPoint("TOPLEFT", 1, -1); bar:SetPoint("TOPRIGHT", -1, -1); bar:SetHeight(2)
        bar:SetColorTexture(accent[1], accent[2], accent[3], 1)

        local head = FS(col, 13, C.text, "LEFT")
        head:SetPoint("TOPLEFT", 10, -10)
        head:SetText(kind == "pvp" and L.black_pvp or L.black_pve)

        local box = CreateFrame("Frame", nil, col, BT)
        box:SetPoint("TOPLEFT", 8, -30)
        box:SetSize(colW - 8 - 8 - 56, 24)
        Flat(box, C.bg, C.border, 1)
        local eb = CreateFrame("EditBox", nil, box)
        eb:SetAutoFocus(false)
        eb:SetFont(FONT, 12, "")
        eb:SetTextColor(C.text[1], C.text[2], C.text[3])
        eb:SetPoint("TOPLEFT", 6, -2); eb:SetPoint("BOTTOMRIGHT", -6, 2)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        col.edit = eb
        local function doAdd()
            local n = eb:GetText()
            if WD:AddWatch(n, kind) then eb:SetText(""); eb:ClearFocus() end
            if WD.RefreshBlack then WD:RefreshBlack() end
        end
        eb:SetScript("OnEnterPressed", doAdd)
        local add = MakeChip(col, L.watch_add, 50)
        add:SetPoint("TOPRIGHT", -8, -30)
        add:SetScript("OnClick", doAdd)

        local seenLbl = FS(col, 11, C.dim, "LEFT")
        seenLbl:SetPoint("TOPLEFT", 10, -62)
        seenLbl:SetText(L.black_seen)
        col.seenEmpty = FS(col, 11, C.mute, "LEFT")
        col.seenEmpty:SetPoint("TOPLEFT", 12, -80)
        col.seenEmpty:SetText(L.black_seen_empty)
        col.seenRows = {}
        for r = 1, SEEN_ROWS do
            local b = CreateFrame("Button", nil, col)
            b:SetHeight(20)
            b:SetPoint("TOPLEFT", 8, -78 - (r - 1) * 20)
            b:SetPoint("TOPRIGHT", -8, -78 - (r - 1) * 20)
            b.hl = b:CreateTexture(nil, "HIGHLIGHT"); b.hl:SetAllPoints(); b.hl:SetColorTexture(1, 1, 1, 0.06)
            b.text = FS(b, 12, C.text, "LEFT")
            b.text:SetPoint("LEFT", 6, 0)
            b:SetScript("OnClick", function(self)
                if self.name then eb:SetText(self.name); eb:ClearFocus() end
            end)
            b:Hide()
            col.seenRows[r] = b
        end

        col.listLbl = FS(col, 11, C.dim, "LEFT")
        col.listLbl:SetPoint("TOPLEFT", 10, -166)
        col.empty = FS(col, 11, C.mute, "LEFT")
        col.empty:SetPoint("TOPLEFT", 12, -184)
        col.empty:SetText(L.black_empty)
        col.more = FS(col, 10, C.mute, "RIGHT")
        col.more:SetPoint("TOPRIGHT", -10, -167)
        col.rows = {}
        for r = 1, LIST_ROWS do
            local row = CreateFrame("Frame", nil, col)
            row:SetHeight(20)
            row:SetPoint("TOPLEFT", 8, -182 - (r - 1) * 20)
            row:SetPoint("TOPRIGHT", -8, -182 - (r - 1) * 20)
            row.label = FS(row, 12, accent, "LEFT")
            row.label:SetPoint("LEFT", 6, 0)
            row.label:SetPoint("RIGHT", -80, 0)
            row.label:SetWordWrap(false)
            local x = CreateFrame("Button", nil, row)
            x:SetSize(20, 20)
            x:SetPoint("RIGHT", 0, 0)
            x.text = FS(x, 13, C.mute, "CENTER")
            x.text:SetPoint("CENTER", 0, 1)
            x.text:SetText("x")
            x:SetScript("OnEnter", function(self) self.text:SetTextColor(C.red[1], C.red[2], C.red[3]) end)
            x:SetScript("OnLeave", function(self) self.text:SetTextColor(C.mute[1], C.mute[2], C.mute[3]) end)
            x:SetScript("OnClick", function()
                if row.name then WD:RemoveWatch(row.name, kind); if WD.RefreshBlack then WD:RefreshBlack() end end
            end)
            local m = CreateFrame("Button", nil, row)
            m:SetSize(28, 20)
            m:SetPoint("RIGHT", x, "LEFT", -2, 0)
            m.text = FS(m, 11, C.mute, "CENTER")
            m.text:SetPoint("CENTER", 0, 0)
            m:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(L.black_macro_tip); GameTooltip:Show()
            end)
            m:SetScript("OnLeave", function() GameTooltip:Hide() end)
            m:SetScript("OnClick", function()
                if row.name then WD:ToggleMacroName(row.name); if WD.RefreshBlack then WD:RefreshBlack() end end
            end)
            row.m = m
            local am = CreateFrame("Button", nil, row)
            am:SetSize(28, 20)
            am:SetPoint("RIGHT", m, "LEFT", -2, 0)
            am.text = FS(am, 11, C.mute, "CENTER")
            am.text:SetPoint("CENTER", 0, 0)
            am:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(L.black_alert_tip); GameTooltip:Show()
            end)
            am:SetScript("OnLeave", function() GameTooltip:Hide() end)
            am:SetScript("OnClick", function()
                if row.name then WD:ToggleAlertName(row.name); if WD.RefreshBlack then WD:RefreshBlack() end end
            end)
            row.a = am
            row:Hide()
            col.rows[r] = row
        end
        col:EnableMouseWheel(true)
        col:SetScript("OnMouseWheel", function(self, delta)
            local n = #WD:WatchList(kind)
            self.offset = math.max(0, math.min(math.max(0, n - LIST_ROWS), self.offset - delta))
            if WD.RefreshBlack then WD:RefreshBlack() end
        end)
        p.cols[kind] = col
    end

    function WD:RefreshBlack()
        if not p:IsShown() then return end
        for kind, col in pairs(p.cols) do
            local list = WD:WatchList(kind)
            col.listLbl:SetText(string.format(L.black_list, #list))
            col.offset = math.max(0, math.min(math.max(0, #list - LIST_ROWS), col.offset))
            for r = 1, LIST_ROWS do
                local name = list[col.offset + r]
                local row = col.rows[r]
                if name then
                    row.name = name; row.label:SetText(name); row:Show()
                    local on = WD:InMacro(name)
                    row.m.text:SetText(on and "M" or "+M")
                    local c = on and C.green or C.mute
                    row.m.text:SetTextColor(c[1], c[2], c[3])
                    local aon = WD:InAlert(name)
                    row.a.text:SetText(aon and "A" or "A+")
                    local ac = aon and C.gold or C.mute
                    row.a.text:SetTextColor(ac[1], ac[2], ac[3])
                else row.name = nil; row:Hide() end
            end
            col.empty:SetShown(#list == 0)
            col.more:SetText(#list > LIST_ROWS and L.black_more or "")
            -- vistos recentemente (sem os que ja estao na lista)
            local shown = 0
            for _, name in ipairs(WD:SeenList(kind)) do
                if shown >= SEEN_ROWS then break end
                if not WD:IsWatched(name, kind) then
                    shown = shown + 1
                    local b = col.seenRows[shown]
                    b.name = name
                    b.text:SetText(name)
                    b:Show()
                end
            end
            for r = shown + 1, SEEN_ROWS do col.seenRows[r].name = nil; col.seenRows[r]:Hide() end
            col.seenEmpty:SetShown(shown == 0)
        end
    end
    local acc = 0
    p:SetScript("OnUpdate", function(_, el)
        acc = acc + el
        if acc >= 1 then acc = 0; WD:RefreshBlack() end
    end)
    p:SetScript("OnShow", function() WD:RefreshBlack() end)
    return p
end

-- Compatibilidade: antigo /wd premium abre a aba Black list.
function WD:ShowWatchList() WD:Toggle("black") end

---------------------------------------------------------------------------
-- Janela
---------------------------------------------------------------------------
local function SavePosition(f)
    local point, _, relPoint, x, y = f:GetPoint()
    WatchdogDB.pos = { point, relPoint, x, y }
end

local function CreateSidebar(f)
    local side = CreateFrame("Frame", nil, f)
    side:SetPoint("TOPLEFT", 1, -1)
    side:SetPoint("BOTTOMLEFT", 1, 1)
    side:SetWidth(SIDE_W)

    local line = side:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPRIGHT")
    line:SetPoint("BOTTOMRIGHT")
    line:SetWidth(1)
    line:SetColorTexture(1, 1, 1, 0.07)

    -- Logo (texto)
    local wordmark = side:CreateTexture(nil, "ARTWORK")
    wordmark:SetTexture(MEDIA .. "wordmark")
    wordmark:SetSize(136, 17)
    wordmark:SetPoint("TOPLEFT", 17, -24)

    -- Marca d'agua do emblema
    local mark = side:CreateTexture(nil, "BACKGROUND")
    mark:SetTexture(MEDIA .. "emblem")
    mark:SetSize(100, 100)
    mark:SetPoint("BOTTOM", side, "BOTTOM", 0, 100)
    mark:SetAlpha(0.14)

    -- Navegacao
    ui.tabs = {}
    local prev
    for _, t in ipairs(GROUPS) do
        local key = t.key
        local b = CreateFrame("Button", nil, side)
        b:SetSize(SIDE_W - 20, 32)
        if prev then
            b:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -3)
        else
            b:SetPoint("TOPLEFT", 10, -62)
        end
        b.hl = b:CreateTexture(nil, "HIGHLIGHT")
        b.hl:SetAllPoints()
        b.hl:SetColorTexture(1, 1, 1, 0.05)
        b.sel = b:CreateTexture(nil, "BACKGROUND")
        b.sel:SetAllPoints()
        b.sel:SetColorTexture(1, 1, 1, 0.06)
        b.sel:Hide()
        b.bar = b:CreateTexture(nil, "ARTWORK")
        b.bar:SetPoint("TOPLEFT")
        b.bar:SetPoint("BOTTOMLEFT")
        b.bar:SetWidth(3)
        b.bar:SetColorTexture(C.red[1], C.red[2], C.red[3], 1)
        b.bar:Hide()
        b.text = FS(b, 14, C.mute, "LEFT", "")
        b.text:SetPoint("LEFT", 16, 0)
        b.text:SetText(L[t.labelK])
        b.SetActive = function(self, on)
            self.active = on
            self.sel:SetShown(on)
            self.bar:SetShown(on)
            if on then self.text:SetTextColor(1, 1, 1) else self.text:SetTextColor(C.mute[1], C.mute[2], C.mute[3]) end
        end
        b:SetScript("OnClick", function()
            state.tab = (key == "pve") and (state.lastPve or "pve") or key
            state.mob = nil
            ui.scroll:SetVerticalScroll(0)
            WD:Render()
        end)
        b:SetScript("OnEnter", function(self)
            if not self.active then self.text:SetTextColor(0.82, 0.84, 0.86) end
        end)
        b:SetScript("OnLeave", function(self)
            if not self.active then self.text:SetTextColor(C.mute[1], C.mute[2], C.mute[3]) end
        end)
        ui.tabs[key] = b
        prev = b
    end

    -- Rodape: Nova sessao | Comandos (lado a lado)
    local half = math.floor((SIDE_W - 26) / 2)
    local newSession = MakeChip(side, L.chip_newsession, half)
    newSession:SetPoint("BOTTOMLEFT", side, "BOTTOMLEFT", 10, 46)
    newSession.text:SetFont(FONT, 10, "")
    newSession:SetScript("OnClick", function() WD:StartNewSession() end)

    local commands = MakeChip(side, L.chip_commands, half)
    commands:SetPoint("LEFT", newSession, "RIGHT", 6, 0)
    commands.text:SetFont(FONT, 10, "")
    commands:SetScript("OnClick", function() if WD.ToggleCommands then WD:ToggleCommands() end end)

    local dot = side:CreateTexture(nil, "ARTWORK")
    dot:SetSize(7, 7)
    dot:SetPoint("BOTTOMLEFT", 20, 17)
    dot:SetColorTexture(0.2, 0.83, 0.6, 1)
    local ver = FS(side, 11, C.dim, "LEFT")
    ver:SetPoint("LEFT", dot, "RIGHT", 7, 0)
    ver:SetText("Rastreando  ·  v" .. (WD.version or ""))
end

local function CreateMainFrame()
    local f = CreateFrame("Frame", "WatchdogFrame", UIParent, BT)
    f:SetSize(FRAME_W, FRAME_H)
    local pos = WatchdogDB.pos
    if pos then
        f:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        f:SetPoint("CENTER")
    end
    Flat(f, C.bg, C.border, 0.97)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:HookScript("OnShow", function(self) self:Raise() end)
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

    CreateSidebar(f)

    local left = SIDE_W + PAD

    -- Fechar
    local close = CreateFrame("Button", nil, f)
    close:SetSize(26, 26)
    close:SetPoint("TOPRIGHT", -10, -10)
    close.text = FS(close, 16, C.mute, "CENTER")
    close.text:SetPoint("CENTER", 0, 1)
    close.text:SetText("x")
    close:SetScript("OnEnter", function(self) self.text:SetTextColor(C.red[1], C.red[2], C.red[3]) end)
    close:SetScript("OnLeave", function(self) self.text:SetTextColor(C.mute[1], C.mute[2], C.mute[3]) end)
    close:SetScript("OnClick", function() f:Hide() end)

    -- Relogio da sessao ativa
    ui.timerLabel = FS(f, 9, C.mute, "RIGHT")
    ui.timerLabel:SetPoint("TOPRIGHT", f, "TOPRIGHT", -48, -16)
    ui.timerLabel:SetText(L.session_active)
    ui.timer = FS(f, 17, C.text, "RIGHT", "")
    ui.timer:SetPoint("TOPRIGHT", f, "TOPRIGHT", -48, -28)
    -- Botao "Sessao ativa": abre os dados da sessao atual
    ui.activeChip = MakeChip(f, L.btn_active, 96)
    ui.activeChip:SetPoint("TOPRIGHT", f, "TOPRIGHT", -140, -14)
    ui.activeChip:SetScript("OnClick", function()
        state.tab = "hist"; state.histView = "current"; state.mob = nil
        ui.scroll:SetVerticalScroll(0)
        WD:Render()
    end)
    local acc = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc >= 1 then
            acc = 0
            UpdateTimer()
        end
    end)

    -- Cabecalho
    ui.title = FS(f, 22, C.text, "LEFT", "")
    ui.title:SetPoint("TOPLEFT", f, "TOPLEFT", left, -22)

    ui.summary = FS(f, 12, C.dim, "LEFT")
    ui.summary:SetPoint("TOPLEFT", f, "TOPLEFT", left, -52)
    ui.summary:SetPoint("RIGHT", f, "RIGHT", -110, 0)
    ui.summary:SetWordWrap(false)

    ui.back = MakeChip(f, L.back, 70)
    ui.back:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -46)
    ui.back:SetScript("OnClick", function() state.mob = nil; state.histView = nil; ui.scroll:SetVerticalScroll(0); WD:Render() end)

    -- Sub-menu do grupo PvE (Mobs / EXP / Inventario / Historico) + Relatorio
    ui.subChips = {}
    local sprev
    for _, sdef in ipairs(PVE_SUBS) do
        local b = MakeChip(f, L[sdef.labelK], 84)
        b.key = sdef.key
        if sprev then b:SetPoint("LEFT", sprev, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", f, "TOPLEFT", left, -76) end
        b:SetScript("OnClick", function()
            state.tab = sdef.key
            state.mob = nil
            if sdef.key == "hist" then state.histView = nil end
            ui.scroll:SetVerticalScroll(0)
            WD:Render()
        end)
        ui.subChips[#ui.subChips + 1] = b
        sprev = b
    end
    -- Historico: lista de sessoes ou janela por tempo
    ui.histChips = {}
    local hprev
    for _, hd in ipairs({ { "list", "win_sessions" }, { "w24", "win_24h" }, { "w168", "win_7d" }, { "w720", "win_30d" } }) do
        local b = MakeChip(f, L[hd[2]], 84)
        b.key = hd[1]
        if hprev then b:SetPoint("LEFT", hprev, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", f, "TOPLEFT", left, -106) end
        b:SetScript("OnClick", function()
            state.histView = (hd[1] ~= "list") and hd[1] or nil
            ui.scroll:SetVerticalScroll(0)
            WD:Render()
        end)
        b:Hide()
        ui.histChips[#ui.histChips + 1] = b
        hprev = b
    end

    -- Periodos (PvE / PvP / EXP)
    ui.periodButtons = {}
    local prev
    for _, p in ipairs(PERIODS) do
        local b = MakeChip(f, L[p.labelK], 68)
        b.key = p.key
        if prev then
            b:SetPoint("LEFT", prev, "RIGHT", 6, 0)
        else
            b:SetPoint("TOPLEFT", f, "TOPLEFT", left, -106)
        end
        b:SetScript("OnClick", function()
            state.period = p.key
            WD:Render()
        end)
        ui.periodButtons[#ui.periodButtons + 1] = b
        prev = b
    end

    -- Visao do inventario (Bolsa / Lista)
    ui.viewButtons = {}
    prev = nil
    for _, v in ipairs(INV_VIEWS) do
        local b = MakeChip(f, L[v.labelK], 80)
        b.key = v.key
        if prev then
            b:SetPoint("LEFT", prev, "RIGHT", 6, 0)
        else
            b:SetPoint("TOPLEFT", f, "TOPLEFT", left, -106)
        end
        b:SetScript("OnClick", function()
            state.invView = v.key
            ui.scroll:SetVerticalScroll(0)
            WD:Render()
        end)
        ui.viewButtons[#ui.viewButtons + 1] = b
        prev = b
    end

    -- Contornos vendor x AH (so na aba Inventario)
    ui.borderBtn = MakeChip(f, "", 150)
    ui.borderBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -106)
    ui.borderBtn:SetScript("OnClick", function() WD:ToggleBorders(); WD:Render() end)
    ui.borderBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText(L.inv_borders_tip, nil, nil, nil, nil, true); GameTooltip:Show()
    end)
    ui.borderBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Ordenacao da lista de mobs (PvE)
    ui.sortBtn = MakeChip(f, L[SORTS[1].labelK], 132)
    ui.sortBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -106)
    -- Lista de opcoes: abre ao clicar, escolhe-se direto (sem trocar no escuro)
    local sp = CreateFrame("Frame", nil, f, BT)
    sp:SetFrameLevel((tonumber(f:GetFrameLevel()) or 10) + 60)     -- acima do resto da janela, mesma camada (sem camada especial)
    sp:SetSize(150, #SORTS * 26 + 8)
    sp:SetPoint("TOPRIGHT", ui.sortBtn, "BOTTOMRIGHT", 0, -2)
    Flat(sp, C.bg, C.border, 1)
    sp:EnableMouse(true)
    sp:Hide()
    ui.sortPop = sp
    -- fecha sozinha quando o mouse sai da lista (e do botao Sort) por um instante
    local away = 0
    local function Over(fr)
        if fr and fr.IsMouseOver then return fr:IsMouseOver() end
        if MouseIsOver then return MouseIsOver(fr) end
        return true      -- sem como saber: nao fecha sozinha (fecha ao escolher ou clicando no Sort)
    end
    sp:SetScript("OnUpdate", function(self, el)
        local ok, over = pcall(function() return Over(self) or Over(ui.sortBtn) end)
        if not ok then self:SetScript("OnUpdate", nil); return end   -- nunca repetir erro a cada quadro
        if over then away = 0
        else
            away = away + el
            if away > 0.5 then self:Hide() end
        end
    end)
    sp:SetScript("OnShow", function() away = 0 end)
    local opts = {}
    for i, s in ipairs(SORTS) do
        local o = CreateFrame("Button", nil, sp, BT)
        o:SetFrameLevel((tonumber(sp:GetFrameLevel()) or 70) + 2)
        o:EnableMouse(true)
        o:RegisterForClicks("LeftButtonUp")
        o:SetSize(142, 24)
        o:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 26)
        o.text = FS(o, 12, C.dim, "LEFT")
        o.text:SetPoint("LEFT", 10, 0)
        o.text:SetText((L[s.labelK] or s.key):gsub("^[^:]+:%s*", ""))
        o:SetScript("OnEnter", function(self) Flat(self, C.tile, C.border, 1) end)
        o:SetScript("OnLeave", function(self)
            if state.sort == s.key then Flat(self, C.tile, C.red, 1) else Flat(self, C.bg, C.bg, 0) end
        end)
        local function Pick()
            if state.sort == s.key and not sp:IsShown() then return end
            state.sort = s.key
            sp:Hide()
            ui.scroll:SetVerticalScroll(0)
            WD:Render()
        end
        o:SetScript("OnClick", Pick)
        o:SetScript("OnMouseUp", Pick)      -- reserva: garante o clique mesmo que o OnClick nao dispare
        opts[i] = o
    end
    local function PaintPop()
        for i, s in ipairs(SORTS) do
            local o = opts[i]
            if state.sort == s.key then
                Flat(o, C.tile, C.red, 1); o.text:SetTextColor(1, 1, 1)
            else
                Flat(o, C.bg, C.bg, 0); o.text:SetTextColor(C.dim[1], C.dim[2], C.dim[3])
            end
        end
    end
    ui.sortBtn:SetScript("OnClick", function()
        if sp:IsShown() then sp:Hide() else PaintPop(); sp:Show() end
    end)

    -- Lista / bolsa com rolagem (sem barra: use a roda do mouse).
    ui.scroll = CreateFrame("ScrollFrame", "WatchdogScroll", f)
    ui.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", left, -146)
    ui.scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD + 38)
    ui.content = CreateFrame("Frame", nil, ui.scroll)
    ui.content:SetSize(CONTENT_W, 1)
    ui.scroll:SetScrollChild(ui.content)
    ui.scroll:EnableMouseWheel(true)
    ui.scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, contentH - self:GetHeight())
        local v = self:GetVerticalScroll() - delta * ROW_H * 2
        self:SetVerticalScroll(math.max(0, math.min(maxScroll, v)))
    end)

    -- Area dos tiles (PvP / EXP)
    ui.info = CreateFrame("Frame", nil, f)
    ui.info:SetPoint("TOPLEFT", f, "TOPLEFT", left, -146)
    ui.info:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD + 38)

    -- Barra de XP
    ui.xpLabel = FS(ui.info, 13, C.dim, "LEFT")
    ui.xpLabel:SetPoint("TOPLEFT", ui.info, "TOPLEFT", 2, -82)
    ui.xpPct = FS(ui.info, 11, C.dim, "RIGHT")
    ui.xpPct:SetPoint("TOPRIGHT", ui.info, "TOPRIGHT", -2, -83)
    ui.xpBar = CreateFrame("Frame", nil, ui.info, BT)
    ui.xpBar:SetSize(CONTENT_W, 16)
    ui.xpBar:SetPoint("TOPLEFT", ui.info, "TOPLEFT", 0, -102)
    Flat(ui.xpBar, C.card, C.border, 1)
    ui.xpFill = ui.xpBar:CreateTexture(nil, "ARTWORK")
    ui.xpFill:SetPoint("TOPLEFT", 1, -1)
    ui.xpFill:SetPoint("BOTTOMLEFT", 1, 1)
    ui.xpFill:SetColorTexture(C.purple[1], C.purple[2], C.purple[3], 1)
    ui.info:Hide()

    -- Rodape: ouro por hora da sessao
    local foot = CreateFrame("Frame", nil, f, BT)
    ui.foot = foot
    foot:SetHeight(30)
    foot:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", left, PAD)
    foot:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
    Flat(foot, C.card, C.border, 0.9)
    local goldLine = foot:CreateTexture(nil, "ARTWORK")
    goldLine:SetPoint("TOPLEFT", 1, -1)
    goldLine:SetPoint("BOTTOMLEFT", 1, 1)
    goldLine:SetWidth(3)
    goldLine:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 1)
    ui.gph = FS(foot, 14, C.text, "LEFT")
    ui.gph:SetPoint("LEFT", 14, 0)
    ui.gphTotal = FS(foot, 11, C.dim, "RIGHT")
    ui.gphTotal:SetPoint("RIGHT", -12, 0)

    frame = f
end

function WD:Toggle(tab)
    if not frame then CreateMainFrame() end
    -- Primeira abertura depois de logar (por /wd ou minimapa) cai na tela de EXP.
    local db = WatchdogCharDB
    local first = db and db.openedStamp ~= db.loginStamp
    if tab then
        state.tab = tab
        state.mob = nil
        if db then db.openedStamp = db.loginStamp end
        frame:Show()
        WD:Render()
        return
    end
    if not frame:IsShown() and first then
        state.tab = "xp"
        state.mob = nil
    end
    if not frame:IsShown() and db then db.openedStamp = db.loginStamp end
    frame:SetShown(not frame:IsShown())
end

---------------------------------------------------------------------------
-- Barras flutuantes (/wd goldbar, /wd expbar)
---------------------------------------------------------------------------
local bars = {}

local BAR_DEFS = {
    gold = {
        accent = C.gold, w = 270, defaultY = -120, nameK = "bar_gold",
        update = function(b)
            local perHour = SessionGoldPerHour()
            b.main:SetText(Coins(perHour) .. Gray(L.per_hour))
            local start = WatchdogCharDB.sessionStart
            b.side:SetText(start and FormatClock(time() - start) or "")
        end,
    },
    exp = {
        accent = C.purple, w = 250, defaultY = -160, nameK = "bar_exp",
        update = function(b)
            local s = WD:GetXPStats()
            b.main:SetText(White(Num(math.floor(s.perHour))) .. Gray(L.xp_hour_suffix))
            if s.maxLevel then
                b.side:SetText("")
                b.fill:SetWidth(math.max(1, b:GetWidth() - 2))
            else
                b.side:SetText(s.timeToLevel and (L.ups_in .. FormatDuration(s.timeToLevel)) or "")
                local frac = s.max > 0 and math.min(1, s.cur / s.max) or 0
                b.fill:SetWidth(math.max(1, (b:GetWidth() - 2) * frac))
            end
        end,
    },
    sgold = {
        accent = C.gold, w = 270, defaultY = -200, nameK = "bar_sgold",
        update = function(b)
            local _, total = SessionGoldPerHour()
            b.main:SetText(Coins(total) .. Gray(L.in_session))
            local start = WatchdogCharDB.sessionStart
            b.side:SetText(start and FormatClock(time() - start) or "")
        end,
    },
    igold = {
        accent = C.green, w = 270, defaultY = -240, nameK = "bar_igold",
        update = function(b)
            local scan = WD:ScanBags()
            b.main:SetText(Coins(scan.value) .. Gray(L.in_inventory))
            b.side:SetText(White(scan.used) .. Gray("/" .. scan.total))
        end,
    },
}

local function SaveBarState(key, f)
    WatchdogDB.bars = WatchdogDB.bars or {}
    local st = WatchdogDB.bars[key] or {}
    st.shown = f:IsShown()
    local point, _, relPoint, x, y = f:GetPoint()
    if point then st.pos = { point, relPoint, x, y } end
    WatchdogDB.bars[key] = st
end

local function CreateBar(key)
    local def = BAR_DEFS[key]
    local f = CreateFrame("Frame", "WatchdogBar_" .. key, UIParent, BT)
    f:SetSize(def.w, 30)
    Flat(f, C.card, C.border, 0.92)

    local st = WatchdogDB.bars and WatchdogDB.bars[key]
    if st and st.pos then
        f:SetPoint(st.pos[1], UIParent, st.pos[2], st.pos[3], st.pos[4])
    else
        f:SetPoint("TOP", UIParent, "TOP", 0, def.defaultY)
    end
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")

    local accent = f:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", 1, -1)
    accent:SetPoint("BOTTOMLEFT", 1, 1)
    accent:SetWidth(3)
    accent:SetColorTexture(def.accent[1], def.accent[2], def.accent[3], 1)

    f.main = FS(f, 14, C.text, "LEFT")
    f.main:SetPoint("LEFT", 14, 0)
    f.side = FS(f, 10, C.dim, "RIGHT")
    f.side:SetPoint("RIGHT", -10, 0)

    if key == "exp" then
        local track = f:CreateTexture(nil, "ARTWORK")
        track:SetPoint("BOTTOMLEFT", 1, 1)
        track:SetPoint("BOTTOMRIGHT", -1, 1)
        track:SetHeight(3)
        track:SetColorTexture(1, 1, 1, 0.08)
        f.fill = f:CreateTexture(nil, "OVERLAY")
        f.fill:SetPoint("BOTTOMLEFT", 1, 1)
        f.fill:SetHeight(3)
        f.fill:SetColorTexture(C.purple[1], C.purple[2], C.purple[3], 1)
    end

    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveBarState(key, self)
    end)
    f:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            self:Hide()
            SaveBarState(key, self)
        end
    end)
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(string.format(L.tip_bar_title, L[def.nameK]))
        GameTooltip:AddLine(L.tip_drag_move, 1, 1, 1)
        GameTooltip:AddLine(L.tip_right_close, 1, 1, 1)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local acc = 0
    f:SetScript("OnUpdate", function(self, elapsed)
        acc = acc + elapsed
        if acc >= 1 then
            acc = 0
            if WatchdogCharDB and WatchdogCharDB.session then def.update(self) end
        end
    end)
    f:SetScript("OnShow", function(self)
        if WatchdogCharDB and WatchdogCharDB.session then def.update(self) end
    end)

    f:Hide()  -- nasce escondida: o primeiro comando liga
    bars[key] = f
    return f
end

local function ToggleBar(key)
    local f = bars[key] or CreateBar(key)
    f:SetShown(not f:IsShown())
    SaveBarState(key, f)
    print("|cffffd100Watchdog:|r " .. string.format(L.bar_toggle, L[BAR_DEFS[key].nameK], f:IsShown() and L.on_word or L.off_word))
end

---------------------------------------------------------------------------
-- Aba ATALHOS: tudo que existe como /wd ... vira botao (liga/desliga com marcacao)
---------------------------------------------------------------------------
function BuildButtonsPanel(host)
    local left = SIDE_W + PAD
    local p = CreateFrame("Frame", nil, host)
    p:SetPoint("TOPLEFT", host, "TOPLEFT", left, -76)
    p:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -PAD, PAD)
    p:Hide()

    local colW = math.floor((CONTENT_W - 10) / 2)
    local refreshers = {}
    local y = 0

    local function Section(text)
        local s = FS(p, 11, C.dim, "LEFT")
        s:SetPoint("TOPLEFT", p, "TOPLEFT", 2, -y)
        s:SetText(text)
        y = y + 20
    end

    -- Botao com marcacao: indicador verde + "ON" quando ligado; apagado + "OFF" quando desligado.
    local function Card(col, row0, label, getOn, onClick, isAction)
        local b = CreateFrame("Button", nil, p, BT)
        b:SetSize(colW, 34)
        b:SetPoint("TOPLEFT", p, "TOPLEFT", col * (colW + 10), -(row0))
        Flat(b, C.card, C.border, 0.9)
        local dot = b:CreateTexture(nil, "ARTWORK")
        dot:SetSize(8, 8)
        dot:SetPoint("LEFT", 10, 0)
        local lab = FS(b, 12, C.text, "LEFT")
        lab:SetPoint("LEFT", 26, 0)
        lab:SetText(label)
        local st = FS(b, 11, C.mute, "RIGHT")
        st:SetPoint("RIGHT", -10, 0)
        local function paint()
            if isAction then
                dot:SetColorTexture(C.mute[1], C.mute[2], C.mute[3], 0.5)
                st:SetText(">")
                return
            end
            local on = getOn() and true or false
            if on then
                Flat(b, C.tile, C.green, 1)
                dot:SetColorTexture(C.green[1], C.green[2], C.green[3], 1)
                st:SetText(L.cfg_on); st:SetTextColor(C.green[1], C.green[2], C.green[3])
            else
                Flat(b, C.card, C.border, 0.9)
                dot:SetColorTexture(C.mute[1], C.mute[2], C.mute[3], 0.45)
                st:SetText(L.cfg_off); st:SetTextColor(C.mute[1], C.mute[2], C.mute[3])
            end
        end
        b:SetScript("OnClick", function() onClick(); paint() end)
        refreshers[#refreshers + 1] = paint
        paint()
        return b
    end

    local function Grid(items)
        local row0 = y
        for i, it in ipairs(items) do
            local col = (i - 1) % 2
            if col == 0 and i > 1 then row0 = row0 + 40 end
            Card(col, row0, it.label, it.on, it.click, it.action)
        end
        y = row0 + 44
    end

    local function BarOn(key) return function() return bars[key] and bars[key]:IsShown() end end
    local function BarGo(key) return function() ToggleBar(key) end end

    Section(L.btn_sec_toggle)
    Grid({
        { label = L[BAR_DEFS.gold.nameK], on = BarOn("gold"), click = BarGo("gold") },
        { label = L[BAR_DEFS.exp.nameK], on = BarOn("exp"), click = BarGo("exp") },
        { label = L[BAR_DEFS.sgold.nameK], on = BarOn("sgold"), click = BarGo("sgold") },
        { label = L[BAR_DEFS.igold.nameK], on = BarOn("igold"), click = BarGo("igold") },
        { label = L.btn_minimap, on = function() return not WatchdogDB.hideMinimap end,
          click = function()
              WatchdogDB.hideMinimap = not WatchdogDB.hideMinimap
              if ui.minimap then ui.minimap:SetShown(not WatchdogDB.hideMinimap) end
          end },
    })
    local acc = 0
    p:SetScript("OnUpdate", function(_, el)
        acc = acc + el
        if acc >= 0.5 then acc = 0; for _, fn in ipairs(refreshers) do fn() end end
    end)
    p:SetScript("OnShow", function() for _, fn in ipairs(refreshers) do fn() end end)
    return p
end

---------------------------------------------------------------------------
-- Aba AH: busca no catalogo do ultimo scan (AH movel: so consulta)
---------------------------------------------------------------------------
local AH_ROWS = 14
function BuildAHPanel(host)
    local left = SIDE_W + PAD
    local p = CreateFrame("Frame", nil, host)
    p:SetPoint("TOPLEFT", host, "TOPLEFT", left, -76)
    p:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -PAD, PAD)
    p:Hide()

    local box = CreateFrame("Frame", nil, p, BT)
    box:SetPoint("TOPLEFT", 0, 0)
    box:SetSize(230, 26)
    Flat(box, C.bg, C.border, 1)
    local eb = CreateFrame("EditBox", nil, box)
    eb:SetAutoFocus(false)
    eb:SetFont(FONT, 12, "")
    eb:SetTextColor(C.text[1], C.text[2], C.text[3])
    eb:SetPoint("TOPLEFT", 6, -3); eb:SetPoint("BOTTOMRIGHT", -6, 3)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local ph = FS(box, 12, C.mute, "LEFT")
    ph:SetPoint("LEFT", 8, 0)
    ph:SetText(L.ah_search)

    local sortBtn = MakeChip(p, "", 110)
    sortBtn:SetPoint("LEFT", box, "RIGHT", 8, 0)

    -- Engrenagem: configuracoes do valor AH x vendor e das cores dos contornos
    local gear = CreateFrame("Button", nil, p, BT)
    gear:SetSize(26, 26)
    gear:SetPoint("LEFT", sortBtn, "RIGHT", 6, 0)
    Flat(gear, C.card, C.border, 1)
    local gi = gear:CreateTexture(nil, "ARTWORK")
    gi:SetPoint("TOPLEFT", 3, -3); gi:SetPoint("BOTTOMRIGHT", -3, 3)
    gi:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    local pop = CreateFrame("Frame", nil, p, BT)
    pop:SetSize(330, 150)
    pop:SetPoint("TOPRIGHT", gear, "BOTTOMRIGHT", 0, -4)
    pop:SetFrameStrata("DIALOG")
    Flat(pop, C.bg, C.border, 1)
    pop:Hide()
    local function PopRow(y, text)
        local l = FS(pop, 12, C.text, "LEFT")
        l:SetPoint("TOPLEFT", 10, y)
        l:SetText(text)
        return l
    end
    PopRow(-14, L.ah_cfg_use)
    local useChip = MakeChip(pop, "", 60)
    useChip:SetPoint("TOPRIGHT", -10, -9)
    PopRow(-46, L.ah_cfg_pct)
    local plus = MakeChip(pop, "+", 26)
    plus:SetPoint("TOPRIGHT", -10, -41)
    local pctFS = FS(pop, 12, C.text, "CENTER")
    pctFS:SetPoint("RIGHT", plus, "LEFT", -4, 0); pctFS:SetWidth(44)
    local minus = MakeChip(pop, "-", 26)
    minus:SetPoint("RIGHT", pctFS, "LEFT", -4, 0)
    PopRow(-78, L.ah_cfg_vcol)
    local vChip = MakeChip(pop, "", 110)
    vChip:SetPoint("TOPRIGHT", -10, -73)
    PopRow(-110, L.ah_cfg_acol)
    local aChip = MakeChip(pop, "", 110)
    aChip:SetPoint("TOPRIGHT", -10, -105)
    local function PopPaint()
        local o = WD:AHOpt()
        useChip.text:SetText(o.on and L.cfg_on or L.cfg_off); useChip:SetActive(o.on)
        pctFS:SetText(o.pct .. "%")
        local b = WD:BorderOpt()
        local function sw(key)
            for _, pc in ipairs(WD.PALETTE) do
                if pc.key == key then
                    return string.format("|cff%02x%02x%02x■|r %s", pc.c[1] * 255, pc.c[2] * 255, pc.c[3] * 255, L["col_" .. key] or key)
                end
            end
            return key
        end
        vChip.text:SetText(sw(b.vk)); aChip.text:SetText(sw(b.ak))
    end
    useChip:SetScript("OnClick", function() local o = WD:AHOpt(); o.on = not o.on; PopPaint(); WD:BumpValuation() end)
    plus:SetScript("OnClick", function() local o = WD:AHOpt(); o.pct = math.min(100, o.pct + 5); PopPaint(); WD:BumpValuation() end)
    minus:SetScript("OnClick", function() local o = WD:AHOpt(); o.pct = math.max(50, o.pct - 5); PopPaint(); WD:BumpValuation() end)
    vChip:SetScript("OnClick", function() WD:CycleBorderColor("vendor"); PopPaint(); WD:UpdateBagBorders(); WD:Refresh() end)
    aChip:SetScript("OnClick", function() WD:CycleBorderColor("ah"); PopPaint(); WD:UpdateBagBorders(); WD:Refresh() end)
    gear:SetScript("OnClick", function() pop:SetShown(not pop:IsShown()); PopPaint() end)
    gear:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText(L.ah_cfg_tip); GameTooltip:Show() end)
    gear:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local info = FS(p, 11, C.dim, "LEFT")
    info:SetPoint("TOPLEFT", p, "TOPLEFT", 2, -32)
    local rule = FS(p, 11, C.dim, "LEFT")
    rule:SetPoint("TOPLEFT", p, "TOPLEFT", 2, -48)

    local hdrY = -68
    local itemW = {}
    local function Hdr(text, point, x, w, just)
        local h = FS(p, 10, C.mute, just)
        h:SetPoint(point, p, point, x, hdrY)
        h:SetWidth(w); h:SetText(text)
        itemW[#itemW + 1] = h
    end
    Hdr(L.ah_col_item, "TOPLEFT", 6, 220, "LEFT")
    Hdr(L.ah_col_qty, "TOPRIGHT", -250, 50, "RIGHT")
    Hdr(L.ah_col_vendor, "TOPRIGHT", -130, 110, "RIGHT")
    Hdr(L.ah_col_ah, "TOPRIGHT", -4, 120, "RIGHT")

    local rows = {}
    for r = 1, AH_ROWS do
        local row = CreateFrame("Frame", nil, p)
        row:SetHeight(20)
        row:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -84 - (r - 1) * 21)
        row:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, -84 - (r - 1) * 21)
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(C.card[1], C.card[2], C.card[3], (r % 2 == 0) and 0.5 or 0.22)
        row.name = FS(row, 12, C.text, "LEFT")
        row.name:SetPoint("LEFT", 6, 0); row.name:SetWidth(250); row.name:SetWordWrap(false)
        row.qty = FS(row, 11, C.dim, "RIGHT")
        row.qty:SetPoint("RIGHT", -250, 0); row.qty:SetWidth(50)
        row.vend = FS(row, 11, C.dim, "RIGHT")
        row.vend:SetPoint("RIGHT", -130, 0); row.vend:SetWidth(110)
        row.ah = FS(row, 11, C.text, "RIGHT")
        row.ah:SetPoint("RIGHT", -4, 0); row.ah:SetWidth(120)
        -- destaque + tooltip do item ao passar o mouse
        row:EnableMouse(true)
        row.hl = row:CreateTexture(nil, "HIGHLIGHT")
        row.hl:SetAllPoints(); row.hl:SetColorTexture(1, 1, 1, 0.07)
        row:Hide()
        rows[r] = row
    end

    local function ShowTip(row)
        local id = row.itemID
        if not id then return end
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        local ok = false
        if GameTooltip.SetItemByID then ok = pcall(GameTooltip.SetItemByID, GameTooltip, id) end
        if not ok then pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. id) end
        row.tipLoaded = GetItemInfo(id) ~= nil
        if not row.tipLoaded and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
        GameTooltip:Show()
    end
    for r = 1, AH_ROWS do
        local row = rows[r]
        row:SetScript("OnEnter", function(self) self.hover = true; ShowTip(self) end)
        row:SetScript("OnLeave", function(self) self.hover = nil; GameTooltip:Hide() end)
        -- item que ainda nao estava no cache do jogo: refaz o tooltip quando chegar
        local acc = 0
        row:SetScript("OnUpdate", function(self, el)
            if not self.hover or self.tipLoaded then return end
            acc = acc + el
            if acc < 0.4 then return end
            acc = 0
            if self.itemID and GetItemInfo(self.itemID) then ShowTip(self) end
        end)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta)
            local pw = p:GetScript("OnMouseWheel")
            if pw then pw(p, delta) end
        end)
    end

    local state2 = { sort = "name", offset = 0, q = "", list = {} }
    local function Rebuild()
        local q = eb:GetText()
        if type(q) ~= "string" then q = "" end
        ph:SetShown(q == "" and not eb:HasFocus())
        q = q:lower():gsub("^%s+", "")
        q = q:gsub("%s+$", "")
        local out = {}
        for _, e in ipairs(WD:AHIndex()) do
            if q == "" or e.lname:find(q, 1, true) then out[#out + 1] = e end
        end
        if state2.sort == "price" then
            table.sort(out, function(a, b) return a.p > b.p end)
        end
        state2.list = out
        state2.offset = 0
    end
    local function Paint()
        sortBtn.text:SetText(state2.sort == "price" and L.ah_sort_price or L.ah_sort_name)
        local t, cnt = WD:AHScanInfo()
        if t then
            local h = (time() - t) / 3600
            local age = h < 1 and string.format("%dm", math.max(1, math.floor(h * 60))) or (h < 48 and string.format("%dh", math.floor(h)) or string.format("%dd", math.floor(h / 24)))
            info:SetText(string.format(L.ah_info, cnt, age, #state2.list))
        else
            info:SetText(L.ah_noscan)
        end
        local o = WD:AHOpt()
        rule:SetText(o.on and string.format(L.ah_rule_on, o.pct) or L.ah_rule_off)
        local n = #state2.list
        state2.offset = math.max(0, math.min(math.max(0, n - AH_ROWS), state2.offset))
        for r = 1, AH_ROWS do
            local e = state2.list[state2.offset + r]
            local row = rows[r]
            if e then
                local _, quality, sell = WD:GetItemDisplay(e.id)
                row.name:SetText(QualityColor(quality) .. e.name .. "|r")
                row.qty:SetText(Num(e.q))
                row.vend:SetText((sell and sell > 0) and Coins(sell) or "-")
                row.ah:SetText(Coins(e.p))
                row.itemID = e.id
                row:Show()
                if row.hover then ShowTip(row) end    -- rolou a lista com o mouse parado: atualiza o tooltip
            else
                row.itemID = nil
                if row.hover then row.hover = nil; GameTooltip:Hide() end
                row:Hide()
            end
        end
    end
    p.Paint = Paint
    eb:SetScript("OnTextChanged", function() Rebuild(); Paint() end)
    eb:SetScript("OnEditFocusGained", function() ph:Hide() end)
    eb:SetScript("OnEditFocusLost", function() ph:SetShown((eb:GetText() or "") == "") end)
    sortBtn:SetScript("OnClick", function()
        state2.sort = (state2.sort == "name") and "price" or "name"
        Rebuild(); Paint()
    end)
    ---------------------------------------------------------------------
    -- Subaba Historico: compras, vendas, postados, expirados e cancelados
    ---------------------------------------------------------------------
    local mode = "items"
    local hp = CreateFrame("Frame", nil, p)
    hp:SetAllPoints(p)
    hp:Hide()
    local H_ROWS = 14
    local hs = { filter = "all", period = "all", offset = 0, list = {}, buy = 0, sell = 0, fees = 0 }
    local FILTERS = { "all", "buy", "sell", "post", "exp" }
    local PERIODS = { "all", "day", "week", "month" }
    local PSECS = { day = 86400, week = 7 * 86400, month = 30 * 86400 }
    local KCOL = { buy = "|cffff7a7a", sell = "|cff7aff94", post = "|cffbfbfbf", exp = "|cff8a8a8a", cancel = "|cff8a8a8a" }

    local fChip = MakeChip(hp, "", 160)
    fChip:SetPoint("TOPLEFT", hp, "TOPLEFT", 0, 0)
    local pChip = MakeChip(hp, "", 130)
    pChip:SetPoint("LEFT", fChip, "RIGHT", 6, 0)
    local hsum = FS(hp, 11, C.dim, "LEFT")
    hsum:SetPoint("TOPLEFT", hp, "TOPLEFT", 2, -32)
    local function HHdr(text, point, x, w, just)
        local h = FS(hp, 10, C.mute, just)
        h:SetPoint(point, hp, point, x, -52)
        h:SetWidth(w); h:SetText(text)
    end
    HHdr(L.hist_c_date, "TOPLEFT", 6, 86, "LEFT")
    HHdr(L.hist_c_type, "TOPLEFT", 94, 54, "LEFT")
    HHdr(L.hist_c_item, "TOPLEFT", 152, 190, "LEFT")
    HHdr(L.hist_c_qty, "TOPRIGHT", -138, 40, "RIGHT")
    HHdr(L.hist_c_value, "TOPRIGHT", -4, 130, "RIGHT")
    local hempty = FS(hp, 12, C.mute, "CENTER")
    hempty:SetPoint("TOP", hp, "TOP", 0, -120)
    hempty:SetWidth(430); hempty:SetWordWrap(true)

    local hrows = {}
    for r = 1, H_ROWS do
        local row = CreateFrame("Frame", nil, hp)
        row:SetHeight(20)
        row:SetPoint("TOPLEFT", hp, "TOPLEFT", 0, -66 - (r - 1) * 21)
        row:SetPoint("TOPRIGHT", hp, "TOPRIGHT", 0, -66 - (r - 1) * 21)
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(C.card[1], C.card[2], C.card[3], (r % 2 == 0) and 0.5 or 0.22)
        row.date = FS(row, 11, C.dim, "LEFT")
        row.date:SetPoint("LEFT", 6, 0); row.date:SetWidth(86)
        row.kind = FS(row, 11, C.text, "LEFT")
        row.kind:SetPoint("LEFT", 94, 0); row.kind:SetWidth(56)
        row.name = FS(row, 12, C.text, "LEFT")
        row.name:SetPoint("LEFT", 152, 0); row.name:SetWidth(190); row.name:SetWordWrap(false)
        row.qty = FS(row, 11, C.dim, "RIGHT")
        row.qty:SetPoint("RIGHT", -138, 0); row.qty:SetWidth(40)
        row.val = FS(row, 11, C.text, "RIGHT")
        row.val:SetPoint("RIGHT", -4, 0); row.val:SetWidth(130)
        row:EnableMouse(true)
        row.hl = row:CreateTexture(nil, "HIGHLIGHT")
        row.hl:SetAllPoints(); row.hl:SetColorTexture(1, 1, 1, 0.07)
        row:Hide()
        hrows[r] = row
    end

    local function EntryName(e)
        local name, quality = e.name, nil
        if e.id then
            local ok, n, _, q = pcall(GetItemInfo, e.id)
            if ok and n then name = name or n; quality = q end
        elseif e.name then
            local ok, _, _, q = pcall(GetItemInfo, e.name)
            if ok then quality = q end
        end
        if not name then name = e.id and ("#" .. e.id) or "?" end
        return name, quality
    end
    local function HTip(row)
        local e = row.entry
        if not e then return end
        GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
        local shown = false
        if e.id then
            if GameTooltip.SetItemByID then shown = pcall(GameTooltip.SetItemByID, GameTooltip, e.id) end
            if not shown then shown = pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. e.id) end
        elseif e.name then
            local ok, _, link = pcall(GetItemInfo, e.name)
            if ok and link then shown = pcall(GameTooltip.SetHyperlink, GameTooltip, link) end
        end
        if not shown then GameTooltip:SetText((EntryName(e))) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(date("%d/%m/%Y %H:%M", e.t or time()) .. "  -  " .. (L["hist_k_" .. (e.kind or "post")] or ""), 0.8, 0.8, 0.8)
        if e.kind == "sell" then
            if e.who then GameTooltip:AddLine(L.hist_tip_buyer .. ": " .. e.who, 0.7, 0.7, 0.7) end
            GameTooltip:AddLine(L.hist_tip_fee .. ": " .. Coins(e.fee or 0), 0.7, 0.7, 0.7)
            GameTooltip:AddLine(L.hist_tip_net .. ": " .. Coins(math.max(0, (e.price or 0) - (e.fee or 0))), 0.7, 0.7, 0.7)
        elseif e.kind == "buy" and e.who then
            GameTooltip:AddLine(L.hist_tip_seller .. ": " .. e.who, 0.7, 0.7, 0.7)
        end
        if e.char then GameTooltip:AddLine(L.hist_tip_char .. ": " .. e.char, 0.55, 0.55, 0.55) end
        GameTooltip:Show()
    end
    for r = 1, H_ROWS do
        local row = hrows[r]
        row:SetScript("OnEnter", function(self) self.hover = true; HTip(self) end)
        row:SetScript("OnLeave", function(self) self.hover = nil; GameTooltip:Hide() end)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta)
            local pw = p:GetScript("OnMouseWheel")
            if pw then pw(p, delta) end
        end)
    end

    local function HRebuild()
        local out, now = {}, time()
        local lim = PSECS[hs.period]
        local l = WD:HistList()
        local buy, sell, fees = 0, 0, 0
        for i = #l, 1, -1 do
            local e = l[i]
            if not lim or now - (e.t or 0) <= lim then
                if e.kind == "buy" then buy = buy + (e.price or 0)
                elseif e.kind == "sell" then sell = sell + (e.price or 0); fees = fees + (e.fee or 0) end
                local f = hs.filter
                if f == "all" or f == e.kind or (f == "exp" and e.kind == "cancel") then out[#out + 1] = e end
            end
        end
        hs.list, hs.buy, hs.sell, hs.fees = out, buy, sell, fees
        hs.offset = 0
    end
    local function HPaint()
        fChip.text:SetText(L["hist_f_" .. hs.filter]); fChip:SetActive(hs.filter ~= "all")
        pChip.text:SetText(L["hist_p_" .. hs.period]); pChip:SetActive(hs.period ~= "all")
        local bal = hs.sell - hs.fees - hs.buy
        local balTxt = (bal < 0 and "|cffff7a7a-" or "|cff7aff94") .. Coins(math.abs(bal)) .. "|r"
        hsum:SetText(string.format(L.hist_sum, Coins(hs.buy), Coins(hs.sell), Coins(hs.fees), balTxt))
        local n = #hs.list
        hs.offset = math.max(0, math.min(math.max(0, n - H_ROWS), hs.offset))
        hempty:SetText(n == 0 and L.hist_empty or "")
        for r = 1, H_ROWS do
            local e = hs.list[hs.offset + r]
            local row = hrows[r]
            if e then
                local nm, q = EntryName(e)
                local yr = (time() - (e.t or 0)) > 300 * 86400
                row.date:SetText(date(yr and "%d/%m/%y" or "%d/%m %H:%M", e.t or time()))
                local kind = e.kind or "post"
                row.kind:SetText((KCOL[kind] or "") .. (L["hist_k_" .. kind] or kind) .. "|r")
                row.name:SetText(QualityColor(q) .. nm .. "|r")
                row.qty:SetText(e.count and Num(e.count) or "-")
                if kind == "exp" or kind == "cancel" or not e.price or e.price <= 0 then
                    row.val:SetText("-")
                else
                    row.val:SetText((KCOL[kind] or "") .. Coins(e.price) .. "|r")
                end
                row.entry = e
                row:Show()
                if row.hover then HTip(row) end
            else
                row.entry = nil
                if row.hover then row.hover = nil; GameTooltip:Hide() end
                row:Hide()
            end
        end
    end
    local function Cycle(list, cur)
        for i, v in ipairs(list) do if v == cur then return list[i % #list + 1] end end
        return list[1]
    end
    fChip:SetScript("OnClick", function() hs.filter = Cycle(FILTERS, hs.filter); HRebuild(); HPaint() end)
    pChip:SetScript("OnClick", function() hs.period = Cycle(PERIODS, hs.period); HRebuild(); HPaint() end)

    local subItems = MakeChip(p, L.ah_sub_items, 52)
    subItems:SetPoint("TOPRIGHT", p, "TOPRIGHT", -78, 0)
    local subHist = MakeChip(p, L.ah_sub_hist, 74)
    subHist:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, 0)
    local function SetMode(m)
        mode = m
        subItems:SetActive(m == "items"); subHist:SetActive(m == "hist")
        pop:Hide()
        GameTooltip:Hide()
        for _, w in ipairs({ box, sortBtn, gear, info, rule }) do w:SetShown(m == "items") end
        for _, w in ipairs(itemW) do w:SetShown(m == "items") end
        hp:SetShown(m == "hist")
        if m == "items" then
            Rebuild(); Paint()
        else
            for r = 1, AH_ROWS do rows[r]:Hide() end
            HRebuild(); HPaint()
        end
    end
    subItems:SetScript("OnClick", function() SetMode("items") end)
    subHist:SetScript("OnClick", function() SetMode("hist") end)
    subItems:SetActive(true)

    p:EnableMouseWheel(true)
    p:SetScript("OnMouseWheel", function(_, delta)
        if mode == "hist" then
            hs.offset = hs.offset - delta * 3
            HPaint()
        else
            state2.offset = state2.offset - delta * 3
            Paint()
        end
    end)
    p:SetScript("OnShow", function() SetMode(mode) end)
    p:SetScript("OnHide", function() pop:Hide() end)
    function WD:RefreshAHTab()
        if not p:IsShown() then return end
        if mode == "hist" then
            local off = hs.offset
            HRebuild(); hs.offset = off; HPaint()
        else
            Rebuild(); Paint()
        end
    end
    return p
end

local function RestoreBars()
    local saved = WatchdogDB.bars
    if not saved then return end
    for key, st in pairs(saved) do
        if BAR_DEFS[key] and st.shown then
            local f = bars[key] or CreateBar(key)
            f:Show()
        end
    end
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

    local back = mb:CreateTexture(nil, "BACKGROUND")
    back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    back:SetSize(22, 22)
    back:SetPoint("TOPLEFT", 5, -4)

    local icon = mb:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(MEDIA .. "emblem_icon")
    icon:SetSize(18, 18)
    icon:SetPoint("TOPLEFT", 7, -6)

    local border = mb:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    local function UpdatePosition()
        local a = math.rad(WatchdogDB.minimapAngle or 210)
        mb:ClearAllPoints()
        -- raio acompanha o tamanho real do minimapa (mesma regra dos outros botoes: na borda do anel)
        local w = Minimap:GetWidth()
        local r = (w and w > 10) and (w / 2 + 5) or 80
        mb:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
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
        GameTooltip:AddLine(L.tip_click_toggle, 1, 1, 1)
        GameTooltip:AddLine(L.tip_drag_button, 1, 1, 1)
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
    RestoreBars()
    HookNameplateName()
    if WD.MaxNameplateRange then WD:MaxNameplateRange() end
end)

---------------------------------------------------------------------------
-- Comandos
---------------------------------------------------------------------------
local QUALITY_KEYS = { [0] = "q_gray", "q_common", "q_uncommon", "q_rare", "q_epic", "q_legendary" }

local function AlertsCommand(arg)
    local a = WatchdogDB.alerts
    arg = strtrim((arg or ""):lower())
    local function onoff(v) return v and ("|cff00ff00" .. L.enabled .. "|r") or ("|cffff5555" .. L.disabled .. "|r") end
    if arg == "drop" then
        a.drop = not a.drop
    elseif arg == "raro" or arg == "rare" or arg == "mob" then
        a.rare = not a.rare
    elseif arg == "som" or arg == "sound" then
        a.sound = not a.sound
    elseif tonumber(arg) then
        a.minQuality = math.max(0, math.min(5, math.floor(tonumber(arg))))
    elseif arg ~= "" then
        print("|cffffd100Watchdog:|r " .. L.alerts_usage)
        return
    end
    print("|cffffd100" .. L.alerts_header .. "|r")
    print(string.format(L.alerts_drop, onoff(a.drop), a.minQuality, L[QUALITY_KEYS[a.minQuality]] or "?"))
    print(string.format(L.alerts_rare, onoff(a.rare)))
    print(string.format(L.alerts_sound, onoff(a.sound)))
end

SLASH_WATCHDOG1 = "/wd"
SLASH_WATCHDOG2 = "/watchdog"
SlashCmdList.WATCHDOG = function(msg)
    local raw = strtrim(msg or "")
    msg = raw:lower()
    local cmd = msg:match("^(%S+)") or ""
    local rest = raw:match("^%S+%s+(.*)$") or ""
    if cmd == "nova" or cmd == "new" then
        WD:StartNewSession()
        print("|cffffd100Watchdog:|r " .. L.msg_new_session)
    elseif cmd == "lang" or cmd == "idioma" or cmd == "lingua" then
        local code = rest:lower()
        if code == "pt" or code == "ptbr" or code == "pt-br" or code == "portugues" or code == "português" then code = "ptBR"
        elseif code == "en" or code == "enus" or code == "ingles" or code == "inglês" or code == "english" then code = "enUS" end
        if WD.locales[code] then
            WatchdogDB.locale = code
            WD:SetLocale(code)
            print("|cffffd100Watchdog:|r " .. string.format(L.msg_lang_set, WD.localeNames[code] or code))
            print("|cffffd100Watchdog:|r " .. L.msg_lang_reload)
        else
            print("|cffffd100Watchdog:|r " .. L.msg_lang_usage)
        end
    elseif cmd == "minimapa" or cmd == "minimap" then
        WatchdogDB.hideMinimap = not WatchdogDB.hideMinimap
        if ui.minimap then ui.minimap:SetShown(not WatchdogDB.hideMinimap) end
    elseif cmd == "goldbar" then
        ToggleBar("gold")
    elseif cmd == "expbar" then
        ToggleBar("exp")
    elseif cmd == "sgoldbar" then
        ToggleBar("sgold")
    elseif cmd == "igoldbar" then
        ToggleBar("igold")
    elseif cmd == "commands" or cmd == "comandos" or cmd == "cmds" then
        if WD.ToggleCommands then WD:ToggleCommands() end
    elseif cmd == "config" or cmd == "opcoes" or cmd == "opções" or cmd == "menu" or cmd == "assist" then
        if WD.ToggleConfig then WD:ToggleConfig() end
    elseif cmd == "premium" or cmd == "lista" or cmd == "watchlist" or cmd == "blacklist" or cmd == "black" then
        WD:Toggle("black")
    elseif cmd == "ah" or cmd == "leilao" or cmd == "leilão" then
        WD:Toggle("ah")
    elseif cmd == "bordas" or cmd == "borders" or cmd == "contornos" then
        WD:ToggleBorders()
        print("|cffffd100Watchdog:|r " .. L.inv_borders .. ": " .. (WD:BorderOpt().on and L.cfg_on or L.cfg_off))
    elseif cmd == "goldinfo" then
        local sv = WatchdogCharDB and WatchdogCharDB.session or {}
        local ahP, ahV = WD:AHTotals(WatchdogCharDB.sessionStart)
        local g = WD:GoldSummary({
            income = sv.income or 0,
            bagDelta = (sv.bagStart and sv.bagLast) and (sv.bagLast - sv.bagStart) or nil,
            bagDeltaA = (sv.bagStartA and sv.bagLastA) and (sv.bagLastA - sv.bagStartA) or nil,
            ahPrice = ahP, ahVendor = ahV, ahVendorA = 0 })
        print(string.format("|cffffd100Watchdog gold:|r income=%d bagStart=%d bagLast=%d delta=%d ahPosted=%d ahVendor=%d -> raw=%d (mostrado=%d)",
            sv.income or 0, sv.bagStart or -1, sv.bagLast or -1, (sv.bagLast or 0) - (sv.bagStart or 0), ahP or 0, ahV or 0,
            (g.coin or 0) + (g.inv or 0) + (ahP or 0), g.probable or 0))
    elseif cmd == "scan" then
        WD:StartAHScan()
    elseif cmd == "nameplates" or cmd == "plaquinhas" or cmd == "alcance" then
        WD:MaxNameplateRange()
        print("|cffffd100Watchdog:|r " .. L.msg_nameplates)
    elseif cmd == "watch" or cmd == "marcar" or cmd == "unwatch" or cmd == "desmarcar" then
        local remove = (cmd == "unwatch" or cmd == "desmarcar")
        local n = strtrim(rest or "")
        local kind
        local pre = n:match("^[Pp][Vv][Pp]%s+(.+)$")
        if pre then kind, n = "pvp", pre end
        if n == "" and UnitExists("target") then
            n = UnitName("target")
            kind = UnitIsPlayer("target") and "pvp" or "pve"
        end
        if n ~= "" and remove then
            WD:RemoveWatch(n, kind)
            print("|cffffd100Watchdog:|r " .. string.format(L.msg_watch_removed, n))
        elseif n ~= "" and WD:AddWatch(n, kind) then
            print("|cffffd100Watchdog:|r " .. string.format(L.msg_watch_added, n))
        else
            print("|cffffd100Watchdog:|r " .. L.msg_watch_usage)
        end
    elseif cmd == "consumiveis" or cmd == "consumíveis" or cmd == "cons" or cmd == "consumables" then
        if WD.PrintConsumables then WD:PrintConsumables() end
    elseif cmd == "sessao" or cmd == "sessão" or cmd == "session" then
        state.histView = "current"
        WD:Toggle("hist")
    elseif cmd == "wizard" or cmd == "intro" or cmd == "boasvindas" then
        if WD.ShowWizard then WD:ShowWizard(true) end
    elseif cmd == "relatorio" or cmd == "relatório" or cmd == "report" then
        WD:ShowReport()
    elseif cmd == "historico" or cmd == "histórico" or cmd == "history" then
        WD:Toggle("hist")
    elseif cmd == "inventario" or cmd == "inventário" or cmd == "bolsa" or cmd == "inventory" or cmd == "bag" then
        WD:Toggle("inv")
    elseif cmd == "alertas" or cmd == "alerta" or cmd == "alerts" or cmd == "alert" or cmd == "warning" or cmd == "warnings" then
        AlertsCommand(rest)
    elseif cmd == "debug" then
        WD.debug = not WD.debug
        print("|cffffd100Watchdog:|r " .. (WD.debug and L.debug_on or L.debug_off))
    elseif cmd == "status" then
        WD:PrintStatus()
    elseif cmd == "ajuda" or cmd == "help" then
        print("|cffffd100Watchdog|r " .. L.help_header)
        for _, line in ipairs({
            L.help_open, L.help_new, L.help_report, L.help_hist, L.help_cons, L.help_session, L.help_wizard, L.help_inv,
            L.help_alerts, L.help_premium, L.help_watch, L.help_unwatch, L.help_nameplates,
            L.help_minimap, L.help_goldbar, L.help_expbar, L.help_sgoldbar, L.help_igoldbar,
            L.help_config, L.help_lang, L.help_status, L.help_debug,
        }) do print(line) end
    else
        WD:Toggle()
    end
end

SLASH_WATCHDOGGOLDBAR1 = "/wdgoldbar"
SlashCmdList.WATCHDOGGOLDBAR = function() ToggleBar("gold") end

SLASH_WATCHDOGEXPBAR1 = "/wdexpbar"
SlashCmdList.WATCHDOGEXPBAR = function() ToggleBar("exp") end

SLASH_WATCHDOGSGOLDBAR1 = "/wdsgoldbar"
SlashCmdList.WATCHDOGSGOLDBAR = function() ToggleBar("sgold") end

SLASH_WATCHDOGIGOLDBAR1 = "/wdigoldbar"
SlashCmdList.WATCHDOGIGOLDBAR = function() ToggleBar("igold") end

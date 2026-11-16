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
    { key = "pve",  labelK = "tab_pve",  titleK = "title_pve" },
    { key = "pvp",  labelK = "tab_pvp",  titleK = "title_pvp" },
    { key = "xp",   labelK = "tab_xp",   titleK = "title_xp" },
    { key = "inv",  labelK = "tab_inv",  titleK = "title_inv" },
    { key = "hist", labelK = "tab_hist", titleK = "title_hist" },
}

local SORTS = {
    { key = "kills",   labelK = "sort_kills" },
    { key = "value",   labelK = "sort_value" },
    { key = "perkill", labelK = "sort_perkill" },
    { key = "hit",     labelK = "sort_hit" },
}

local INV_VIEWS = {
    { key = "bag",  labelK = "inv_bag" },
    { key = "list", labelK = "inv_list" },
}

local FRAME_W, FRAME_H = 680, 470
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
    if c and c.hex then return c.hex end
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
    local total = WD:BucketValue(WatchdogCharDB.session)
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
local function Flat(f, bg, border, alpha)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
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
            Flat(self, C.card, C.border, 0.9)
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
        if qc then
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
    t.value:SetPoint("TOPLEFT", 12, -12)
    t.label = FS(t, 10, C.dim, "LEFT")
    t.label:SetPoint("BOTTOMLEFT", 12, 9)
    t.sub = FS(t, 10, C.mute, "RIGHT")
    t.sub:SetPoint("BOTTOMRIGHT", -12, 9)

    tiles[i] = t
    return t
end

local function SetTile(i, col, cols, y, label, value, color, sub)
    local t = GetTile(i)
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
    ui.summary:SetText(PeriodLabel())

    SetTile(1, 1, 2, 0,  L.t_xp_period, Num(data.xp or 0), C.text)
    SetTile(2, 2, 2, 0,  L.t_xp_hour,   Num(math.floor(s.perHour)), C.green,
        L.period_session .. " " .. FormatDuration(s.elapsed))
    SetTile(3, 1, 2, 72, L.t_xp_session,  Num(s.sessionXP), C.text)
    SetTile(4, 2, 2, 72, L.t_levels, tostring(s.levels), C.gold)

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
        SetTile(5, 1, 3, 200, L.t_remaining,  Num(s.remaining), C.text, rested)
        SetTile(6, 2, 3, 200, L.t_time_level,  FormatDuration(s.timeToLevel), C.text)
        SetTile(7, 3, 3, 200, L.t_kills_level,  s.killsToLevel and Num(s.killsToLevel) or "-", C.text,
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
            }
            -- Ranking por drop % so conta mobs com amostra minima (>= 5 kills).
            entries[#entries].hitr = (m.kills or 0) >= 5 and entries[#entries].hit or 0
        end
        local metric = state.sort == "value" and "value" or (state.sort == "perkill" and "per")
            or (state.sort == "hit" and "hitr") or "kills"
        table.sort(entries, function(a, b)
            if a[metric] ~= b[metric] then return a[metric] > b[metric] end
            if metric == "hitr" and a.per ~= b.per then return a.per > b.per end
            if a.kills ~= b.kills then return a.kills > b.kills end
            return a.name < b.name
        end)

        ui.summary:SetText(PeriodLabel() .. "  ·  " .. White(Num(total)) .. L.kills_word)
        local top = entries[1] and entries[1][metric] or 0
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
                pct = e[metric] / top,
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
    })
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
        value = WD:BucketValue(s),
        money = s.money or 0,
        pvpKills = pvp.kills, deaths = pvp.deaths, honor = pvp.honor,
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
            value = h.value or 0,
            money = h.money or 0,
            pvpKills = h.pvpKills, deaths = h.deaths, honor = h.honor,
        })
    end
    return n
end

local function SetChipVisibility()
    local inPeriodTab = state.tab == "pve" or state.tab == "pvp" or state.tab == "xp"
    for _, b in ipairs(ui.periodButtons) do b:SetShown(inPeriodTab) end
    for _, b in ipairs(ui.viewButtons) do b:SetShown(state.tab == "inv") end
    ui.sortBtn:SetShown(state.tab == "pve" and not state.mob)
end

function WD:Render()
    if not frame or not frame:IsShown() then return end

    for _, b in ipairs(ui.periodButtons) do b:SetActive(b.key == state.period) end
    for _, b in ipairs(ui.viewButtons) do b:SetActive(b.key == state.invView) end
    for key, b in pairs(ui.tabs) do b:SetActive(key == state.tab) end
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

    if state.tab == "pve" then
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
        ui.info:Hide()
        ui.scroll:Show()
        ui.back:Hide()
        n = RenderHist()
        contentH = math.max(1, n * ROW_H)
    else
        ui.scroll:Hide()
        ui.back:Hide()
        ui.info:Show()
        HideInfo()
        local data = WD:Aggregate(state.period)
        if state.tab == "pvp" then RenderPvP(data) else RenderXP(data) end
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
        pcall(PlaySound, 8959)
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

function WD:ColorOneNameplate(unit)
    if not unit or not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then return end
    local np = C_NamePlate.GetNamePlateForUnit(unit)
    local fs = NameplateNameFS(np)
    if not fs or not fs.SetVertexColor then return end
    local name = UnitName(unit)
    if name and WD:IsWatched(name) then
        local col = WatchdogDB.watchColor or C.blue
        fs:SetVertexColor(col[1], col[2], col[3])
    end
end

function WD:OnNameplateAdded(unit)
    WD:ColorOneNameplate(unit)
end

function WD:RefreshNameplates()
    if not C_NamePlate or not C_NamePlate.GetNamePlates then return end
    for _, np in ipairs(C_NamePlate.GetNamePlates()) do
        local unit = np.namePlateUnitToken or (np.UnitFrame and np.UnitFrame.unit)
        if unit then WD:ColorOneNameplate(unit) end
    end
end

-- Liga nomes de inimigos e joga o alcance das nameplates no maximo,
-- para o nome azul aparecer de mais longe possivel.
function WD:MaxNameplateRange()
    local function set(k, v) pcall(SetCVar, k, v) end
    set("nameplateShowEnemies", 1)
    set("nameplateMaxDistance", 41)
    set("nameplateMaxDistanceenemy", 41)
    if WD.RefreshNameplates then WD:RefreshNameplates() end
end

-- Mantem a cor mesmo quando a Blizzard reescreve o nome da nameplate.
local function HookNameplateName()
    if WD._nameHooked then return end
    if type(CompactUnitFrame_UpdateName) ~= "function" or not hooksecurefunc then return end
    hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
        if not frame or not frame.unit or not frame.name then return end
        if not tostring(frame.unit):match("nameplate") then return end
        local name = UnitName(frame.unit)
        if name and WD:IsWatched(name) and frame.name.SetVertexColor then
            local col = WatchdogDB.watchColor or C.blue
            frame.name:SetVertexColor(col[1], col[2], col[3])
        end
    end)
    WD._nameHooked = true
end

local watchFrame
local function RebuildWatchRows()
    local f = watchFrame
    if not f then return end
    for _, row in ipairs(f.rows) do row:Hide() end
    local list = WD:WatchList()
    f.count:SetText(Gray(string.format(L.watch_count, #list)))
    local shown = math.min(#list, #f.rows)
    for i = 1, shown do
        local row = f.rows[i]
        row.label:SetText(Hex(C.blue) .. list[i] .. "|r")
        row.name = list[i]
        row:Show()
    end
    if #list > shown then
        local row = f.rows[shown]
        if row then row.label:SetText(Gray(string.format(L.watch_more, #list - shown))) end
    end
    if #list == 0 then
        f.empty:Show()
    else
        f.empty:Hide()
    end
end

function WD:ShowWatchList()
    if not watchFrame then
        local f = CreateFrame("Frame", "WatchdogWatchFrame", UIParent, BT)
        f:SetSize(360, 420)
        f:SetPoint("CENTER")
        Flat(f, C.bg, C.border, 0.98)
        f:SetFrameStrata("DIALOG")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:Hide()
        tinsert(UISpecialFrames, "WatchdogWatchFrame")
        f.rows = {}

        local title = FS(f, 16, C.text, "LEFT")
        title:SetPoint("TOPLEFT", 18, -16)
        title:SetText(L.watch_title)
        local hint = FS(f, 11, C.dim, "LEFT")
        hint:SetPoint("TOPLEFT", 18, -38)
        hint:SetWidth(324)
        hint:SetJustifyH("LEFT")
        hint:SetText(L.watch_hint)

        local box = CreateFrame("Frame", nil, f, BT)
        box:SetPoint("TOPLEFT", 16, -70)
        box:SetPoint("TOPRIGHT", -108, -70)
        box:SetHeight(26)
        Flat(box, C.card, C.border, 1)
        local eb = CreateFrame("EditBox", nil, box)
        eb:SetAutoFocus(false)
        eb:SetFont(FONT, 13, "")
        eb:SetTextColor(C.text[1], C.text[2], C.text[3])
        eb:SetPoint("TOPLEFT", 8, -2)
        eb:SetPoint("BOTTOMRIGHT", -8, 2)
        eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        local function doAdd()
            local n = eb:GetText()
            if n == "" and UnitExists("target") and not UnitIsPlayer("target") then n = UnitName("target") end
            if WD:AddWatch(n) then eb:SetText("") end
            RebuildWatchRows()
        end
        eb:SetScript("OnEnterPressed", doAdd)
        f.edit = eb

        local addBtn = MakeChip(f, L.watch_add, 84)
        addBtn:SetPoint("TOPRIGHT", -16, -70)
        addBtn:SetScript("OnClick", doAdd)

        local tgtBtn = MakeChip(f, L.watch_add_target, 160)
        tgtBtn:SetPoint("TOPLEFT", 16, -104)
        tgtBtn:SetScript("OnClick", function()
            if UnitExists("target") and not UnitIsPlayer("target") then
                WD:AddWatch(UnitName("target"))
                RebuildWatchRows()
            end
        end)

        f.count = FS(f, 11, C.dim, "RIGHT")
        f.count:SetPoint("TOPRIGHT", -16, -112)

        local listbox = CreateFrame("Frame", nil, f, BT)
        listbox:SetPoint("TOPLEFT", 16, -136)
        listbox:SetPoint("BOTTOMRIGHT", -16, 52)
        Flat(listbox, C.card, C.border, 1)

        f.empty = FS(listbox, 12, C.dim, "CENTER")
        f.empty:SetPoint("CENTER")
        f.empty:SetText(L.watch_empty)

        local ROWH = 24
        for i = 1, 11 do
            local row = CreateFrame("Button", nil, listbox)
            row:SetHeight(ROWH)
            row:SetPoint("TOPLEFT", 6, -6 - (i - 1) * ROWH)
            row:SetPoint("TOPRIGHT", -6, -6 - (i - 1) * ROWH)
            row.label = FS(row, 13, C.text, "LEFT")
            row.label:SetPoint("LEFT", 6, 0)
            local x = FS(row, 14, C.red, "RIGHT")
            x:SetPoint("RIGHT", -8, 0)
            x:SetText("X")
            row.x = x
            row:SetScript("OnClick", function(self)
                if self.name then WD:RemoveWatch(self.name); RebuildWatchRows() end
            end)
            row:SetScript("OnEnter", function(self) self.label:SetText(self.label:GetText()); GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(L.watch_remove); GameTooltip:Show() end)
            row:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row:Hide()
            f.rows[i] = row
        end

        local close = MakeChip(f, L.btn_close, 90)
        close:SetPoint("BOTTOMRIGHT", -16, 16)
        close:SetScript("OnClick", function() f:Hide() end)

        watchFrame = f
    end
    HookNameplateName()
    watchFrame:Show()
    RebuildWatchRows()
end

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
    for _, t in ipairs(TABS) do
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
            state.tab = key
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

    -- Rodape: relatorio, nova sessao e versao
    local premium = MakeChip(side, L.chip_premium, SIDE_W - 28)
    premium:SetPoint("BOTTOM", side, "BOTTOM", 0, 100)
    premium:SetScript("OnClick", function() WD:ShowWatchList() end)

    local report = MakeChip(side, L.chip_report, SIDE_W - 28)
    report:SetPoint("BOTTOM", side, "BOTTOM", 0, 70)
    report:SetScript("OnClick", function() WD:ShowReport() end)

    local newSession = MakeChip(side, L.chip_newsession, SIDE_W - 28)
    newSession:SetPoint("BOTTOM", side, "BOTTOM", 0, 40)
    newSession:SetScript("OnClick", function()
        WD:StartNewSession()
    end)

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
    ui.back:SetScript("OnClick", function() state.mob = nil; ui.scroll:SetVerticalScroll(0); WD:Render() end)

    -- Periodos (PvE / PvP / EXP)
    ui.periodButtons = {}
    local prev
    for _, p in ipairs(PERIODS) do
        local b = MakeChip(f, L[p.labelK], 68)
        b.key = p.key
        if prev then
            b:SetPoint("LEFT", prev, "RIGHT", 6, 0)
        else
            b:SetPoint("TOPLEFT", f, "TOPLEFT", left, -76)
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
            b:SetPoint("TOPLEFT", f, "TOPLEFT", left, -76)
        end
        b:SetScript("OnClick", function()
            state.invView = v.key
            ui.scroll:SetVerticalScroll(0)
            WD:Render()
        end)
        ui.viewButtons[#ui.viewButtons + 1] = b
        prev = b
    end

    -- Ordenacao da lista de mobs (PvE)
    ui.sortBtn = MakeChip(f, L[SORTS[1].labelK], 104)
    ui.sortBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -76)
    ui.sortBtn:SetScript("OnClick", function()
        for i, s in ipairs(SORTS) do
            if s.key == state.sort then
                state.sort = SORTS[i % #SORTS + 1].key
                break
            end
        end
        ui.scroll:SetVerticalScroll(0)
        WD:Render()
    end)

    -- Lista / bolsa com rolagem (sem barra: use a roda do mouse).
    ui.scroll = CreateFrame("ScrollFrame", "WatchdogScroll", f)
    ui.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", left, -116)
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
    ui.info:SetPoint("TOPLEFT", f, "TOPLEFT", left, -116)
    ui.info:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD + 38)

    -- Barra de XP
    ui.xpLabel = FS(ui.info, 13, C.dim, "LEFT")
    ui.xpLabel:SetPoint("TOPLEFT", ui.info, "TOPLEFT", 2, -150)
    ui.xpPct = FS(ui.info, 11, C.dim, "RIGHT")
    ui.xpPct:SetPoint("TOPRIGHT", ui.info, "TOPRIGHT", -2, -151)
    ui.xpBar = CreateFrame("Frame", nil, ui.info, BT)
    ui.xpBar:SetSize(CONTENT_W, 16)
    ui.xpBar:SetPoint("TOPLEFT", ui.info, "TOPLEFT", 0, -170)
    Flat(ui.xpBar, C.card, C.border, 1)
    ui.xpFill = ui.xpBar:CreateTexture(nil, "ARTWORK")
    ui.xpFill:SetPoint("TOPLEFT", 1, -1)
    ui.xpFill:SetPoint("BOTTOMLEFT", 1, 1)
    ui.xpFill:SetColorTexture(C.purple[1], C.purple[2], C.purple[3], 1)
    ui.info:Hide()

    -- Rodape: ouro por hora da sessao
    local foot = CreateFrame("Frame", nil, f, BT)
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
    if tab then
        state.tab = tab
        state.mob = nil
        frame:Show()
        WD:Render()
        return
    end
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
    elseif cmd == "premium" or cmd == "lista" or cmd == "watchlist" then
        WD:ShowWatchList()
    elseif cmd == "nameplates" or cmd == "plaquinhas" or cmd == "alcance" then
        WD:MaxNameplateRange()
        print("|cffffd100Watchdog:|r " .. L.msg_nameplates)
    elseif cmd == "watch" or cmd == "marcar" then
        local n = strtrim(rest or "")
        if n == "" and UnitExists("target") and not UnitIsPlayer("target") then n = UnitName("target") end
        if n ~= "" and WD:AddWatch(n) then
            print("|cffffd100Watchdog:|r " .. string.format(L.msg_watch_added, n))
        else
            print("|cffffd100Watchdog:|r " .. L.msg_watch_usage)
        end
    elseif cmd == "unwatch" or cmd == "desmarcar" then
        local n = strtrim(rest or "")
        if n == "" and UnitExists("target") and not UnitIsPlayer("target") then n = UnitName("target") end
        if n ~= "" then
            WD:RemoveWatch(n)
            print("|cffffd100Watchdog:|r " .. string.format(L.msg_watch_removed, n))
        end
    elseif cmd == "relatorio" or cmd == "relatório" or cmd == "report" then
        WD:ShowReport()
    elseif cmd == "historico" or cmd == "histórico" or cmd == "history" then
        WD:Toggle("hist")
    elseif cmd == "inventario" or cmd == "inventário" or cmd == "bolsa" or cmd == "inventory" or cmd == "bag" then
        WD:Toggle("inv")
    elseif cmd == "alertas" or cmd == "alerta" then
        AlertsCommand(rest)
    elseif cmd == "debug" then
        WD.debug = not WD.debug
        print("|cffffd100Watchdog:|r " .. (WD.debug and L.debug_on or L.debug_off))
    elseif cmd == "status" then
        WD:PrintStatus()
    elseif cmd == "ajuda" or cmd == "help" then
        print("|cffffd100Watchdog|r " .. L.help_header)
        for _, line in ipairs({
            L.help_open, L.help_new, L.help_report, L.help_hist, L.help_inv,
            L.help_alerts, L.help_premium, L.help_watch, L.help_unwatch, L.help_nameplates,
            L.help_minimap, L.help_goldbar, L.help_expbar, L.help_sgoldbar, L.help_igoldbar,
            L.help_lang, L.help_status, L.help_debug,
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

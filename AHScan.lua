-- Watchdog: scan da casa de leiloes (preco minimo por item), tag no tooltip e busca.
local _, WD = ...
local L = WD.L

local scanning, ahOpen, processing = false, false, false
local panel               -- painel do scan (preso na janela da AH do WoW)
local evToken = 0
local CHUNK = 400
local scanStart

function WD:AHScanInfo()
    return WatchdogDB and WatchdogDB.ahScanTime, WatchdogDB and WatchdogDB.ahScanCount or 0
end

local function Dlog(msg)
    local d = WatchdogDB
    if not d then return end
    d.ahDiag = d.ahDiag or { api = {}, log = {} }
    local l = d.ahDiag.log
    l[#l + 1] = date("%H:%M:%S ") .. "scan: " .. tostring(msg)
    if #l > 80 then table.remove(l, 1) end
end

---------------------------------------------------------------------------
-- Painel do scan: botao + barra de progresso na janela da AH do WoW
---------------------------------------------------------------------------
local function AHFrame()
    return _G.AuctionHouseFrame or _G.AuctionFrame
end

-- state: "idle" | "wait" | "read" | "done" | "error"
local function Paint(state, pct, text, color)
    if not panel then return end
    panel.state = state
    panel.text:SetText(text or "")
    local c = color or { 0.8, 0.8, 0.85 }
    panel.text:SetTextColor(c[1], c[2], c[3])
    local busy = (state == "wait" or state == "read")
    panel.btn:SetEnabled(not busy)
    panel.bar:SetMinMaxValues(0, 100)
    if state == "read" then
        panel.bar:SetValue(pct or 0)
        panel.bar:SetStatusBarColor(0.2, 0.7, 1)
    elseif state == "done" then
        panel.bar:SetValue(100)
        panel.bar:SetStatusBarColor(0.2, 0.85, 0.3)
    elseif state == "error" then
        panel.bar:SetValue(100)
        panel.bar:SetStatusBarColor(0.9, 0.25, 0.25)
    elseif state == "wait" then
        panel.bar:SetValue(0)
        panel.bar:SetStatusBarColor(0.9, 0.7, 0.2)
    else
        panel.bar:SetValue(0)
    end
end

local function BuildPanel()
    if panel then return panel end
    local K = WD.UIKit
    local C = K.C
    panel = CreateFrame("Frame", "WatchdogScanPanel", UIParent, "BackdropTemplate")
    panel:SetSize(340, 64)
    panel:SetFrameStrata("DIALOG")
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    K.Flat(panel, C.bg, C.border, 0.97)

    -- faixa vermelha no topo (assinatura do Watchdog)
    local accent = panel:CreateTexture(nil, "OVERLAY")
    accent:SetColorTexture(C.red[1], C.red[2], C.red[3], 1)
    accent:SetPoint("TOPLEFT", 1, -1); accent:SetPoint("TOPRIGHT", -1, -1); accent:SetHeight(2)

    local icon = panel:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(K.MEDIA .. "emblem_icon")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 10, -9)
    local title = K.FS(panel, 12, C.text, "LEFT", "OUTLINE")
    title:SetPoint("LEFT", icon, "RIGHT", 7, 0)
    title:SetText("WATCHDOG  |cff9ea3afAH SCAN|r")

    -- botao no estilo do addon (plano, borda vermelha), nao o botao padrao do WoW
    local btn = CreateFrame("Button", "WatchdogAHScanButton", panel, "BackdropTemplate")
    btn:SetSize(86, 22)
    btn:SetPoint("TOPRIGHT", -10, -8)
    K.Flat(btn, C.tile, C.red, 1)
    btn.label = K.FS(btn, 11, C.text, "CENTER", "OUTLINE")
    btn.label:SetPoint("CENTER", 0, 0)
    btn.label:SetText(L.ah_btn_scan_short or "SCAN")
    btn.enabled = true
    btn.SetEnabled = function(self, on)
        self.enabled = on and true or false
        if on then
            K.Flat(self, C.tile, C.red, 1); self.label:SetTextColor(C.text[1], C.text[2], C.text[3])
        else
            K.Flat(self, C.card, C.border, 1); self.label:SetTextColor(C.mute[1], C.mute[2], C.mute[3])
        end
    end
    btn:SetScript("OnEnter", function(self) if self.enabled then K.Flat(self, C.border, C.red, 1) end end)
    btn:SetScript("OnLeave", function(self) if self.enabled then K.Flat(self, C.tile, C.red, 1) end end)
    btn:SetScript("OnClick", function(self) if self.enabled then WD:StartAHScan() end end)
    panel.btn = btn

    panel.text = K.FS(panel, 11, C.dim, "LEFT")
    panel.text:SetPoint("TOPLEFT", 10, -34)
    panel.text:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
    panel.text:SetWordWrap(false)
    panel.text:SetHeight(14)

    panel.bar = CreateFrame("StatusBar", nil, panel)
    panel.bar:SetPoint("BOTTOMLEFT", 10, 8)
    panel.bar:SetPoint("BOTTOMRIGHT", -10, 8)
    panel.bar:SetHeight(4)
    panel.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    local bg = panel.bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetColorTexture(C.tile[1], C.tile[2], C.tile[3], 1)
    panel:Hide()
    return panel
end

-- Prende o painel na janela da AH (acima do canto esquerdo); se a janela nao existir, fica solto e arrastavel.
local function Anchor()
    BuildPanel()
    local fr = AHFrame()
    panel:ClearAllPoints()
    if fr then
        panel:SetPoint("BOTTOMLEFT", fr, "TOPLEFT", 0, 4)
    else
        panel:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end
end


---------------------------------------------------------------------------
-- Resolve nomes de itens que o jogo nao devolveu no scan (cache do cliente vazio)
---------------------------------------------------------------------------
local nameQueue, nameBusy, nameDirty = nil, false, false
local nf = CreateFrame("Frame")
pcall(nf.RegisterEvent, nf, "GET_ITEM_INFO_RECEIVED")
nf:SetScript("OnEvent", function(_, _, id, ok)
    local e = id and WatchdogDB and WatchdogDB.ahPrices and WatchdogDB.ahPrices[id]
    if e and not e.n then
        local nm = GetItemInfo(id)
        if nm then e.n = nm; nameDirty = true end
    end
end)
local function NamePump()
    local P = WatchdogDB and WatchdogDB.ahPrices
    if not P then nameBusy = false; return end
    if not nameQueue then
        nameQueue = {}
        for id, e in pairs(P) do if not e.n then nameQueue[#nameQueue + 1] = id end end
    end
    local req = C_Item and C_Item.RequestLoadItemDataByID
    local cnt = 0
    while #nameQueue > 0 and cnt < 60 do
        local id = table.remove(nameQueue)
        local e = P[id]
        if e and not e.n then
            local nm = GetItemInfo(id)
            if nm then e.n = nm; nameDirty = true elseif req then pcall(req, id) end
        end
        cnt = cnt + 1
    end
    if nameDirty then
        nameDirty = false
        WD.ahIndex = nil
        if WD.RefreshAHTab then pcall(WD.RefreshAHTab, WD) end
    end
    if #nameQueue > 0 then C_Timer.After(0.4, NamePump)
    else
        nameQueue, nameBusy = nil, false
        -- ultima passada: pega o que chegou depois do pedido
        C_Timer.After(3, function()
            local miss = false
            for _, e in pairs(WatchdogDB.ahPrices or {}) do if not e.n then miss = true break end end
            if miss and not nameBusy then
                for id, e in pairs(WatchdogDB.ahPrices) do if not e.n then local nm = GetItemInfo(id); if nm then e.n = nm end end end
                WD.ahIndex = nil
                if WD.RefreshAHTab then pcall(WD.RefreshAHTab, WD) end
            end
        end)
    end
end
function WD:ResolveAHNames()
    if nameBusy then return end
    nameBusy, nameQueue = true, nil
    NamePump()
end

local function Finish(prices, count)
    scanning, processing = false, false
    WatchdogDB.ahPrices = prices
    WatchdogDB.ahScanTime = time()
    WatchdogDB.ahScanCount = count
    WD.ahIndex = nil
    local secs = scanStart and math.max(1, math.floor(GetTime() - scanStart)) or 0
    Dlog("done " .. count .. " itens em " .. secs .. "s")
    Paint("done", 100, string.format(L.ah_done_panel, count, secs), { 0.3, 0.9, 0.4 })
    print("|cffffd100Watchdog:|r " .. string.format(L.ah_scan_done, count))
    WD:BumpValuation()
    WD:ResolveAHNames()
    if WD.RefreshAHTab then WD:RefreshAHTab() end
end

local function Fail(msg)
    scanning, processing = false, false
    Dlog("erro: " .. msg)
    Paint("error", 100, msg, { 1, 0.4, 0.4 })
    print("|cffffd100Watchdog:|r " .. msg)
end

-- Processa a lista do leilao em pedacos (nao trava o jogo) mostrando o progresso.
local function Process()
    if processing then return end
    processing = true
    local A = C_AuctionHouse
    local n = A.GetNumReplicateItems and A.GetNumReplicateItems() or 0
    Dlog("lista recebida: " .. n .. " leiloes")
    if n <= 0 then Fail(L.ah_scan_empty); return end
    local prices, count, i = {}, 0, 1
    local stSold, stNoBuy, stNoId, stOk = 0, 0, 0, 0
    local function step()
        if not scanning then return end
        local last = math.min(n, i + CHUNK - 1)
        for k = i, last do
            local ok, name, _, cnt, _, _, _, _, _, _, buyout, _, _, _, _, _, saleStatus, itemID = pcall(A.GetReplicateItemInfo, k)
            if not (ok and itemID) then stNoId = stNoId + 1
            elseif saleStatus == 1 then stSold = stSold + 1
            else
                cnt = tonumber(cnt) or 1
                buyout = tonumber(buyout) or 0
                if buyout <= 0 then stNoBuy = stNoBuy + 1 end
                if cnt > 0 and buyout > 0 then
                    stOk = stOk + 1
                    local unit = buyout / cnt
                    local e = prices[itemID]
                    if not e then
                        e = { p = unit, q = 0 }
                        prices[itemID] = e
                        count = count + 1
                    elseif unit < e.p then
                        e.p = unit
                    end
                    e.q = e.q + cnt
                    if (not e.n) and name and name ~= "" then e.n = name end
                end
            end
        end
        local pct = math.floor(last / n * 100)
        Paint("read", pct, string.format(L.ah_reading, last, n, pct), { 0.6, 0.85, 1 })
        if last >= n then
            for id, e in pairs(prices) do
                if not e.n then local nm = GetItemInfo(id); if nm then e.n = nm end end
                e.p = math.floor(e.p + 0.5)
            end
            Dlog(string.format("auctions=%d usable=%d no_buyout=%d sold=%d no_item=%d items=%d", n, stOk, stNoBuy, stSold, stNoId, count))
            print(string.format("|cffffd100Watchdog:|r %d auctions read: %d with buyout, %d bid-only (skipped), %d invalid", n, stOk, stNoBuy, stSold + stNoId))
            if count == 0 then Fail(L.ah_scan_empty) else Finish(prices, count) end
        else
            i = last + 1
            C_Timer.After(0, step)
        end
    end
    step()
end

function WD:StartAHScan()
    if scanning then return end
    local A = C_AuctionHouse
    if not ahOpen then print("|cffffd100Watchdog:|r " .. L.ah_open_first); return end
    Anchor(); panel:Show()
    if not (A and A.ReplicateItems) then Fail(L.ah_noapi); return end
    scanning, processing = true, false
    scanStart = GetTime()
    evToken = evToken + 1
    Paint("wait", 0, L.ah_waiting, { 1, 0.85, 0.3 })
    local ok, err = pcall(A.ReplicateItems)
    Dlog("ReplicateItems ok=" .. tostring(ok) .. " err=" .. tostring(err))
    if not ok then Fail(L.ah_noapi); return end
    -- contador de espera + tempo limite (o jogo pode demorar ou limitar a frequencia do scan)
    local token = evToken
    local function tick()
        if not scanning or token ~= evToken or processing then return end
        local waited = math.floor(GetTime() - scanStart)
        if waited >= 90 then Fail(L.ah_timeout); return end
        if waited >= 15 and not WD._replicating then
            -- a AH limita novos pedidos: usa a lista que o jogo ja tem em memoria, se houver
            local n = A.GetNumReplicateItems and A.GetNumReplicateItems() or 0
            if n > 0 then
                Dlog("sem resposta em " .. waited .. "s; usando a lista em memoria (" .. n .. ")")
                print("|cffffd100Watchdog:|r " .. L.ah_cached)
                Process()
                return
            end
        end
        if not WD._replicating then
            Paint("wait", 0, string.format(L.ah_waiting_s, waited), { 1, 0.85, 0.3 })
        end
        C_Timer.After(1, tick)
    end
    C_Timer.After(1, tick)
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "REPLICATE_ITEM_LIST_UPDATE",
    "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" }) do pcall(f.RegisterEvent, f, e) end
f:SetScript("OnEvent", function(_, event)
    if event == "AUCTION_HOUSE_SHOW" then
        ahOpen = true
        Dlog("AH aberta; janela=" .. tostring(AHFrame() and (AHFrame():GetName() or "?") or "nenhuma"))
        Anchor(); panel:Show()
        if not scanning then
            local t, cnt = WD:AHScanInfo()
            if t then
                Paint("idle", 0, string.format(L.ah_last_panel, cnt, date("%d/%m %H:%M", t)), { 0.7, 0.7, 0.75 })
            else
                Paint("idle", 0, L.ah_panel_hint, { 0.7, 0.7, 0.75 })
            end
        end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        ahOpen = false
        if scanning then scanning, processing = false, false; Dlog("AH fechada durante o scan") end
        if panel then panel:Hide() end
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
        Dlog("evento REPLICATE_ITEM_LIST_UPDATE (scanning=" .. tostring(scanning) .. ")")
        if scanning and not processing then
            WD._replicating = true
            evToken = evToken + 1
            local token = evToken
            -- espera a lista "assentar" (pode chegar em varios eventos)
            Paint("wait", 0, L.ah_receiving, { 1, 0.85, 0.3 })
            C_Timer.After(1.0, function()
                if token == evToken and scanning and not processing then
                    WD._replicating = nil
                    Process()
                end
            end)
        end
    elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_DROPPED" then
        Dlog("throttled: mensagem descartada")
        if scanning and not processing then Fail(L.ah_busy) end
    end
end)

---------------------------------------------------------------------------
-- Tag no tooltip: "Watchdog AH: preco" (abaixo do vendor)
---------------------------------------------------------------------------
local function AgeText()
    local t = WatchdogDB and WatchdogDB.ahScanTime
    if not t then return "" end
    local h = (time() - t) / 3600
    if h < 1 then return string.format("  |cff808080(%dm)|r", math.max(1, math.floor(h * 60))) end
    if h < 48 then return string.format("  |cff808080(%dh)|r", math.floor(h)) end
    return string.format("  |cff808080(%dd)|r", math.floor(h / 24))
end

-- Moeda com icones (ouro/prata/cobre) montada na mao, igual ao tooltip do jogo.
local function TipCoin(c)
    c = math.floor(tonumber(c) or 0)
    local g, sv, cp = math.floor(c / 10000), math.floor((c % 10000) / 100), c % 100
    local function ic(n) return "|TInterface\\MoneyFrame\\UI-" .. n .. "Icon:0:0:2:0|t" end
    local out = ""
    if g > 0 then out = out .. g .. ic("Gold") .. " " end
    if g > 0 or sv > 0 then out = out .. sv .. ic("Silver") .. " " end
    return out .. cp .. ic("Copper")
end

local function AddTag(tt, itemID)
    if not itemID or not tt or not tt.AddDoubleLine then return end
    local p = WD:AHPrice(itemID)
    if not p then return end
    local coin = TipCoin(math.floor(p))
    tt:AddDoubleLine("|cff4fd1c5Watchdog AH|r", coin .. AgeText(), 1, 1, 1, 1, 1, 1)
    if tt.Show then tt:Show() end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
        if data and data.id then pcall(AddTag, tt, data.id) end
    end)
else
    local function hook(tt)
        if not (tt and tt.HookScript) then return end
        tt:HookScript("OnTooltipCleared", function(self) self._wdAH = nil end)
        tt:HookScript("OnTooltipSetItem", function(self)
            if self._wdAH then return end
            local _, link = self:GetItem()
            local id = link and tonumber(link:match("item:(%d+)"))
            if id then self._wdAH = true; pcall(AddTag, self, id) end
        end)
    end
    hook(GameTooltip); hook(ItemRefTooltip)
end

---------------------------------------------------------------------------
-- Indice de busca (para a aba AH)
---------------------------------------------------------------------------
function WD:AHIndex()
    if WD.ahIndex then return WD.ahIndex end
    if not WD._namesAsked then WD._namesAsked = true; C_Timer.After(1, function() WD:ResolveAHNames() end) end
    local list = {}
    for id, e in pairs(WatchdogDB.ahPrices or {}) do
        local name = e.n
        if not name then local nm = GetItemInfo(id); name = nm end
        list[#list + 1] = { id = id, name = name or ("Item #" .. id), lname = (name or ""):lower(), p = e.p, q = e.q or 0 }
    end
    table.sort(list, function(a, b) return a.lname < b.lname end)
    WD.ahIndex = list
    return list
end

---------------------------------------------------------------------------
-- Contornos coloridos: prata = vale mais no vendor, dourado = vale mais na AH
---------------------------------------------------------------------------
WD.PALETTE = {
    { key = "silver", c = { 0.78, 0.80, 0.85 } }, { key = "gold", c = { 1.00, 0.82, 0.00 } },
    { key = "white", c = { 1, 1, 1 } }, { key = "green", c = { 0.20, 0.85, 0.30 } },
    { key = "blue", c = { 0.30, 0.60, 1.00 } }, { key = "purple", c = { 0.70, 0.40, 1.00 } },
    { key = "red", c = { 1.00, 0.30, 0.30 } }, { key = "orange", c = { 1.00, 0.55, 0.10 } },
    { key = "cyan", c = { 0.30, 0.90, 0.90 } },
}
function WD:BorderOpt()
    local o = WD:AHOpt()
    o.border = o.border or {}
    local b = o.border
    if b.on == nil then b.on = false end
    if not b.v2 then b.vk, b.ak, b.v2 = "blue", "orange", true end   -- padrao: vendor azul, AH laranja
    b.vk = b.vk or "blue"
    b.ak = b.ak or "orange"
    return b
end
local function PaletteColor(key)
    for _, p in ipairs(WD.PALETTE) do if p.key == key then return p.c end end
    return WD.PALETTE[1].c
end
function WD:CycleBorderColor(which)
    local b = WD:BorderOpt()
    local field = (which == "ah") and "ak" or "vk"
    local idx = 1
    for i, p in ipairs(WD.PALETTE) do if p.key == b[field] then idx = i end end
    b[field] = WD.PALETTE[idx % #WD.PALETTE + 1].key
end
-- Cor do contorno de um item (nil = sem contorno).
function WD:ItemBorderColor(itemID, bound)
    local b = WD:BorderOpt()
    if not b.on or not itemID then return nil end
    local _, _, sell = WD:GetItemDisplay(itemID)
    local v, isA = WD:UnitValue(itemID, sell, bound)
    if isA then return PaletteColor(b.ak) end
    if v and v > 0 then return PaletteColor(b.vk) end
    return nil
end
-- Item que nao da pra vender de nenhum jeito (nem vendor nem AH): fica "apagado".
function WD:ItemDimmed(itemID, bound)
    if not itemID then return false end
    if WD:IsQuestItem(itemID) then return true end
    local _, _, sell = WD:GetItemDisplay(itemID)
    if (tonumber(sell) or 0) > 0 then return false end
    return not WD:CanAuction(itemID, bound)
end
function WD:ToggleBorders()
    local b = WD:BorderOpt()
    b.on = not b.on
    WD:UpdateBagBorders()
    if WD.RefreshBagButton then WD:RefreshBagButton() end
    if WD.Refresh then WD:Refresh() end
end

-- Contornos nas bolsas do proprio jogo (quando abertas). Protegido: se o cliente tiver outro layout, nao quebra.
local function Edge(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints(parent)
    f:SetFrameLevel((parent:GetFrameLevel() or 1) + 5)
    f.t = {}
    for i = 1, 4 do f.t[i] = f:CreateTexture(nil, "OVERLAY") end
    f.t[1]:SetPoint("TOPLEFT"); f.t[1]:SetPoint("TOPRIGHT"); f.t[1]:SetHeight(2)
    f.t[2]:SetPoint("BOTTOMLEFT"); f.t[2]:SetPoint("BOTTOMRIGHT"); f.t[2]:SetHeight(2)
    f.t[3]:SetPoint("TOPLEFT"); f.t[3]:SetPoint("BOTTOMLEFT"); f.t[3]:SetWidth(2)
    f.t[4]:SetPoint("TOPRIGHT"); f.t[4]:SetPoint("BOTTOMRIGHT"); f.t[4]:SetWidth(2)
    return f
end
local function Collect(out, frame)
    if not frame or not frame:IsShown() then return end
    if frame.EnumerateValidItems then
        for _, b in frame:EnumerateValidItems() do out[#out + 1] = b end
    elseif frame.Items then
        for _, b in ipairs(frame.Items) do out[#out + 1] = b end
    else
        local name = frame:GetName()
        for j = 1, 40 do
            local b = name and _G[name .. "Item" .. j]
            if b then out[#out + 1] = b end
        end
    end
end
local seenButtons = {}
function WD:UpdateBagBorders()
    local on = WD:BorderOpt().on
    local btns = {}
    pcall(function()
        Collect(btns, _G.ContainerFrameCombinedBags)
        for i = 1, (NUM_CONTAINER_FRAMES or 13) do Collect(btns, _G["ContainerFrame" .. i]) end
    end)
    for _, b in ipairs(btns) do
        local ok = pcall(function()
            local bag = b.GetBagID and b:GetBagID() or (b:GetParent() and b:GetParent():GetID())
            local id = b.GetID and b:GetID()
            local info = C_Container and C_Container.GetContainerItemInfo and bag and id and C_Container.GetContainerItemInfo(bag, id)
            local itemID, bound = info and info.itemID, info and info.isBound
            local icon = b.icon or b.Icon
            if icon and icon.SetAlpha then
                if on and itemID and WD:ItemDimmed(itemID, bound) then
                    icon:SetAlpha(0.3); b._wdDim = true
                elseif b._wdDim then
                    icon:SetAlpha(1); b._wdDim = nil
                end
            end
            local col = on and itemID and WD:ItemBorderColor(itemID, bound) or nil
            if col then
                b._wdEdge = b._wdEdge or Edge(b)
                for _, t in ipairs(b._wdEdge.t) do t:SetColorTexture(col[1], col[2], col[3], 1) end
                b._wdEdge:Show()
                seenButtons[b] = true
            elseif b._wdEdge then
                b._wdEdge:Hide()
            end
        end)
    end
    if not on then
        for b in pairs(seenButtons) do if b._wdEdge then b._wdEdge:Hide() end end
        for _, b in ipairs(btns) do
            if b._wdDim then
                local icon = b.icon or b.Icon
                if icon and icon.SetAlpha then icon:SetAlpha(1) end
                b._wdDim = nil
            end
        end
    end
end
-- Botao liga/desliga preso na bolsa do jogo (acima da janela da bolsa que estiver aberta).
local bagBtn
local function FirstBagFrame()
    local c = _G.ContainerFrameCombinedBags
    if c and c:IsShown() then return c end
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local fr = _G["ContainerFrame" .. i]
        if fr and fr:IsShown() then return fr end
    end
    return nil
end
local function PaintBagBtn()
    if not bagBtn then return end
    local on = WD:BorderOpt().on
    local c = on and { 0.2, 0.85, 0.3 } or { 0.45, 0.45, 0.5 }
    for _, t in ipairs(bagBtn.edge) do t:SetColorTexture(c[1], c[2], c[3], 1) end
    bagBtn.icon:SetDesaturated(not on)
end
local function UpdateBagBtn()
    local fr = FirstBagFrame()
    if not fr then if bagBtn then bagBtn:Hide() end return end
    if not bagBtn then
        bagBtn = CreateFrame("Button", "WatchdogBagBorderButton", UIParent)
        bagBtn:SetSize(24, 24)
        bagBtn:SetFrameStrata("HIGH")
        bagBtn.icon = bagBtn:CreateTexture(nil, "ARTWORK")
        bagBtn.icon:SetPoint("TOPLEFT", 2, -2); bagBtn.icon:SetPoint("BOTTOMRIGHT", -2, 2)
        bagBtn.icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
        bagBtn.edge = {}
        for i = 1, 4 do bagBtn.edge[i] = bagBtn:CreateTexture(nil, "OVERLAY") end
        bagBtn.edge[1]:SetPoint("TOPLEFT"); bagBtn.edge[1]:SetPoint("TOPRIGHT"); bagBtn.edge[1]:SetHeight(2)
        bagBtn.edge[2]:SetPoint("BOTTOMLEFT"); bagBtn.edge[2]:SetPoint("BOTTOMRIGHT"); bagBtn.edge[2]:SetHeight(2)
        bagBtn.edge[3]:SetPoint("TOPLEFT"); bagBtn.edge[3]:SetPoint("BOTTOMLEFT"); bagBtn.edge[3]:SetWidth(2)
        bagBtn.edge[4]:SetPoint("TOPRIGHT"); bagBtn.edge[4]:SetPoint("BOTTOMRIGHT"); bagBtn.edge[4]:SetWidth(2)
        bagBtn:SetScript("OnClick", function() WD:ToggleBorders(); PaintBagBtn() end)
        bagBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Watchdog: " .. L.inv_borders)
            GameTooltip:AddLine(L.inv_borders_tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        bagBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    if bagBtn._anchor ~= fr then
        bagBtn:ClearAllPoints()
        bagBtn:SetPoint("BOTTOMRIGHT", fr, "TOPRIGHT", -4, 2)
        bagBtn._anchor = fr
    end
    bagBtn:Show()
    PaintBagBtn()
end
function WD:RefreshBagButton() pcall(UpdateBagBtn) end

local acc = 0
f:SetScript("OnUpdate", function(_, el)
    acc = acc + el
    if acc < 0.7 then return end
    acc = 0
    pcall(UpdateBagBtn)
    if WD:BorderOpt().on then pcall(WD.UpdateBagBorders, WD) end
end)

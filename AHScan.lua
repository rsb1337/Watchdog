-- Watchdog: scan da casa de leiloes (preco minimo por item), tag no tooltip e busca.
local _, WD = ...
local L = WD.L

local scanning, ahOpen, processing = false, false, false
local scanBtn
local CHUNK = 400

function WD:AHScanInfo()
    return WatchdogDB and WatchdogDB.ahScanTime, WatchdogDB and WatchdogDB.ahScanCount or 0
end

local function SetBtn(text)
    if scanBtn then scanBtn:SetText(text) end
end

local function Finish(prices, count)
    scanning, processing = false, false
    WatchdogDB.ahPrices = prices
    WatchdogDB.ahScanTime = time()
    WatchdogDB.ahScanCount = count
    WD.ahIndex = nil
    SetBtn(L.ah_btn_scan)
    print("|cffffd100Watchdog:|r " .. string.format(L.ah_scan_done, count))
    WD:BumpValuation()
    if WD.RefreshAHTab then WD:RefreshAHTab() end
end

-- Processa a lista do leilao em pedacos (nao trava o jogo).
local function Process()
    if processing then return end
    processing = true
    local A = C_AuctionHouse
    local n = A.GetNumReplicateItems and A.GetNumReplicateItems() or 0
    if n <= 0 then
        scanning = false; processing = false; SetBtn(L.ah_btn_scan)
        print("|cffffd100Watchdog:|r " .. L.ah_scan_empty)
        return
    end
    local prices, count, i = {}, 0, 1
    local function step()
        if not scanning then return end
        local last = math.min(n, i + CHUNK - 1)
        for k = i, last do
            local ok, name, _, cnt, _, _, _, _, _, _, buyout, _, _, _, _, _, saleStatus, itemID = pcall(A.GetReplicateItemInfo, k)
            if ok and itemID and (saleStatus ~= 1) then
                cnt = tonumber(cnt) or 1
                buyout = tonumber(buyout) or 0
                if cnt > 0 and buyout > 0 then
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
        SetBtn(string.format(L.ah_btn_progress, math.floor(last / n * 100)))
        if last >= n then
            -- completa nomes que o cliente ainda nao devolveu
            for id, e in pairs(prices) do
                if not e.n then local nm = GetItemInfo(id); if nm then e.n = nm end end
                e.p = math.floor(e.p + 0.5)
            end
            Finish(prices, count)
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
    if not (A and A.ReplicateItems) then print("|cffffd100Watchdog:|r " .. L.ah_noapi); return end
    scanning = true
    SetBtn(L.ah_btn_wait)
    local ok = pcall(A.ReplicateItems)
    if not ok then scanning = false; SetBtn(L.ah_btn_scan); print("|cffffd100Watchdog:|r " .. L.ah_noapi); return end
    C_Timer.After(25, function()
        if scanning and not WD._replicating then
            scanning = false; SetBtn(L.ah_btn_scan)
            print("|cffffd100Watchdog:|r " .. L.ah_timeout)
        end
    end)
end

local function MakeButton()
    if scanBtn or not AuctionHouseFrame then return end
    scanBtn = CreateFrame("Button", "WatchdogAHScanButton", AuctionHouseFrame, "UIPanelButtonTemplate")
    scanBtn:SetSize(130, 22)
    scanBtn:SetPoint("TOPRIGHT", AuctionHouseFrame, "TOPRIGHT", -34, -2)
    scanBtn:SetText(L.ah_btn_scan)
    scanBtn:SetScript("OnClick", function() WD:StartAHScan() end)
    scanBtn:SetFrameLevel((AuctionHouseFrame:GetFrameLevel() or 1) + 10)
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "REPLICATE_ITEM_LIST_UPDATE" }) do pcall(f.RegisterEvent, f, e) end
f:SetScript("OnEvent", function(_, event)
    if event == "AUCTION_HOUSE_SHOW" then
        ahOpen = true
        MakeButton()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        ahOpen = false
        if scanning then scanning, processing = false, false; SetBtn(L.ah_btn_scan) end
    elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
        if scanning and not processing then
            WD._replicating = true
            C_Timer.After(0.2, function() WD._replicating = nil; if scanning then Process() end end)
        end
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

local function AddTag(tt, itemID)
    if not itemID or not tt or not tt.AddDoubleLine then return end
    local p = WD:AHPrice(itemID)
    if not p then return end
    local coin = GetCoinTextureString and GetCoinTextureString(math.floor(p)) or tostring(math.floor(p))
    tt:AddDoubleLine("|cff4fd1c5Watchdog AH|r", coin .. AgeText())
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
    b.vk = b.vk or "silver"
    b.ak = b.ak or "gold"
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
function WD:ItemBorderColor(itemID)
    local b = WD:BorderOpt()
    if not b.on or not itemID then return nil end
    local _, _, sell = WD:GetItemDisplay(itemID)
    local v, isA = WD:UnitValue(itemID, sell)
    if isA then return PaletteColor(b.ak) end
    if v and v > 0 then return PaletteColor(b.vk) end
    return nil
end
function WD:ToggleBorders()
    local b = WD:BorderOpt()
    b.on = not b.on
    WD:UpdateBagBorders()
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
            local itemID = C_Container and C_Container.GetContainerItemID and bag and id and C_Container.GetContainerItemID(bag, id)
            local col = on and itemID and WD:ItemBorderColor(itemID) or nil
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
    end
end
local acc = 0
f:SetScript("OnUpdate", function(_, el)
    acc = acc + el
    if acc < 0.7 then return end
    acc = 0
    if WD:BorderOpt().on then pcall(WD.UpdateBagBorders, WD) end
end)

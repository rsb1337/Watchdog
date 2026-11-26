-- Watchdog: rastreamento de kills PvE/PvP, honra, drops, dinheiro, EXP e inventario.
-- Usa eventos de chat/XP/honra/loot e o combat log (apenas leitura) para mortes PvP.
-- Tudo vem de eventos de chat, XP, honra, loot e bolsas.
local ADDON, WD = ...
local function GetItemInfo(...) local f = _G.GetItemInfo or (C_Item and C_Item.GetItemInfo); if f then return f(...) end end
local L = WD.L
WD.version = "1.9.15"
WD.debug = false
WD.failed = {}
WD.stats = { mobKills = 0, pvpKills = 0, pvpDeaths = 0, xpMsgs = 0, slainMsgs = 0, honorMsgs = 0, drops = 0, moneyMsgs = 0 }

-- Cliente novo: nomes/GUIDs de unidades podem ser "secret values" (principalmente
-- em combate). Nunca indexar/concatenar um: devolve nil se for secreto.
local issecret = _G.issecretvalue
function WD.Clean(v)
    if v == nil then return nil end
    if issecret and issecret(v) then return nil end
    return v
end
local Clean = WD.Clean

local GetTime = GetTime
local strsplit = strsplit

local LOOT_ITEM = LOOT_SLOT_ITEM or 1

local PVP_DEATH_WINDOW = 15   -- segundos apos dano de jogador inimigo para contar morte PvP
local EVENT_WINDOW = 3        -- segundos para casar mensagens duplicadas da mesma kill
local CORPSE_TTL = 1800       -- quanto tempo um corpo pode ser lootado
local MONEY_WINDOW = 60       -- segundos entre abrir o loot e pegar o dinheiro
local HISTORY_MAX = 50

local playerGUID, petGUID
local lastPvPHit = 0
local lastPvPAttacker = nil
local lastXP, lastMaxXP, lastLevel
local lastLootName, lastLootTime = nil, 0

local PAT = {}                -- padroes montados a partir das strings globais do jogo
local pend = { slain = {}, xp = {} }
local recentKills = {}        -- { name, t, claimed }
local corpseName = {}         -- [guid] = { name, t }
local guidMob = {}            -- [guid] = nome do mob ja resolvido para esse corpo
local lootSeen = {}           -- ["guid:itemID"] = GetTime()
local guidHit = {}            -- [guid] = true quando o corpo ja rendeu ao menos 1 item
local alertSeen = {}          -- ["guid:itemID"] = GetTime()
local rareSeen = {}           -- [guid] = GetTime()

local function Dbg(...)
    if WD.debug then print("|cff00ccffWD:|r", ...) end
end

-- A UI define WD:ShowAlert. kind: "drop" | "rare" | "rarekill"
-- Sons dos alertas: catalogo de sons do proprio WoW (SoundKit IDs). Padrao: aviso de raide (8959).
WD.SOUNDS = {
    { key = "raid", id = 8959 }, { key = "ready", id = 8960 }, { key = "levelup", id = 888 },
    { key = "quest", id = 878 }, { key = "ping", id = 3175 }, { key = "whisper", id = 3081 },
    { key = "coin", id = 120 }, { key = "auction", id = 5274 }, { key = "boss", id = 11773 },
    { key = "alarm", id = 12867 }, { key = "off", id = 0 },
}
function WD:SoundIndex(cat)
    local sv = WatchdogDB and WatchdogDB.alerts and WatchdogDB.alerts.sounds
    local key = sv and sv[cat] or "raid"
    for i, e in ipairs(WD.SOUNDS) do if e.key == key then return i end end
    return 1
end
function WD:SetSound(cat, idx)
    WatchdogDB.alerts = WatchdogDB.alerts or {}
    WatchdogDB.alerts.sounds = WatchdogDB.alerts.sounds or {}
    WatchdogDB.alerts.sounds[cat] = WD.SOUNDS[idx].key
end
-- Toca o som da categoria. Se o cliente nao tiver o som, cai no padrao e retorna false.
function WD:PlayAlertSound(cat)
    local e = WD.SOUNDS[WD:SoundIndex(cat)]
    if e.id == 0 then return true end
    local ok, will = pcall(PlaySound, e.id)
    if (not ok or will == false) and e.id ~= 8959 then pcall(PlaySound, 8959); return false end
    return true
end

function WD:Alert(kind, title, text, icon)
    if WD.ShowAlert then WD:ShowAlert(kind, title, text, icon) end
end

local function AddKillXP(amount)
    local s = WatchdogCharDB.session
    s.killXP = (s.killXP or 0) + amount
    s.killXPCount = (s.killXPCount or 0) + 1
end

---------------------------------------------------------------------------
-- Dados
---------------------------------------------------------------------------
local function NewBucket()
    return { pvp = { kills = 0, deaths = 0, honor = 0 }, mobs = {}, xp = 0, money = 0 }
end
WD.NewBucket = NewBucket

local function GetMob(bucket, name)
    local m = bucket.mobs[name]
    if not m then
        m = { kills = 0, loot = {}, lootN = {}, money = 0, hit = 0 }
        bucket.mobs[name] = m
    end
    return m
end
WD.GetMob = GetMob

local T_KEYS = { "grind", "flight", "afk", "craft", "dead", "other" }
WD.T_KEYS = T_KEYS

local function NewTimes()
    local t = {}
    for _, k in ipairs(T_KEYS) do t[k] = 0 end
    return t
end

local function BucketKills(s)
    local kills = 0
    for _, m in pairs(s.mobs or {}) do kills = kills + (m.kills or 0) end
    return kills
end

-- Converte o bucket da sessao num registro (mesmo formato do historico).
local function EntryFromBucket(s, start, stop)
    local pvp = s.pvp or {}
    local t = {}
    for _, k in ipairs(T_KEYS) do t[k] = math.floor((s.t and s.t[k]) or 0) end
    local e = {
        start = start, stop = stop,
        kills = BucketKills(s),
        xp = s.xp or 0,
        killXP = s.killXP or 0,
        questXP = s.questXP or 0,
        quests = s.quests or 0,
        levels = s.levels or 0,
        pvpKills = pvp.kills or 0,
        deaths = pvp.deaths or 0,
        honor = pvp.honor or 0,
        money = s.money or 0,
        income = s.farmCoin or 0, spent = s.spent,
        bagDelta = s.farmItems or 0,
        bagDeltaA = s.farmItemsA or 0,
        value = WD:BucketValue(s),
        t = t,
    }
    -- Itens listados na AH nao entram mais no ouro (o valor ja vem do maior entre vendor e AH): fica 0.
    e.ahPrice, e.ahVendor, e.ahVendorA = 0, 0, 0
    return e
end

-- Guarda a sessao que acabou no historico.
local function ArchiveSession()
    local s = WatchdogCharDB.session
    if not s then return end
    local start = WatchdogCharDB.sessionStart or time()
    local stop = WatchdogCharDB.sessionLast or time()
    local dur = stop - start
    local e = EntryFromBucket(s, start, stop)
    local active = e.kills > 0 or e.xp > 0 or e.pvpKills > 0 or e.money > 0 or e.quests > 0
    -- Sessoes sem atividade tambem entram se foram longas (contam no tempo online).
    if not ((active and dur >= 60) or dur >= 120) then return end

    local h = WatchdogCharDB.history
    h[#h + 1] = e
    while #h > HISTORY_MAX do table.remove(h, 1) end
end

local function NewSession()
    ArchiveSession()
    local s = NewBucket()
    s.killXP, s.killXPCount, s.levels = 0, 0, 0
    s.questXP, s.quests = 0, 0
    s.t = NewTimes()
    s.income, s.spent = 0, 0
    s.farmCoin, s.farmItems, s.farmItemsA = 0, 0, 0
    WatchdogCharDB.session = s
    WatchdogCharDB.sessionStart = time()
    WatchdogCharDB.sessionLast = time()
end

-- Registro de uma entrada do historico (campos novos podem faltar em sessoes antigas).
function WD:RecordOf(e, now)
    local stop = e.stop or now or e.start
    local r = {
        start = e.start, stop = stop, dur = math.max(0, stop - e.start),
        kills = e.kills or 0, xp = e.xp or 0, killXP = e.killXP, questXP = e.questXP,
        quests = e.quests, levels = e.levels or 0,
        pvpKills = e.pvpKills or 0, deaths = e.deaths or 0, honor = e.honor or 0,
        money = e.money or 0, income = e.income, spent = e.spent, bagDelta = e.bagDelta, value = e.value or 0, t = e.t,
        ahPrice = e.ahPrice or 0, ahVendor = e.ahVendor or 0,
        bagDeltaA = e.bagDeltaA, ahVendorA = e.ahVendorA or 0,
    }
    return r
end

-- Ouro farmado da sessao (a partir da 1.9.14):
--   puro      = ouro dropado + recompensa de ouro de quest
--   inventario= valor dos itens de loot/skinning/pickpocket/quest NO MOMENTO DO DROP (maior entre vendor e AH, regra da %)
--   ah        = parte do inventario valorizada pela AH
--   provavel  = puro + inventario (nunca subtrai; vender/usar/postar o item nao altera)
-- (sessoes antigas salvas usam a conta anterior: variacao das bolsas)
function WD:GoldSummary(r)
    if r.income == nil then
        return { probable = r.value or 0, legacy = true }
    end
    local inv = (r.bagDelta or 0) - (r.ahVendor or 0)          -- itens (vendor + AH), sem os listados
    local invA = (r.bagDeltaA or 0) - (r.ahVendorA or 0)       -- parte valorizada pela AH
    local posted = r.ahPrice or 0
    return {
        coin = r.income,
        inv = inv,
        invA = invA,
        invV = inv - invA,
        ah = posted + invA,
        probable = math.max(0, r.income + inv + posted),
    }
end

-- Gold provavel da sessao atual (puro + inventario + AH): e o numero "da sessao" em toda a interface.
function WD:SessionProbable()
    local s = WatchdogCharDB.session
    if not s then return 0 end
    local ahP, ahV, ahVA = 0, 0, 0   -- listar na AH nao altera o ouro da sessao
    local r = {
        income = s.farmCoin or 0,
        bagDelta = s.farmItems or 0,
        bagDeltaA = s.farmItemsA or 0,
        ahPrice = ahP, ahVendor = ahV, ahVendorA = ahVA,
    }
    return WD:GoldSummary(r).probable
end

function WD:CurrentRecord()
    pcall(WD.UpdateBagValue, WD)
    local now = time()
    local e = EntryFromBucket(WatchdogCharDB.session, WatchdogCharDB.sessionStart or now, now)
    return WD:RecordOf(e, now)
end

function WD:HistoryRecord(i)
    local e = WatchdogCharDB.history[i]
    return e and WD:RecordOf(e) or nil
end

-- Janela por tempo (ex.: ultimas 24h): soma as sessoes (proporcional ao trecho que cai na
-- janela) e calcula o tempo offline = janela (desde a 1a sessao registrada) - tempo online.
local SUM_KEYS = { "kills", "xp", "killXP", "questXP", "quests", "levels", "pvpKills", "deaths", "honor", "money", "income", "spent", "bagDelta", "bagDeltaA", "value", "ahPrice", "ahVendor", "ahVendorA" }
function WD:WindowRecord(hours)
    pcall(WD.UpdateBagValue, WD)
    local now = time()
    local cutoff = now - hours * 3600
    local list = {}
    for _, e in ipairs(WatchdogCharDB.history or {}) do list[#list + 1] = e end
    list[#list + 1] = EntryFromBucket(WatchdogCharDB.session, WatchdogCharDB.sessionStart or now, now)

    local out = { t = NewTimes(), unknown = 0, sessions = 0 }
    for _, k in ipairs(SUM_KEYS) do out[k] = 0 end
    local first, online = nil, 0
    for _, e in ipairs(list) do
        local st, sp = e.start, e.stop or e.start
        if not first or st < first then first = st end
        local a, b = math.max(st, cutoff), math.min(sp, now)
        if b > a then
            local dur = math.max(1, sp - st)
            local f = (b - a) / dur
            online = online + (b - a)
            out.sessions = out.sessions + 1
            for _, k in ipairs(SUM_KEYS) do out[k] = out[k] + (e[k] or 0) * f end
            if e.income == nil then out.goldPartial = true end
            if e.t then
                for _, k in ipairs(T_KEYS) do out.t[k] = out.t[k] + (e.t[k] or 0) * f end
            else
                out.unknown = out.unknown + (b - a)
            end
        end
    end
    for _, k in ipairs(SUM_KEYS) do out[k] = math.floor(out[k] + 0.5) end
    local span = now - math.max(cutoff, first or now)
    out.start, out.stop, out.span = math.max(cutoff, first or now), now, span
    out.dur = online
    out.offline = math.max(0, span - online)
    out.window = hours
    return out
end

local function TodayKey()
    return date("%Y-%m-%d")
end

local function GetDay()
    local key = TodayKey()
    local b = WatchdogCharDB.days[key]
    if not b then
        b = NewBucket()
        WatchdogCharDB.days[key] = b
    end
    return b
end

-- Toda contagem vai para o dia de hoje e para a sessao atual.
local function Each(fn)
    fn(GetDay())
    fn(WatchdogCharDB.session)
end

function WD:CacheItem(itemID, name, quality, sell)
    if not itemID or not name or name == "" then return end
    local c = WatchdogDB.items[itemID]
    if not c then
        WatchdogDB.items[itemID] = { n = name, q = quality, p = sell }
    else
        if quality and c.q ~= quality then c.q = quality end
        if sell and c.p ~= sell then c.p = sell end
    end
end

-- Retorna nome, qualidade e preco de venda no NPC (em cobre; nil se ainda desconhecido).
function WD:GetItemDisplay(itemID)
    local c = WatchdogDB.items[itemID]
    local name, quality, sell = c and c.n, c and c.q, c and c.p
    if not name or sell == nil then
        local n, _, q, _, _, _, _, _, _, _, price = GetItemInfo(itemID)
        if n then
            self:CacheItem(itemID, n, q, price)
            name = name or n
            quality = quality or q
            sell = price
        end
    end
    return name or ("Item #" .. itemID), quality, sell
end

-- Valor de um item: vendor x preco do Watchdog AH. Regra: se o vendor for >= pct% do preco da AH,
-- vale o vendor (facil de vender); senao vale o da AH. Retorna valor unitario, usaAH.
local function AHOpt()
    local o = WatchdogDB.ahv
    if not o then o = { on = true, pct = 80 }; WatchdogDB.ahv = o end
    if o.on == nil then o.on = true end
    if not o.pct then o.pct = 80 end
    return o
end
function WD:AHOpt() return AHOpt() end
function WD:AHPrice(itemID)
    local d = WatchdogDB.ahPrices
    local e = d and itemID and d[itemID]
    return e and e.p or nil, e
end
-- Tipo de bind do item (1 = ao pegar, 2 = ao equipar, 3 = ao usar, 4 = quest) e classe (12 = quest).
local bindCache = {}
function WD:ItemBind(itemID)
    local c = bindCache[itemID]
    if c then return c[1], c[2] end
    local ok, _, _, _, _, _, _, _, _, _, _, _, classID, _, bindType = pcall(GetItemInfo, itemID)
    if ok and bindType ~= nil then
        bindCache[itemID] = { bindType, classID }
        return bindType, classID
    end
    return nil, nil
end
-- Pode ser posto na AH? (nao: soulbound, bind ao pegar, item de quest)
function WD:CanAuction(itemID, bound)
    if bound then return false end
    local bt, cls = self:ItemBind(itemID)
    if bt == 1 then return false end
    if bt == 4 or cls == 12 then
        -- item de quest que aparece no scan da AH e negociavel de verdade
        return (self:AHPrice(itemID)) ~= nil
    end
    return true
end
function WD:IsQuestItem(itemID)
    local bt, cls = self:ItemBind(itemID)
    return bt == 4 or cls == 12
end
function WD:UnitValue(itemID, sell, bound)
    if sell == nil then local _, _, s2 = self:GetItemDisplay(itemID); sell = s2 end
    sell = tonumber(sell) or 0
    local o = AHOpt()
    if o.on and self:CanAuction(itemID, bound) then
        local p = self:AHPrice(itemID)
        if p and p > 0 and sell < (o.pct / 100) * p then return p, true end
    end
    return sell, false
end
-- Muda a regra / chegou scan novo: as bolsas passam a ser reavaliadas sem gerar lucro falso.
function WD:BumpValuation()
    WatchdogDB.valSig = (WatchdogDB.valSig or 0) + 1
    pcall(WD.UpdateBagValue, WD)
    WD:Refresh()
    if WD.RefreshAHTab then WD:RefreshAHTab() end
end

-- Valor (cobre) dos itens dropados por um mob, sem o dinheiro.
function WD:MobItemsValue(mob)
    local total = 0
    for id, qty in pairs(mob.loot) do
        local _, _, sell = self:GetItemDisplay(id)
        local v = self:UnitValue(id, sell)
        if v and v > 0 then total = total + v * qty end
    end
    return total
end

-- Itens + dinheiro dropado pelo mob.
function WD:MobValue(mob)
    return self:MobItemsValue(mob) + (mob.money or 0)
end

-- Valor total de um bucket: itens de todos os mobs + todo o dinheiro looteado.
function WD:BucketValue(b)
    local total = b.money or 0
    for _, m in pairs(b.mobs) do total = total + self:MobItemsValue(m) end
    return total
end

-- Texto simples de moeda, para relatorios: "2g 12s 48c".
function WD:CoinText(copper)
    copper = math.floor(copper or 0)
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    if g > 0 then return string.format("%dg %02ds %02dc", g, s, c) end
    if s > 0 then return string.format("%ds %02dc", s, c) end
    return c .. "c"
end

-- Retorna a chave (YYYY-MM-DD) do inicio do periodo, ou nil para "tempo todo".
function WD:GetPeriodStartKey(period)
    if period == "day" then
        return TodayKey()
    elseif period == "week" then
        local t = date("*t")
        local sinceMonday = (t.wday + 5) % 7 -- wday: 1=domingo, 2=segunda
        local noon = time({ year = t.year, month = t.month, day = t.day, hour = 12 })
        return date("%Y-%m-%d", noon - sinceMonday * 86400)
    elseif period == "month" then
        return date("%Y-%m-01")
    end
    return nil
end

local function MergeInto(out, b)
    out.pvp.kills = out.pvp.kills + (b.pvp.kills or 0)
    out.pvp.deaths = out.pvp.deaths + (b.pvp.deaths or 0)
    out.pvp.honor = out.pvp.honor + (b.pvp.honor or 0)
    out.xp = out.xp + (b.xp or 0)
    out.money = (out.money or 0) + (b.money or 0)
    for name, m in pairs(b.mobs) do
        local o = GetMob(out, name)
        o.kills = o.kills + (m.kills or 0)
        if (m.last or 0) > (o.last or 0) then o.last = m.last end
        o.money = (o.money or 0) + (m.money or 0)
        o.hit = (o.hit or 0) + (m.hit or 0)
        for id, q in pairs(m.loot) do
            o.loot[id] = (o.loot[id] or 0) + q
        end
        if m.lootN then
            for id, n in pairs(m.lootN) do
                o.lootN[id] = (o.lootN[id] or 0) + n
            end
        end
    end
end

-- period: "all" | "month" | "week" | "day" | "session"
function WD:Aggregate(period)
    local out = NewBucket()
    if period == "session" then
        MergeInto(out, WatchdogCharDB.session)
        return out
    end
    local startKey = self:GetPeriodStartKey(period)
    for key, b in pairs(WatchdogCharDB.days) do
        if not startKey or key >= startKey then
            MergeInto(out, b)
        end
    end
    return out
end

function WD:StartNewSession()
    WatchdogCharDB.sessionLast = time()
    NewSession()
    self:Refresh()
end

---------------------------------------------------------------------------
-- Inventario
---------------------------------------------------------------------------
local GetNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots

local function ReadSlot(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then
            return info.iconFileID, info.stackCount or 1, info.quality, info.hyperlink, info.itemID, (WD.SlotBound and WD:SlotBound(bag, slot, info)) or info.isBound
        end
        return nil
    end
    if GetContainerItemInfo then
        local icon, count, _, quality, _, _, link, _, _, itemID = GetContainerItemInfo(bag, slot)
        if icon then return icon, count or 1, quality, link, itemID end
    end
    return nil
end

-- Le as bolsas e devolve { slots = {...}, total, used, value }.
-- Cada slot: { bag, slot, icon?, count?, quality?, link?, itemID?, name?, sell?, value? }
local function ScanIDs(self, ids)
    local out = { slots = {}, total = 0, used = 0, value = 0, valueA = 0, pending = 0 }
    for _, bag in ipairs(ids) do
        local n = GetNumSlots and GetNumSlots(bag) or 0
        for slot = 1, n do
            local icon, count, quality, link, itemID, bound = ReadSlot(bag, slot)
            local entry = { bag = bag, slot = slot }
            out.total = out.total + 1
            if icon then
                itemID = itemID or (link and tonumber(link:match("item:(%d+)")))
                entry.icon, entry.count, entry.link, entry.itemID = icon, count or 1, link, itemID
                entry.bound = bound and true or false
                entry.quality = (quality and quality >= 0) and quality or nil
                if itemID then
                    local name, q, sell = self:GetItemDisplay(itemID)
                    entry.name = name
                    entry.quality = entry.quality or q
                    entry.sell = sell
                    local uv, isA = self:UnitValue(itemID, sell, bound)
                    entry.value = uv * entry.count
                    entry.src = isA and "a" or "v"
                    out.value = out.value + entry.value
                    if isA then out.valueA = out.valueA + entry.value end
                    if sell == nil then out.pending = out.pending + 1 end
                end
                out.used = out.used + 1
            end
            out.slots[#out.slots + 1] = entry
        end
    end
    return out
end

function WD:ScanBags()
    local ids = {}
    for bag = 0, (NUM_BAG_SLOTS or 4) do ids[#ids + 1] = bag end
    return ScanIDs(self, ids)
end

-- Banco (so le com o banco aberto).
function WD:ScanBank()
    local ids = { -1 }
    for bag = (NUM_BAG_SLOTS or 4) + 1, (NUM_BAG_SLOTS or 4) + (NUM_BANKBAGSLOTS or 7) do ids[#ids + 1] = bag end
    return ScanIDs(self, ids)
end

-- "Em transito": itens que sairam da bag mas ainda sao seus (listados na AH, enviados por correio).
-- Contam pelo valor de vendor ate o dinheiro chegar pelo correio (ou ate voltarem para a bag).
local TRANSIT_TTL = 72 * 3600
local function TransitList()
    WatchdogCharDB.transit = WatchdogCharDB.transit or {}
    return WatchdogCharDB.transit
end
local function TransitTotal()
    local now, v, a, l = time(), 0, 0, TransitList()
    for i = #l, 1, -1 do
        if now - l[i].t > TRANSIT_TTL then table.remove(l, i) else v = v + l[i].v; a = a + (l[i].a or 0) end
    end
    return v, a
end
local function TransitAdd(v, a)
    if v > 0 then local l = TransitList(); l[#l + 1] = { t = time(), v = v, a = math.max(0, math.min(a or 0, v)) } end
end
local function TransitTake(x)
    local l = TransitList()
    while x > 0 and l[1] do
        local e = l[1]
        if e.v <= x then x = x - e.v; table.remove(l, 1)
        else
            local f = x / e.v
            e.a = (e.a or 0) * (1 - f); e.v = e.v - x; x = 0
        end
    end
end

-- Itens listados na AH: guardamos o preco pedido e o valor de vendor de cada listagem.
-- Cada uma pertence a sessao em que foi criada (sid = inicio da sessao).
local function AHList()
    WatchdogCharDB.ahList = WatchdogCharDB.ahList or {}
    return WatchdogCharDB.ahList
end
local function AHPurge()
    local now, l = time(), AHList()
    for i = #l, 1, -1 do if (l[i].exp or 0) < now then table.remove(l, i) end end
end
function WD:AHTotals(sid)
    AHPurge()
    local price, vendor, va = 0, 0, 0
    for _, e in ipairs(AHList()) do
        if e.sid == sid then price = price + e.price; vendor = vendor + e.vendor; va = va + (e.va or 0) end
    end
    return price, vendor, va
end
local function AHAdd(count, price, vendor, runTime, name, va, id)
    if not price or price <= 0 then return end
    local hours = ({ [1] = 12, [2] = 24, [3] = 48 })[runTime] or 48
    if WD.HistAdd then pcall(WD.HistAdd, WD, { kind = "post", id = id, name = name, count = count or 1, price = price }) end
    local l = AHList()
    l[#l + 1] = { t = time(), sid = WatchdogCharDB.sessionStart, count = count or 1, price = price,
        vendor = vendor or 0, va = va or 0, name = name, exp = time() + hours * 3600 + 3600 }
    WD:QueueBagValue()
end
-- Dinheiro de venda recebido (descontada a taxa de 5%): remove das listagens, da mais antiga pra mais nova.
-- Retorna o valor de vendor que saiu e quanto do dinheiro foi explicado.
local function AHTakeMoney(d)
    AHPurge()
    local l, vend, used = AHList(), 0, 0
    while d > 0 and l[1] do
        local e = l[1]
        local net = e.price * 0.95
        if net <= d then
            d = d - net; used = used + net; vend = vend + e.vendor; table.remove(l, 1)
        else
            local f = d / net
            vend = vend + e.vendor * f; used = used + d
            e.price = e.price * (1 - f); e.vendor = e.vendor * (1 - f); e.va = (e.va or 0) * (1 - f); d = 0
        end
    end
    return vend, used
end
-- Itens que voltaram pra bolsa (cancelou/expirou): tira das listagens pelo valor de vendor.
local function AHTakeVendor(v)
    local l = AHList()
    while v > 0 and l[1] do
        local e = l[1]
        if e.vendor <= v then v = v - e.vendor; table.remove(l, 1)
        else
            local f = v / e.vendor
            e.price = e.price * (1 - f); e.vendor = e.vendor - v; v = 0
        end
    end
end

local bankOpen, ahOpen, mailOpen = false, false, false
local lastBags, lastBagsA
-- Valor de vendor de tudo que e seu: bolsas + banco (ultimo visto) + itens em transito.
-- Diagnostico do ouro da sessao: guarda em WatchdogDB.goldDiag o que mudou na bolsa e por que um calculo foi ignorado.
local lastSlotsV = {}
local function GDiag(msg)
    local d = WatchdogDB
    if not d then return end
    d.goldDiag = d.goldDiag or {}
    local l = d.goldDiag
    l[#l + 1] = date("%H:%M:%S ") .. msg
    while #l > 120 do table.remove(l, 1) end
end
local function GDiagSlots(scan, total)
    local cur, lines = {}, {}
    for _, e in ipairs(scan.slots or {}) do
        if e.itemID then
            local k = (e.bag or "?") .. ":" .. (e.slot or "?")
            cur[k] = { id = e.itemID, v = e.value or 0, src = e.src or "?", b = e.bound and "B" or "-", n = e.count or 1 }
        end
    end
    for k, n in pairs(cur) do
        local o = lastSlotsV[k]
        if not o then lines[#lines + 1] = string.format("+%s id=%d x%d v=%d %s%s", k, n.id, n.n, n.v, n.src, n.b)
        elseif o.id ~= n.id or math.abs(o.v - n.v) > 0.5 or o.src ~= n.src or o.b ~= n.b then
            lines[#lines + 1] = string.format("~%s id=%d x%d v=%d->%d %s->%s %s->%s", k, n.id, n.n, o.v, n.v, o.src, n.src, o.b, n.b)
        end
    end
    for k, o in pairs(lastSlotsV) do
        if not cur[k] then lines[#lines + 1] = string.format("-%s id=%d v=%d", k, o.id, o.v) end
    end
    lastSlotsV = cur
    if #lines > 0 then
        GDiag(string.format("total=%d", total))
        for i = 1, math.min(#lines, 12) do GDiag("  " .. lines[i]) end
    end
end

function WD:UpdateBagValue()
    local s = WatchdogCharDB and WatchdogCharDB.session
    if not s then return end
    if bankOpen then
        local bank = self:ScanBank()
        if bank.pending == 0 and bank.total > 0 then
            WatchdogCharDB.bankValue = bank.value
            WatchdogCharDB.bankValueA = bank.valueA
        end
    end
    WD._boundUnsure = false
    local scan = self:ScanBags()
    if scan.pending > 0 then GDiag("ignorado: " .. scan.pending .. " item(ns) sem preco de vendor no cache"); return end
    if WD._boundUnsure and (WD._unsureTries or 0) < 4 and C_Timer and C_Timer.After then
        -- o jogo ainda nao disse se algum item esta preso: tenta de novo daqui a pouco (ate 4 vezes)
        WD._unsureTries = (WD._unsureTries or 0) + 1
        GDiag("ignorado: soulbound incerto (tentativa " .. WD._unsureTries .. ")")
        C_Timer.After(2, function() pcall(WD.UpdateBagValue, WD) end)
        return
    end
    WD._unsureTries = 0
    -- Variacao das bolsas com AH/correio abertos = item em transito (nao e perda).
    if lastBags then
        local d = scan.value - lastBags
        local dA = scan.valueA - (lastBagsA or 0)
        if d < 0 and (ahOpen or mailOpen) then TransitAdd(-d, -dA)
        elseif d > 0 and mailOpen then TransitTake(d) end
    end
    lastBags, lastBagsA = scan.value, scan.valueA
    local tv, ta = TransitTotal()
    local total = scan.value + (WatchdogCharDB.bankValue or 0) + tv
    local totalA = scan.valueA + (WatchdogCharDB.bankValueA or 0) + ta
    -- Valorizacao mudou (scan novo / regra / versao): desloca o ponto de partida pra nao virar lucro falso.
    local sig = WatchdogDB.valSig or 0
    if s.valSig ~= sig then
        if s.bagStart ~= nil and s.bagLast ~= nil then
            s.bagStart = s.bagStart + (total - s.bagLast)
            s.bagStartA = (s.bagStartA or (s.bagLastA or 0)) + (totalA - (s.bagLastA or 0))
        end
        s.valSig = sig
    end
    s.bagLast, s.bagLastA = total, totalA
    pcall(GDiagSlots, scan, total)
    if s.bagStart == nil then s.bagStart = total end
    if s.bagStartA == nil then s.bagStartA = totalA end
end

-- Dinheiro que chega pelo correio (venda na AH etc.) quita o valor em transito.
function WD:OnMailMoney(d)
    if not (mailOpen and d > 0) then return end
    local vend, used = AHTakeMoney(d)
    if used > 0 then TransitTake(vend) end
    if d - used > 0 then TransitTake(d - used) end
end

-- Captura do que voce lista na AH (preco pedido + valor de vendor). Cliente com API antiga
-- (PostAuction) ou nova (C_AuctionHouse); o que existir e usado.
-- Diagnostico: o que este cliente tem de API/eventos de leilao (grava em WatchdogDB.ahDiag)
local function Diag(msg)
    local d = WatchdogDB
    if not d then return end
    d.ahDiag = d.ahDiag or { api = {}, log = {} }
    local l = d.ahDiag.log
    l[#l + 1] = date("%H:%M:%S ") .. msg
    if #l > 80 then table.remove(l, 1) end
end
local function Safe(v) local ok, s = pcall(tostring, v); return ok and s or "?" end


---------------------------------------------------------------------------
-- Historico da AH (conta inteira): compras, vendas, itens postados, expirados e cancelados.
-- Compras e postagens vem dos hooks; vendas, expirados e cancelados vem do correio.
---------------------------------------------------------------------------
local HIST_MAX = 500
function WD:HistList()
    if not WatchdogDB then return {} end
    WatchdogDB.ahHistory = WatchdogDB.ahHistory or {}
    return WatchdogDB.ahHistory
end
function WD:HistAdd(e)
    if not WatchdogDB or type(e) ~= "table" then return end
    local l = WD:HistList()
    e.t = e.t or time()
    e.char = e.char or UnitName("player")
    if not e.name and e.id then
        local ok, n = pcall(GetItemInfo, e.id)
        if ok and n then e.name = n end
    end
    local i = #l + 1
    l[i] = e
    while i > 1 and (l[i - 1].t or 0) > e.t do l[i], l[i - 1] = l[i - 1], l[i]; i = i - 1 end
    while #l > HIST_MAX do table.remove(l, 1) end
    if WD.RefreshAHTab then pcall(WD.RefreshAHTab, WD) end
end
-- Ja existe no historico? (mesma chave e mesmo instante, com tolerancia)
local function HistHas(k, mexp)
    for _, e in ipairs(WD:HistList()) do
        if e.k == k and math.abs((e.mexp or 0) - mexp) < 600 then return true end
    end
    return false
end
-- Compra feita no proprio jogo (hook) pode ter o mesmo item/preco da fatura do correio: evita duplicar.
local function HistHasBuy(name, price, t)
    for _, e in ipairs(WD:HistList()) do
        if e.kind == "buy" and math.abs((e.t or 0) - t) < 900 and math.abs((e.price or 0) - price) <= math.max(1, price * 0.02)
            and (not e.name or not name or e.name == name) then
            if not e.name and name then e.name = name end
            return true
        end
    end
    return false
end

local function GlobalPattern(g)
    if type(g) ~= "string" then return nil end
    local p = g:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"):gsub("%%%%s", "(.+)"):gsub("%%s", "(.+)")
    return "^" .. p .. "$"
end

local mailTimer, invLogged
local function ScanMailHistory()
    mailTimer = nil
    if not (GetInboxNumItems and GetInboxHeaderInfo) then return end
    local okN, n = pcall(GetInboxNumItems)
    if not okN or type(n) ~= "number" then return end
    local now = time()
    local patExp = GlobalPattern(AUCTION_EXPIRED_MAIL_SUBJECT)
    local patCan = GlobalPattern(AUCTION_REMOVED_MAIL_SUBJECT)
    for i = 1, n do
        local ok, _, _, sender, subject, money, _, days, itemCount = pcall(GetInboxHeaderInfo, i)
        if ok and type(days) == "number" then
            local mexp = now + days * 86400
            local t = math.min(now, mexp - 30 * 86400)
            if GetInboxInvoiceInfo then
                local r = { pcall(GetInboxInvoiceInfo, i) }
                local invType, itemName, who, bid, buyout, deposit, cons = r[2], r[3], r[4], r[5], r[6], r[7], r[8]
                if r[1] and r[2] and (invLogged or 0) < 8 then
                    invLogged = (invLogged or 0) + 1
                    local parts = {}
                    for j = 2, 13 do parts[#parts + 1] = Safe(r[j]) end
                    Diag("fatura: " .. table.concat(parts, " | "))
                end
                if r[1] and (invType == "seller" or invType == "buyer") and type(itemName) == "string" then
                    local cnt = tonumber(r[11])
                    local kind = invType == "seller" and "sell" or "buy"
                    local price = tonumber(bid) or 0
                    local k = kind .. "|" .. itemName .. "|" .. price .. "|" .. (UnitName("player") or "")
                    if kind == "buy" then
                        -- compra: so entra se o hook nao registrou (por ex. comprada em outra sessao sem o addon)
                        if not HistHas(k, mexp) and not HistHasBuy(itemName, price, t) then
                            WD:HistAdd({ kind = "buy", name = itemName, count = cnt, price = price, who = who, t = t, k = k, mexp = mexp })
                        end
                    elseif not HistHas(k, mexp) then
                        WD:HistAdd({ kind = "sell", name = itemName, count = cnt, price = price, fee = tonumber(cons) or 0,
                            who = who, t = t, k = k, mexp = mexp })
                    end
                end
            end
            if type(subject) == "string" then
                local kind, nm
                if patExp then nm = subject:match(patExp); if nm then kind = "exp" end end
                if not kind and patCan then nm = subject:match(patCan); if nm then kind = "cancel" end end
                if kind then
                    local cnt = tonumber(itemCount) or 1
                    local k = kind .. "|" .. nm .. "|" .. cnt .. "|" .. (UnitName("player") or "")
                    if not HistHas(k, mexp) then
                        WD:HistAdd({ kind = kind, name = nm, count = cnt, price = 0, t = t, k = k, mexp = mexp })
                    end
                end
            end
        end
    end
end
function WD:QueueMailHistory()
    if mailTimer then return end
    mailTimer = true
    C_Timer.After(0.6, function() pcall(ScanMailHistory) end)
end

-- Compras: ConfirmCommoditiesPurchase (commodity), PlaceBid (item) e PlaceAuctionBid (API antiga).
-- O valor pago e o dinheiro que saiu da carteira logo apos a compra.
local function HistBuyLater(id, name, count, estimate, m0)
    C_Timer.After(1.2, function()
        local paid = (m0 or 0) - (GetMoney and GetMoney() or 0)
        if paid <= 0 then paid = estimate or 0 end
        if paid > 0 then WD:HistAdd({ kind = "buy", id = id, name = name, count = count, price = paid }) end
    end)
end
local pendingCommodity
local function OnConfirmCommodity(itemID, quantity)
    local est = 0
    local A = C_AuctionHouse
    if A and A.GetNumCommoditySearchResults and A.GetCommoditySearchResultInfo then
        local okn, nres = pcall(A.GetNumCommoditySearchResults, itemID)
        local need = tonumber(quantity) or 0
        if okn and type(nres) == "number" then
            for i = 1, nres do
                if need <= 0 then break end
                local ok, r = pcall(A.GetCommoditySearchResultInfo, itemID, i)
                if ok and type(r) == "table" then
                    local q = math.min(need, tonumber(r.quantity) or 0)
                    est = est + q * (tonumber(r.unitPrice) or 0); need = need - q
                end
            end
        end
    end
    pendingCommodity = { id = itemID, count = tonumber(quantity) or 1, est = est, m0 = GetMoney and GetMoney() or 0, t = GetTime() }
end
local function OnPlaceBid(auctionID, bidAmount)
    local id, name, count
    local A = C_AuctionHouse
    if A and A.GetAuctionInfoByID then
        local ok, info = pcall(A.GetAuctionInfoByID, auctionID)
        if ok and type(info) == "table" then
            id = info.itemKey and info.itemKey.itemID
            count = tonumber(info.quantity)
        end
    end
    HistBuyLater(id, name, count or 1, tonumber(bidAmount), GetMoney and GetMoney() or 0)
end
local function OnPlaceAuctionBid(listType, index, bid)
    local ok, name, _, count, _, _, _, _, _, _, _, _, _, _, _, _, _, itemId = pcall(GetAuctionItemInfo, listType, index)
    if not ok then name = nil end
    HistBuyLater(itemId, name, tonumber(count) or 1, tonumber(bid), GetMoney and GetMoney() or 0)
end
function WD:OnHistEvent(event)
    if event == "COMMODITY_PURCHASE_SUCCEEDED" then
        local pc = pendingCommodity
        pendingCommodity = nil
        if pc and GetTime() - pc.t < 120 then HistBuyLater(pc.id, nil, pc.count, pc.est, pc.m0) end
    elseif event == "COMMODITY_PURCHASE_FAILED" then
        pendingCommodity = nil
    elseif event == "MAIL_INBOX_UPDATE" or event == "MAIL_SHOW" then
        WD:QueueMailHistory()
    end
end

local sellCache
local function UnitVendor(idOrName)
    if not idOrName then return 0 end
    local ok, _, _, _, _, _, _, _, _, _, _, sell = pcall(GetItemInfo, idOrName)
    return (ok and tonumber(sell)) or 0
end
local function ListV(idOrName, n)
    n = n or 1
    if type(idOrName) == "number" then return (WD:UnitValue(idOrName)) * n end
    return UnitVendor(idOrName) * n
end
local function ListA(idOrName, n)
    n = n or 1
    if type(idOrName) ~= "number" then return 0 end
    local v, isA = WD:UnitValue(idOrName)
    return isA and v * n or 0
end
function WD:OnSellSlot()
    sellCache = nil
    if not GetAuctionSellItemInfo then return end
    local ok, name, _, count, _, _, _, _, stackCount, totalCount, itemID = pcall(GetAuctionSellItemInfo)
    if ok and name and name ~= "" then
        sellCache = { name = name, count = count or 1, totalCount = totalCount, itemID = itemID }
    end
end
local function OnPostAuction(minBid, buyout, runTime, stackSize, numStacks)
    Diag(string.format("PostAuction bid=%s buyout=%s run=%s stack=%s n=%s", Safe(minBid), Safe(buyout), Safe(runTime), Safe(stackSize), Safe(numStacks)))
    local s = sellCache
    if not s then WD:OnSellSlot(); s = sellCache end
    numStacks = tonumber(numStacks) or 1
    stackSize = tonumber(stackSize) or (s and s.count) or 1
    local per = (tonumber(buyout) and buyout > 0) and buyout or tonumber(minBid) or 0
    local count = stackSize * numStacks
    local unit = s and UnitVendor(s.itemID or s.name) or 0
    AHAdd(count, per * numStacks, ListV(s and (s.itemID or s.name), count), runTime, s and s.name, ListA(s and (s.itemID or s.name), count), s and s.itemID)
end
local function OnPostItemNew(itemLocation, duration, quantity, bid, buyout)
    Diag(string.format("PostItem dur=%s qty=%s bid=%s buyout=%s", Safe(duration), Safe(quantity), Safe(bid), Safe(buyout)))
    local id
    if C_Item and C_Item.GetItemID and itemLocation then
        local ok, v = pcall(C_Item.GetItemID, itemLocation)
        if ok then id = v end
    end
    quantity = tonumber(quantity) or 1
    local price = (tonumber(buyout) and buyout > 0) and buyout or tonumber(bid) or 0
    AHAdd(quantity, price, ListV(id, quantity), 3, nil, ListA(id, quantity), id)
end
local function OnPostCommodity(itemLocation, duration, quantity, unitPrice)
    Diag(string.format("PostCommodity dur=%s qty=%s unit=%s", Safe(duration), Safe(quantity), Safe(unitPrice)))
    local id
    if C_Item and C_Item.GetItemID and itemLocation then
        local ok, v = pcall(C_Item.GetItemID, itemLocation)
        if ok then id = v end
    end
    quantity = tonumber(quantity) or 1
    AHAdd(quantity, (tonumber(unitPrice) or 0) * quantity, ListV(id, quantity), 3, nil, ListA(id, quantity), id)
end
-- Sincroniza com a lista REAL de leilões do jogador (fonte confiavel): { {id=, count=, price=}, ... }
function WD:SyncOwned(owned)
    local l = AHList()
    local old, new = {}, {}
    for _, e in ipairs(l) do old[#old + 1] = e end
    for _, o in ipairs(owned) do
        local found
        for i, e in ipairs(old) do
            if e.count == o.count and math.abs(e.price - o.price) < 1 and (not e.id or not o.id or e.id == o.id) then
                found = table.remove(old, i); break
            end
        end
        if found then
            found.id = found.id or o.id
            new[#new + 1] = found
        else
            new[#new + 1] = { t = time(), sid = WatchdogCharDB.sessionStart, count = o.count, price = o.price,
                vendor = ListV(o.id or o.name, o.count), va = ListA(o.id or o.name, o.count), id = o.id, name = o.name,
                exp = time() + 49 * 3600 }
        end
    end
    -- listagens registradas ha poucos segundos ainda podem nao aparecer na lista do jogo (que atrasa)
    for _, e in ipairs(old) do
        if time() - (e.t or 0) < 20 then new[#new + 1] = e end
    end
    WatchdogCharDB.ahList = new
    Diag("sync: " .. #owned .. " leilao(oes) ativo(s)")
end

local function ReadOwnedLegacy()
    if not (GetNumAuctionItems and GetAuctionItemInfo) then return end
    local ok, n = pcall(GetNumAuctionItems, "owner")
    if not ok or type(n) ~= "number" then return end
    local owned = {}
    for i = 1, n do
        local ok2, name, _, count, _, _, _, _, minBid, _, buyout, _, _, _, _, _, saleStatus, itemId = pcall(GetAuctionItemInfo, "owner", i)
        if ok2 and name and saleStatus ~= 1 then
            local price = (tonumber(buyout) and buyout > 0) and buyout or tonumber(minBid) or 0
            owned[#owned + 1] = { id = itemId, name = name, count = tonumber(count) or 1, price = price }
        end
    end
    WD:SyncOwned(owned)
end

local function ReadOwnedNew()
    local A = C_AuctionHouse
    if not (A and A.GetNumOwnedAuctions and A.GetOwnedAuctionInfo) then return end
    local ok, n = pcall(A.GetNumOwnedAuctions)
    if not ok or type(n) ~= "number" then return end
    local owned = {}
    for i = 1, n do
        local ok2, info = pcall(A.GetOwnedAuctionInfo, i)
        if ok2 and type(info) == "table" and (info.status == nil or info.status == 0) then
            local q = tonumber(info.quantity) or 1
            local p = (tonumber(info.buyoutAmount) and info.buyoutAmount > 0) and info.buyoutAmount or tonumber(info.bidAmount) or 0
            local id = info.itemKey and info.itemKey.itemID
            owned[#owned + 1] = { id = id, count = q, price = p * (info.itemKey and q or 1) }
            Diag(string.format("owned[%d] id=%s qty=%s bid=%s buyout=%s status=%s", i, Safe(id), Safe(info.quantity), Safe(info.bidAmount), Safe(info.buyoutAmount), Safe(info.status)))
        end
    end
    WD:SyncOwned(owned)
end

local diagEvents = {
    "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "AUCTION_OWNED_LIST_UPDATE", "NEW_AUCTION_UPDATE",
    "AUCTION_MULTISELL_START", "AUCTION_MULTISELL_UPDATE", "AUCTION_MULTISELL_FAILURE",
    "OWNED_AUCTIONS_UPDATED", "AUCTION_HOUSE_AUCTION_CREATED", "AUCTION_CANCELED", "AUCTION_HOUSE_POST_ERROR",
    "AUCTION_HOUSE_POST_WARNING", "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED", "MAIL_INBOX_UPDATE",
}
function WD:OnAuctionEvent(event, ...)
    if event == "MAIL_INBOX_UPDATE" then pcall(WD.OnHistEvent, WD, event); return end
    Diag(event .. " " .. Safe((...)))
    if event == "COMMODITY_PURCHASE_SUCCEEDED" or event == "COMMODITY_PURCHASE_FAILED" then pcall(WD.OnHistEvent, WD, event) end
    if event == "AUCTION_HOUSE_SHOW" then
        if GetOwnerAuctionItems then pcall(GetOwnerAuctionItems) end
        if C_AuctionHouse and C_AuctionHouse.QueryOwnedAuctions then pcall(C_AuctionHouse.QueryOwnedAuctions, {}) end
    elseif event == "AUCTION_OWNED_LIST_UPDATE" then
        pcall(ReadOwnedLegacy)
    elseif event == "OWNED_AUCTIONS_UPDATED" then
        pcall(ReadOwnedNew)
    elseif event == "AUCTION_HOUSE_AUCTION_CREATED" or event == "AUCTION_CANCELED" then
        -- pede a lista atualizada; quando chegar, OWNED_AUCTIONS_UPDATED faz a leitura
        if C_AuctionHouse and C_AuctionHouse.QueryOwnedAuctions then pcall(C_AuctionHouse.QueryOwnedAuctions, {}) end
        if GetOwnerAuctionItems then pcall(GetOwnerAuctionItems) end
    end
end

local ahHooked
function WD:SetupAHHooks()
    if ahHooked then return end
    ahHooked = true
    if PostAuction then pcall(hooksecurefunc, "PostAuction", function(...) pcall(OnPostAuction, ...) end) end
    if C_AuctionHouse then
        if C_AuctionHouse.PostItem then pcall(hooksecurefunc, C_AuctionHouse, "PostItem", function(...) pcall(OnPostItemNew, ...) end) end
        if C_AuctionHouse.PostCommodity then pcall(hooksecurefunc, C_AuctionHouse, "PostCommodity", function(...) pcall(OnPostCommodity, ...) end) end
        if C_AuctionHouse.ConfirmCommoditiesPurchase then pcall(hooksecurefunc, C_AuctionHouse, "ConfirmCommoditiesPurchase", function(...) pcall(OnConfirmCommodity, ...) end) end
        if C_AuctionHouse.PlaceBid then pcall(hooksecurefunc, C_AuctionHouse, "PlaceBid", function(...) pcall(OnPlaceBid, ...) end) end
    end
    if PlaceAuctionBid then pcall(hooksecurefunc, "PlaceAuctionBid", function(...) pcall(OnPlaceAuctionBid, ...) end) end
    -- APIs disponiveis neste cliente (para diagnostico)
    if WatchdogDB then
        WatchdogDB.ahDiag = WatchdogDB.ahDiag or { api = {}, log = {} }
        local a = WatchdogDB.ahDiag.api
        a.PostAuction = PostAuction and true or false
        a.GetAuctionSellItemInfo = GetAuctionSellItemInfo and true or false
        a.GetNumAuctionItems = GetNumAuctionItems and true or false
        a.GetOwnerAuctionItems = GetOwnerAuctionItems and true or false
        a.C_AuctionHouse = C_AuctionHouse and true or false
        a.PostItem = (C_AuctionHouse and C_AuctionHouse.PostItem) and true or false
        a.PostCommodity = (C_AuctionHouse and C_AuctionHouse.PostCommodity) and true or false
        a.GetOwnedAuctionInfo = (C_AuctionHouse and C_AuctionHouse.GetOwnedAuctionInfo) and true or false
        a.version = select(4, GetBuildInfo())
    end
    local df = CreateFrame("Frame")
    for _, e in ipairs(diagEvents) do pcall(df.RegisterEvent, df, e) end
    df:SetScript("OnEvent", function(_, event, ...) pcall(WD.OnAuctionEvent, WD, event, ...) end)
    if WD.ev then pcall(WD.ev.RegisterEvent, WD.ev, "NEW_AUCTION_UPDATE") end
end

local bagTimer
function WD:QueueBagValue()
    if bagTimer then return end
    bagTimer = true
    C_Timer.After(2, function() bagTimer = nil; pcall(WD.UpdateBagValue, WD) end)
end

---------------------------------------------------------------------------
-- Padroes a partir das strings globais (funciona em qualquer idioma)
---------------------------------------------------------------------------
-- "%s dies, you gain %d experience." -> "^(.+) dies, you gain (%d+) experience%."
local function GlobalPattern(g)
    if type(g) ~= "string" then return nil end
    g = g:gsub("%%%d%$", "%%")                       -- %1$s -> %s
    g = g:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1") -- escapa caracteres magicos
    g = g:gsub("%%s", "(.+)")
    g = g:gsub("%%d", "(%%d+)")
    return "^" .. g
end

local function CoinPattern(g)
    local p = GlobalPattern(g)
    return p and p:sub(2) or nil   -- sem a ancora "^"
end

local function BuildPatterns()
    PAT.xp = GlobalPattern(COMBATLOG_XPGAIN_FIRSTPERSON)
    PAT.slain = GlobalPattern(SELFKILLOTHER)
    PAT.honor = GlobalPattern(COMBATLOG_HONORGAIN)
    PAT.gold = CoinPattern(GOLD_AMOUNT) or "(%d+) Gold"
    PAT.silver = CoinPattern(SILVER_AMOUNT) or "(%d+) Silver"
    PAT.copper = CoinPattern(COPPER_AMOUNT) or "(%d+) Copper"
end

---------------------------------------------------------------------------
-- EXP
---------------------------------------------------------------------------
local function IsMaxLevel()
    local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel()
    return maxLevel and UnitLevel("player") >= maxLevel
end

local function SnapshotXP()
    lastXP, lastMaxXP, lastLevel = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
end

local lastQuestTurn, questExact = -100, false
local function OnQuestTurnedIn(_, xp, money)
    local s = WatchdogCharDB.session
    s.quests = (s.quests or 0) + 1
    lastQuestTurn = GetTime()
    WD._questUntil = GetTime() + 4                      -- itens recebidos logo apos entregar contam como recompensa
    if type(money) == "number" and money > 0 and WD.FarmAdd then WD:FarmAdd(money) end
    if type(xp) == "number" and xp > 0 then
        s.questXP = (s.questXP or 0) + xp
        questExact = true
    else
        questExact = false
    end
    WD:Refresh()
end

-- Atividade: classifica o tempo (grind / voo / afk / craft / morto / outros).
local lastActivity, lastTick = -100, nil
function WD:MarkActive() lastActivity = GetTime() end

local function IsCrafting()
    local a, b = _G.TradeSkillFrame, _G.CraftFrame
    return (a and a.IsShown and a:IsShown() == true) or (b and b.IsShown and b:IsShown() == true) or false
end

local function ActivityTick()
    local s = WatchdogCharDB and WatchdogCharDB.session
    if not s then return end
    s.t = s.t or NewTimes()
    local now = GetTime()
    local dt = lastTick and (now - lastTick) or 0
    lastTick = now
    if dt <= 0 then return end
    if dt > 10 then dt = 2 end -- travada/loading: nao conta o buraco
    local cat
    if UnitOnTaxi and UnitOnTaxi("player") then cat = "flight"
    elseif UnitIsAFK and UnitIsAFK("player") then cat = "afk"
    elseif UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then cat = "dead"
    elseif IsCrafting() then cat = "craft"
    elseif (UnitAffectingCombat and UnitAffectingCombat("player")) or now - lastActivity < 45 then cat = "grind"
    else cat = "other" end
    s.t[cat] = (s.t[cat] or 0) + dt
end

-- Ouro: acompanha a carteira. Tudo que entra (loot, vendor, AH via correio, quest...) soma em
-- "income"; tudo que sai (reparo, compras, taxas, voo...) soma em "spent".
local lastMoney
local function OnPlayerMoney()
    local now = GetMoney and GetMoney() or nil
    if not now then return end
    if lastMoney then
        local d = now - lastMoney
        local s = WatchdogCharDB.session
        if d > 0 then s.income = (s.income or 0) + d; WD:OnMailMoney(d)
        elseif d < 0 then s.spent = (s.spent or 0) - d end
    end
    lastMoney = now
end

local function OnXPUpdate()
    if not lastXP then SnapshotXP() return end
    local cur, level = UnitXP("player"), UnitLevel("player")
    local gained
    if level > lastLevel or cur < lastXP then
        -- Upou: o que faltava do nivel anterior + o que ja tem no novo.
        gained = (lastMaxXP - lastXP) + cur
        local ups = math.max(1, level - lastLevel)
        WatchdogCharDB.session.levels = (WatchdogCharDB.session.levels or 0) + ups
    else
        gained = cur - lastXP
    end
    if gained > 0 then
        Each(function(b) b.xp = (b.xp or 0) + gained end)
        -- Sem o valor exato da quest, atribui o ganho logo apos a entrega a ela.
        if not questExact and GetTime() - lastQuestTurn < 3 then
            local s = WatchdogCharDB.session
            s.questXP = (s.questXP or 0) + gained
        end
    end
    SnapshotXP()
    WD:Refresh()
end

-- Estatisticas de EXP da sessao atual.
function WD:GetXPStats()
    local s = WatchdogCharDB.session
    local cur, max = UnitXP("player"), UnitXPMax("player")
    local elapsed = math.max(1, time() - (WatchdogCharDB.sessionStart or time()))
    local sessionXP = s.xp or 0
    local perHour = sessionXP / elapsed * 3600
    local remaining = math.max(0, max - cur)
    local avgKill = (s.killXPCount or 0) > 0 and (s.killXP / s.killXPCount) or nil
    return {
        maxLevel = IsMaxLevel(),
        level = UnitLevel("player"),
        cur = cur,
        max = max,
        remaining = remaining,
        rested = GetXPExhaustion and GetXPExhaustion() or nil,
        sessionXP = sessionXP,
        elapsed = elapsed,
        perHour = perHour,
        timeToLevel = perHour > 0 and (remaining / perHour * 3600) or nil,
        avgKill = avgKill,
        killsToLevel = avgKill and math.ceil(remaining / avgKill) or nil,
        levels = s.levels or 0,
    }
end

---------------------------------------------------------------------------
-- Kills (PvE e PvP) por mensagens de chat
---------------------------------------------------------------------------
-- Cada kill gera mais de uma mensagem ("You have slain X!" e "X dies, you gain
-- N experience."). Casamos as duas pelo nome numa janela curta para contar 1x.
local function MatchPending(tbl, name)
    local list = tbl[name]
    if not list then return false end
    local now = GetTime()
    for i = #list, 1, -1 do
        if now - list[i] > EVENT_WINDOW then table.remove(list, i) end
    end
    if #list > 0 then
        table.remove(list, 1)
        return true
    end
    return false
end

local function AddPending(tbl, name)
    local list = tbl[name]
    if not list then
        list = {}
        tbl[name] = list
    end
    list[#list + 1] = GetTime()
end

local killSeq = 0
local function CountMobKill(name)
    WD:MarkActive()
    Each(function(b)
        local m = GetMob(b, name)
        m.kills = m.kills + 1
        killSeq = killSeq + 1
        m.last = time() + (killSeq % 1000) / 1000   -- ordem exata dos ultimos abates
    end)
    recentKills[#recentKills + 1] = { name = name, t = GetTime() }
    if #recentKills > 60 then table.remove(recentKills, 1) end
    WD.stats.mobKills = WD.stats.mobKills + 1
    if WatchdogDB.rareNames[name] and WatchdogDB.alerts.rare then
        WD:Alert("rarekill", L.alert_rarekill, name, nil)
    end
    WD:Refresh()
end

local function CountPvPKill()
    Each(function(b) b.pvp.kills = b.pvp.kills + 1 end)
    WD.stats.pvpKills = WD.stats.pvpKills + 1
    WD:Refresh()
end

-- "Wolf dies, you gain 54 experience."
local function OnXPMessage(msg)
    WD.stats.xpMsgs = WD.stats.xpMsgs + 1
    local name, xp = msg:match(PAT.xp or "^$")
    xp = tonumber(xp)
    if not name or not xp then
        Dbg("XP sem match:", msg)
        return
    end
    Dbg("XP kill:", name, xp)
    if not MatchPending(pend.slain, name) then
        AddPending(pend.xp, name)
        CountMobKill(name)
    end
    AddKillXP(xp)
    WD:Refresh()
end

local function SlainIsPlayer(name)
    local n = Clean(UnitName("target"))
    return UnitExists("target") and n == name and UnitIsPlayer("target")
end

-- "You have slain Wolf!"
local function OnSlainMessage(msg)
    WD.stats.slainMsgs = WD.stats.slainMsgs + 1
    local name = msg:match(PAT.slain or "^$")
    if not name then
        Dbg("Slain sem match:", msg)
        return
    end
    if SlainIsPlayer(name) then
        -- Kill de PvP: quem conta e a mensagem de honra.
        Dbg("Slain PLAYER (conta pela honra):", name)
        return
    end
    Dbg("Slain mob:", name)
    if not MatchPending(pend.xp, name) then
        AddPending(pend.slain, name)
        CountMobKill(name)
    end
end

-- Qualquer ganho de honra = 1 kill de PvP.
-- "Fulano dies, honorable kill Rank: X (Estimated Honor Points: 12)"
local function OnHonorGain(msg)
    if type(msg) ~= "string" then return end
    WD.stats.honorMsgs = WD.stats.honorMsgs + 1
    local _, _, pts = msg:match(PAT.honor or "^$")
    local value = tonumber(pts)
    if not value then
        -- Outras frases de honra: pega o ultimo numero da mensagem.
        local last
        for n in msg:gmatch("%d+") do last = n end
        value = tonumber(last)
    end
    Dbg("Honra +" .. tostring(value) .. " = 1 kill:", msg)
    CountPvPKill()
    if value and value > 0 then
        Each(function(b) b.pvp.honor = b.pvp.honor + value end)
    end
    WD:Refresh()
end

-- Dano recebido de jogador inimigo (para contar morte PvP).
local function MarkPvPHit(name)
    lastPvPHit = GetTime()
    if type(name) == "string" and name ~= "" then lastPvPAttacker = name end
end

local function OnHostilePlayerHit()
    MarkPvPHit(nil)
end

-- Deteccao robusta via combat log: qualquer dano de jogador inimigo em voce.
local COMBATLOG_PLAYER = COMBATLOG_OBJECT_TYPE_PLAYER or 0x00000400
local COMBATLOG_HOSTILE = COMBATLOG_OBJECT_REACTION_HOSTILE or 0x00000040
local function IsCreature(guid)
    local kind = strsplit("-", guid)
    return kind == "Creature" or kind == "Vehicle"
end

-- Este cliente proibe addons de usar o combat log (COMBAT_LOG_EVENT_UNFILTERED
-- gera ADDON_ACTION_FORBIDDEN). Detecta agressor PvP por unidades visiveis:
-- jogador inimigo em combate que tem VOCE como alvo (nameplates, alvo, mouseover).
local function ScanPvPThreat()
    local function check(u)
        if not u or not UnitExists(u) or not UnitIsPlayer(u) then return end
        if UnitIsUnit(u, "player") then return end
        if not UnitCanAttack("player", u) then return end
        if UnitIsDeadOrGhost(u) then return end
        local tgt = u .. "target"
        if UnitExists(tgt) and UnitIsUnit(tgt, "player") and UnitAffectingCombat(u) then
            MarkPvPHit(Clean(UnitName(u)))
        elseif u == "target" and UnitAffectingCombat("player") and UnitAffectingCombat(u) then
            MarkPvPHit(Clean(UnitName(u)))
        end
    end
    check("target")
    check("mouseover")
    if C_NamePlate and C_NamePlate.GetNamePlates then
        for _, np in ipairs(C_NamePlate.GetNamePlates()) do
            check(np.namePlateUnitToken or (np.UnitFrame and np.UnitFrame.unit))
        end
    end
end
WD.ScanPvPThreat = ScanPvPThreat

local function OnPlayerDead()
    if lastPvPHit > 0 and (GetTime() - lastPvPHit) <= PVP_DEATH_WINDOW then
        Each(function(b) b.pvp.deaths = b.pvp.deaths + 1 end)
        WD.stats.pvpDeaths = (WD.stats.pvpDeaths or 0) + 1
        Dbg("Morte PvP contada (atacante:", lastPvPAttacker or "?", ")")
        WD:Refresh()
    end
    lastPvPHit = 0
    lastPvPAttacker = nil
end

---------------------------------------------------------------------------
-- Loot
---------------------------------------------------------------------------
-- Aprende o nome de corpos de mobs que vemos (alvo / mouseover).
local function RememberCorpse(unit)
    if not UnitExists(unit) or not UnitIsDead(unit) or UnitIsPlayer(unit) then return end
    local guid, name = Clean(UnitGUID(unit)), Clean(UnitName(unit))
    if type(guid) == "string" and type(name) == "string" then corpseName[guid] = { name = name, t = GetTime() } end
end

local function HasRecentKill(name)
    local now = GetTime()
    for i = #recentKills, 1, -1 do
        local k = recentKills[i]
        if k.name == name and now - k.t <= CORPSE_TTL then return true end
    end
    return false
end

-- Marca uma kill recente como "ja lootada" e devolve o nome.
local function ClaimKill(name)
    local now = GetTime()
    for i = #recentKills, 1, -1 do
        local k = recentKills[i]
        if not k.claimed and now - k.t <= CORPSE_TTL and (not name or k.name == name) then
            k.claimed = true
            return k.name
        end
    end
end

local function ResolveLootName(guid)
    local cached = guidMob[guid]
    if cached then return cached end
    local name
    local c = corpseName[guid]
    if c then
        ClaimKill(c.name)
        if HasRecentKill(c.name) then name = c.name end
    else
        -- Sem alvo/mouseover (ex.: autoloot): usa a kill mais recente ainda nao lootada.
        name = ClaimKill(nil)
    end
    if name then guidMob[guid] = name end
    return name
end

local function RecordLoot(guid, itemID, qty)
    if not guid or not IsCreature(guid) then return false end
    local key = guid .. ":" .. itemID
    if lootSeen[key] then return false end
    local name = ResolveLootName(guid)
    if not name then return false end
    lootSeen[key] = GetTime()
    local firstItem = not guidHit[guid]
    guidHit[guid] = true
    Each(function(b)
        local m = GetMob(b, name)
        if firstItem then m.hit = (m.hit or 0) + 1 end
        m.loot[itemID] = (m.loot[itemID] or 0) + qty
        m.lootN = m.lootN or {}
        m.lootN[itemID] = (m.lootN[itemID] or 0) + 1
    end)
    WD.stats.drops = WD.stats.drops + 1
    Dbg("Drop:", name, itemID, qty)
    return true
end

-- Aviso de drop raro (qualidade >= minQuality), uma vez por corpo/item.
local function MaybeAlertDrop(guid, itemID, qty, quality, link)
    local a = WatchdogDB.alerts
    if not a.drop or not quality or quality < (a.minQuality or 3) then return end
    local key = tostring(guid or "?") .. ":" .. itemID
    if alertSeen[key] then return end
    alertSeen[key] = GetTime()
    local icon = GetItemIcon and GetItemIcon(itemID) or nil
    local text = (link or ("item " .. itemID)) .. ((qty or 1) > 1 and (" x" .. qty) or "")
    WD:Alert("drop", L.alert_drop, text, icon)
end

local function OnLoot()
    WD:MarkActive()
    RememberCorpse("target")
    RememberCorpse("mouseover")

    -- Descobre de qual mob e esse loot (usado tambem para o dinheiro).
    if GetLootSourceInfo and GetNumLootItems() > 0 then
        local guid = GetLootSourceInfo(1)
        if guid and IsCreature(guid) then
            local nm = ResolveLootName(guid)
            if nm then lastLootName, lastLootTime = nm, GetTime() end
        end
    end

    local changed = false
    for slot = 1, GetNumLootItems() do
        if GetLootSlotType(slot) == LOOT_ITEM then
            local link = GetLootSlotLink(slot)
            local itemID = link and tonumber(link:match("item:(%d+)"))
            if itemID then
                local _, itemName, quantity, _, quality = GetLootSlotInfo(slot)
                local _, _, _, _, _, _, _, _, _, _, sell = GetItemInfo(link)
                WD:CacheItem(itemID, itemName, quality, sell)
                if GetLootSourceInfo then
                    local src = { GetLootSourceInfo(slot) }
                    for i = 1, #src, 2 do
                        if RecordLoot(src[i], itemID, src[i + 1] or 1) then changed = true end
                        MaybeAlertDrop(src[i], itemID, src[i + 1] or 1, quality, link)
                    end
                else
                    local guid = UnitGUID("target") or UnitGUID("mouseover")
                    if RecordLoot(guid, itemID, quantity or 1) then changed = true end
                    MaybeAlertDrop(guid, itemID, quantity or 1, quality, link)
                end
            end
        end
    end
    if changed then WD:Refresh() end
end

-- "You loot 5 Silver, 3 Copper."
local function OnMoneyMessage(msg)
    if type(msg) ~= "string" then return end
    WD.stats.moneyMsgs = WD.stats.moneyMsgs + 1
    local function amount(pat)
        return pat and tonumber(msg:match(pat)) or 0
    end
    local copper = amount(PAT.gold) * 10000 + amount(PAT.silver) * 100 + amount(PAT.copper)
    if copper <= 0 then
        Dbg("Dinheiro sem match:", msg)
        return
    end
    local name = (lastLootName and GetTime() - lastLootTime <= MONEY_WINDOW) and lastLootName or nil
    Dbg("Dinheiro:", copper, name or "(sem mob)")
    if WD.FeedGold then pcall(WD.FeedGold, WD, copper) end
    if WD.FarmAdd then WD:FarmAdd(copper) end
    Each(function(b)
        b.money = (b.money or 0) + copper
        if name then
            local m = GetMob(b, name)
            m.money = (m.money or 0) + copper
        end
    end)
    WD:Refresh()
end

---------------------------------------------------------------------------
-- Feed de loot da sessao (janela /wd lootgoldbar): itens e ouro recebidos
---------------------------------------------------------------------------
-- Ouro farmado da sessao: soma so o que ENTRA do farm (ouro dropado, recompensa de quest, itens de
-- loot/skinning/pickpocket/quest pelo valor no momento do drop). Nunca subtrai: o que voce faz depois com
-- o item (vender, usar, postar na AH) nao altera o valor farmado.
function WD:FarmAdd(coin, items, itemsA)
    local s = WatchdogCharDB and WatchdogCharDB.session
    if not s then return end
    s.farmCoin = (s.farmCoin or 0) + (tonumber(coin) or 0)
    s.farmItems = (s.farmItems or 0) + (tonumber(items) or 0)
    s.farmItemsA = (s.farmItemsA or 0) + (tonumber(itemsA) or 0)
end

local function FarmItem(id, qty, tries)
    local unit, viaAH = WD:UnitValue(id)
    unit = tonumber(unit) or 0
    -- item ainda sem dados no cache: tenta de novo em instantes (ate 3 vezes)
    if unit == 0 and not GetItemInfo(id) and (tries or 0) < 3 and C_Timer and C_Timer.After then
        C_Timer.After(2, function() pcall(FarmItem, id, qty, (tries or 0) + 1) end)
        return
    end
    local v = unit * qty
    WD:FarmAdd(0, v, viaAH and v or 0)
end

local FEED_MAX = 40
local function Feed()
    local c = WatchdogCharDB
    if not c then return nil end
    local f = c.lootFeed
    if not f or f.sid ~= c.sessionStart then
        f = { sid = c.sessionStart, items = {}, gold = {}, goldTotal = 0 }
        c.lootFeed = f
    end
    return f
end
function WD:LootFeed() return Feed() end

local function FeedPoke() if WD.RefreshLootBar then pcall(WD.RefreshLootBar, WD) end end

function WD:FeedGold(copper)
    local f = Feed()
    copper = tonumber(copper)
    if not f or not copper or copper <= 0 then return end
    table.insert(f.gold, 1, { t = time(), c = copper })
    while #f.gold > FEED_MAX do table.remove(f.gold) end
    f.goldTotal = (f.goldTotal or 0) + copper
    FeedPoke()
end

function WD:FeedItem(itemID, qty)
    local f = Feed()
    itemID = tonumber(itemID)
    if not f or not itemID then return end
    qty = math.max(1, tonumber(qty) or 1)
    local now = time()
    local top = f.items[1]
    if top and top.id == itemID and now - (top.t or 0) <= 4 then
        top.n = (top.n or 1) + qty; top.t = now
    else
        table.insert(f.items, 1, { t = now, id = itemID, n = qty })
        while #f.items > FEED_MAX do table.remove(f.items) end
    end
    FeedPoke()
end

function WD:FeedClear()
    local c = WatchdogCharDB
    if c then c.lootFeed = nil end
    FeedPoke()
end

local lootPats
local function LootPatterns()
    if lootPats then return lootPats end
    lootPats = {}
    for _, g in ipairs({ "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF_MULTIPLE" }) do
        local p = _G[g] and GlobalPattern(_G[g])
        if p then lootPats[#lootPats + 1] = { p, true, g == "LOOT_ITEM_SELF_MULTIPLE" } end
    end
    for _, g in ipairs({ "LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF" }) do
        local p = _G[g] and GlobalPattern(_G[g])
        if p then lootPats[#lootPats + 1] = { p, false, g == "LOOT_ITEM_SELF" } end
    end
    return lootPats
end

-- "You receive loot: [Item]x5." (so as suas; mensagens de outros jogadores nao casam)
local function OnLootMessage(msg)
    msg = Clean(msg)
    if type(msg) ~= "string" then return end
    for _, e in ipairs(LootPatterns()) do
        local a, b = msg:match(e[1])
        if a then
            local id = tonumber(a:match("item:(%d+)"))
            if id then
                local qty = e[2] and tonumber(b) or 1
                WD:FeedItem(id, qty)
                -- "You receive loot" = loot de verdade (mob, skinning, pickpocket, bau); "You receive item" so conta
                -- se acabou de entregar uma quest (recompensa). Compra, craft e correio ficam de fora.
                if e[3] or (WD._questUntil and GetTime() <= WD._questUntil) then pcall(FarmItem, id, qty) end
            end
            return
        end
    end
end

---------------------------------------------------------------------------
-- Lista premium (mobs destacados na nameplate)
---------------------------------------------------------------------------
local function TrimName(s) return (s or ""):match("^%s*(.-)%s*$") end

local function WatchTable(kind, create)
    local key = (kind == "pvp") and "watchPvp" or "watch"
    if create then WatchdogDB[key] = WatchdogDB[key] or {} end
    return WatchdogDB[key]
end

-- kind: "pve" (mobs, padrao) ou "pvp" (jogadores)
function WD:IsWatched(name, kind)
    name = Clean(name)
    if type(name) ~= "string" then return false end
    local t = WatchTable(kind)
    return t ~= nil and t[name:lower()] ~= nil
end

-- Retorna "pve"/"pvp" se a unidade esta em alguma lista (jogador -> lista PvP; resto -> lista PvE).
function WD:IsUnitWatched(unit)
    local ok, res = pcall(function()
        local name = Clean(UnitName(unit))
        if type(name) ~= "string" then return nil end
        local kind = UnitIsPlayer(unit) and "pvp" or "pve"
        if WD:IsWatched(name, kind) then return kind end
        return nil
    end)
    return ok and res or nil
end

function WD:AddWatch(name, kind)
    name = TrimName(name)
    if name == "" then return false end
    WatchTable(kind, true)[name:lower()] = name
    if WD.RefreshNameplates then WD:RefreshNameplates() end
    WD:UpdateTargetMacro()
    return true
end

function WD:RemoveWatch(name, kind)
    name = TrimName(name)
    local t = WatchTable(kind)
    if name == "" or not t then return end
    t[name:lower()] = nil
    if WatchdogDB and WatchdogDB.macroNames then WatchdogDB.macroNames[name:lower()] = nil end
    if WatchdogDB and WatchdogDB.alertNames then WatchdogDB.alertNames[name:lower()] = nil end
    if WD.RefreshNameplates then WD:RefreshNameplates() end
    WD:UpdateTargetMacro()
end

-- Macro de verdade (aparece em /macro): o jogador arrasta pra barra. Atualiza sozinha quando a lista muda.
local MACRO_NAME = "WD Alvo"
local MACRO_ICON = "Ability_Hunter_EagleEye"
-- O jogo so aceita icones dele para macro (imagem do addon nao funciona). Poe um icone so quando ainda esta o "?".
local function IsQuestionIcon(icon)
    return icon == nil or icon == 134400 or tostring(icon):lower():find("questionmark", 1, true) ~= nil
end
function WD:InMacro(name)
    local t = WatchdogDB and WatchdogDB.macroNames
    return t and t[name:lower()] and true or false
end
function WD:ToggleMacroName(name)
    -- so UM mob por vez: marcar um tira o outro; marcar o mesmo de novo desmarca
    local k = name:lower()
    local was = WatchdogDB.macroNames and WatchdogDB.macroNames[k]
    WatchdogDB.macroNames = was and {} or { [k] = true }
    WD:SyncMacro(false)
end
function WD:MacroBody()
    local names = {}
    for _, kind in ipairs({ "pve", "pvp" }) do
        for _, n in ipairs(WD:WatchList(kind)) do
            if WD:InMacro(n) then names[#names + 1] = n end
        end
    end
    local tail = "\n/cleartarget [dead]"
    local lines, len, dropped = {}, #tail, 0
    for _, n in ipairs(names) do
        local line = "/targetexact " .. n
        if len + #line + 1 > 255 then dropped = dropped + 1
        else lines[#lines + 1] = line; len = len + #line + 1 end
    end
    local rev = {}
    for i = #lines, 1, -1 do rev[#rev + 1] = lines[i] end
    if #rev == 0 then return "/cleartarget [dead]", dropped end
    return table.concat(rev, "\n") .. tail, dropped
end
function WD:SyncMacro(create)
    if InCombatLockdown() or not GetMacroIndexByName then return false end
    local body, dropped = WD:MacroBody()
    local idx = GetMacroIndexByName(MACRO_NAME)
    if not idx or idx == 0 then
        if not create then return false end
        local ok, res = pcall(CreateMacro, MACRO_NAME, MACRO_ICON, body, false)
        if not ok or not res then ok, res = pcall(CreateMacro, MACRO_NAME, MACRO_ICON, body, true) end
        if not ok or not res then return false end
        if WatchdogDB then WatchdogDB.macroIcon = MACRO_ICON end
    else
        local _, icon, curBody = GetMacroInfo(idx)
        -- aplica o icone do addon quando ainda esta "?" ou quando o icone do addon mudou de versao
        local apply = IsQuestionIcon(icon) or (WatchdogDB and WatchdogDB.macroIcon ~= MACRO_ICON)
        -- so mexe na macro quando algo realmente mudou (EditMacro dispara atualizacao das barras de acao)
        if curBody ~= body or apply then
            pcall(EditMacro, idx, nil, apply and MACRO_ICON or nil, body)
        end
        if apply and WatchdogDB then WatchdogDB.macroIcon = MACRO_ICON end
    end
    WD.macroDropped = dropped
    return true
end
function WD:PickupTargetMacro()
    if InCombatLockdown() then return false, "combat" end
    if not WD:SyncMacro(true) then return false, "full" end
    pcall(PickupMacro, MACRO_NAME)
    return true
end
function WD:UpdateTargetMacro()
    if InCombatLockdown() then WD._targetPending = true; return end
    WD._targetPending = nil
    WD:SyncMacro(false)
end

function WD:WatchList(kind)
    local t = {}
    local src = WatchTable(kind)
    if src then
        for _, disp in pairs(src) do t[#t + 1] = disp end
    end
    table.sort(t, function(a, b) return a:lower() < b:lower() end)
    return t
end

-- Nomes vistos por ultimo (inimigos mirados / sob o mouse / em plaquinhas) para escolher na Black list.
local SEEN_MAX = 15
function WD:RememberSeen(unit)
    pcall(function()
        if not unit or not UnitExists(unit) or UnitIsUnit(unit, "player") then return end
        if not UnitCanAttack("player", unit) then return end
        local name = Clean(UnitName(unit))
        if type(name) ~= "string" or name == "" then return end
        local kind = UnitIsPlayer(unit) and "pvp" or "pve"
        if kind == "pve" and UnitPlayerControlled and UnitPlayerControlled(unit) then return end
        WatchdogDB.seen = WatchdogDB.seen or {}
        local l = WatchdogDB.seen[kind]
        if not l then l = {}; WatchdogDB.seen[kind] = l end
        if l[1] and l[1]:lower() == name:lower() then return end
        for i = #l, 1, -1 do
            if l[i]:lower() == name:lower() then table.remove(l, i) end
        end
        table.insert(l, 1, name)
        while #l > SEEN_MAX do table.remove(l) end
    end)
end

function WD:SeenList(kind)
    local l = WatchdogDB.seen and WatchdogDB.seen[kind == "pvp" and "pvp" or "pve"]
    return l or {}
end

---------------------------------------------------------------------------
-- Mob raro
---------------------------------------------------------------------------
local function CheckRare(unit)
    if not unit or not UnitExists(unit) or UnitIsPlayer(unit) or UnitIsDead(unit) then return end
    local cls = UnitClassification and UnitClassification(unit)
    if cls ~= "rare" and cls ~= "rareelite" then return end
    local guid, name = Clean(UnitGUID(unit)), Clean(UnitName(unit))
    if type(guid) ~= "string" or type(name) ~= "string" then return end
    WatchdogDB.rareNames[name] = true
    if rareSeen[guid] then return end
    rareSeen[guid] = GetTime()
    if WatchdogDB.alerts.rare then
        local lvl = UnitLevel(unit)
        local text = string.format(L.alert_rare_body, name, (lvl and lvl > 0) and lvl or "??")
        WD:Alert("rare", L.alert_rare, text, nil)
    end
end

-- Alerta de mob da Black list marcado com "A+": avisa como mob raro, uma vez por mob (por guid).
function WD:InAlert(name)
    local t = WatchdogDB and WatchdogDB.alertNames
    return t and t[name:lower()] and true or false
end
function WD:ToggleAlertName(name)
    WatchdogDB.alertNames = WatchdogDB.alertNames or {}
    local k = name:lower()
    WatchdogDB.alertNames[k] = (not WatchdogDB.alertNames[k]) or nil
end
local function CheckWatchAlert(unit)
    if not unit or not UnitExists(unit) or UnitIsDead(unit) then return end
    local t = WatchdogDB.alertNames
    if not t or not next(t) then return end
    local guid, name = Clean(UnitGUID(unit)), Clean(UnitName(unit))
    if type(guid) ~= "string" or type(name) ~= "string" then return end
    if not t[name:lower()] then return end
    if not WD:IsUnitWatched(unit) then return end
    local key = "A" .. guid
    if rareSeen[key] then return end
    rareSeen[key] = GetTime()
    local lvl = UnitLevel(unit)
    WD:Alert("rare", L.alert_mob, string.format(L.alert_rare_body, name, (lvl and lvl > 0) and lvl or "??"), nil)
end

local function Prune()
    local now = GetTime()
    for guid, c in pairs(corpseName) do
        if now - c.t > CORPSE_TTL then corpseName[guid] = nil end
    end
    for key, t in pairs(lootSeen) do
        if now - t > CORPSE_TTL then lootSeen[key] = nil end
    end
    for key, t in pairs(alertSeen) do
        if now - t > CORPSE_TTL then alertSeen[key] = nil end
    end
    for guid, t in pairs(rareSeen) do
        if now - t > 600 then rareSeen[guid] = nil end
    end
    -- guidMob so cresce com corpos lootados; limpa de vez em quando.
    local n = 0
    for _ in pairs(guidMob) do n = n + 1 end
    if n > 400 then guidMob = {}; guidHit = {} end
    if WatchdogCharDB then WatchdogCharDB.sessionLast = time() end
    pcall(WD.UpdateBagValue, WD)
end

---------------------------------------------------------------------------
-- Eventos
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
WD.ev = ev

local EVENTS = {
    "PLAYER_ENTERING_WORLD",
    "PLAYER_LOGOUT",
    "PLAYER_DEAD",
    "PLAYER_XP_UPDATE",
    "PLAYER_TARGET_CHANGED",
    "UPDATE_MOUSEOVER_UNIT",
    "UNIT_PET",
    "LOOT_READY",
    "LOOT_OPENED",
    "CHAT_MSG_MONEY",
    "CHAT_MSG_COMBAT_XP_GAIN",
    "CHAT_MSG_COMBAT_HONOR_GAIN",
}

-- Eventos que nem todo cliente tem: registra sem reclamar se falhar.
local OPTIONAL_EVENTS = {
    "CHAT_MSG_LOOT",
    "CHAT_MSG_COMBAT_HOSTILE_DEATH",
    "CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS",
    "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE",
    "NAME_PLATE_UNIT_ADDED",
    "PLAYER_REGEN_ENABLED",
    "BAG_UPDATE_DELAYED",
    "BAG_UPDATE",
    "QUEST_TURNED_IN",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_MONEY",
    "BANKFRAME_OPENED",
    "BANKFRAME_CLOSED",
    "AUCTION_HOUSE_SHOW",
    "AUCTION_HOUSE_CLOSED",
    "MAIL_SHOW",
    "MAIL_CLOSED",
}

local function Register(event)
    local ok = pcall(ev.RegisterEvent, ev, event)
    if not ok or not ev:IsEventRegistered(event) then
        WD.failed[#WD.failed + 1] = event
        print("|cffff5555Watchdog:|r nao consegui registrar o evento " .. event)
    end
end

function WD:PrintStatus()
    print("|cffffd100Watchdog " .. WD.version .. "|r " .. L.status_title)
    for _, e in ipairs(EVENTS) do
        print(string.format("  %s %s", ev:IsEventRegistered(e) and "|cff00ff00OK|r " or "|cffff0000FALHOU|r", e))
    end
    for _, e in ipairs(OPTIONAL_EVENTS) do
        print(string.format("  %s %s %s", ev:IsEventRegistered(e) and "|cff00ff00OK|r " or ("|cff888888" .. L.status_missing .. "|r"), e, L.status_optional))
    end
    print("  padrao XP:    " .. tostring(PAT.xp))
    print("  padrao slain: " .. tostring(PAT.slain))
    print("  padrao honra: " .. tostring(PAT.honor))
    print("  padrao ouro/prata/cobre: " .. tostring(PAT.gold) .. " / " .. tostring(PAT.silver) .. " / " .. tostring(PAT.copper))
    local s = WD.stats
    print(string.format("  desde o login: msgs XP=%d slain=%d honra=%d dinheiro=%d | kills mob=%d pvp=%d | drops=%d",
        s.xpMsgs, s.slainMsgs, s.honorMsgs, s.moneyMsgs, s.mobKills, s.pvpKills, s.drops))
end

-- Diagnostico: liga o registro de taint (Logs/taint.log) em todo login, pois o jogo o desliga sozinho.
function WD:ApplyTaintLog()
    if not WatchdogDB or WatchdogDB.taintLog == false then return end
    pcall(SetCVar, "taintLog", "2")
    if tostring(GetCVar and GetCVar("taintLog") or "") ~= "2" and ConsoleExec then
        pcall(ConsoleExec, "taintLog 2")
    end
end

local function Init()
    WatchdogDB = WatchdogDB or {}
    WD:ApplyTaintLog()
    WatchdogDB.items = WatchdogDB.items or {}
    WatchdogDB.rareNames = WatchdogDB.rareNames or {}
    WatchdogDB.watch = WatchdogDB.watch or {}
    WatchdogDB.ahPrices = WatchdogDB.ahPrices or {}
    AHOpt()
    -- Regra de valorizacao mudou nesta versao (soulbound = vendor): reajusta o ponto de partida da sessao.
    if WatchdogDB.valRev ~= 2 then WatchdogDB.valSig = (WatchdogDB.valSig or 0) + 1; WatchdogDB.valRev = 2 end
    WatchdogDB.alerts = WatchdogDB.alerts or {}
    local a = WatchdogDB.alerts
    if a.drop == nil then a.drop = true end
    if a.rare == nil then a.rare = true end
    if a.sound == nil then a.sound = true end
    if a.minQuality == nil then a.minQuality = 3 end
    if WD.ResolveLocale then WD:ResolveLocale() end

    WatchdogCharDB = WatchdogCharDB or {}
    -- Instalacao nova (sem nenhum dado antigo) -> mostra o wizard de boas-vindas.
    WD.freshInstall = (WatchdogDB.wizardDone == nil) and next(WatchdogCharDB) == nil and next(WatchdogDB.items) == nil
    if WatchdogDB.wizardDone == nil and not WD.freshInstall then WatchdogDB.wizardDone = true end
    WatchdogCharDB.days = WatchdogCharDB.days or {}
    WatchdogCharDB.history = WatchdogCharDB.history or {}
    if not WatchdogCharDB.session then NewSession() end
    -- (nao mexe em sessionLast aqui: no login ele guarda o instante do ultimo logout/gravacao,
    --  que e quando a sessao anterior realmente terminou.)

    BuildPatterns()
    for _, e in ipairs(EVENTS) do Register(e) end
    for _, e in ipairs(OPTIONAL_EVENTS) do pcall(ev.RegisterEvent, ev, e) end

    C_Timer.NewTicker(0.5, function() pcall(ScanPvPThreat) end)
    C_Timer.NewTicker(60, Prune)
    C_Timer.NewTicker(2, function() pcall(ActivityTick) end)
    -- Atualiza XP/hora, ouro/hora e tempo de sessao com a janela aberta.
    C_Timer.NewTicker(5, function()
        local s = WatchdogCharDB and WatchdogCharDB.session
        if s and s.bagStart == nil then pcall(WD.UpdateBagValue, WD) end
        WD:Refresh()
    end)
    -- Repinta nameplates da lista premium (rede de seguranca).
    C_Timer.NewTicker(0.5, function() if WD.RefreshNameplates then WD:RefreshNameplates() end end)
end

ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(_, event, ...)
    local arg1 = ...
    if event == "CHAT_MSG_COMBAT_XP_GAIN" then
        OnXPMessage(arg1 or "")
    elseif event == "CHAT_MSG_COMBAT_HOSTILE_DEATH" then
        OnSlainMessage(arg1 or "")
    elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN" then
        OnHonorGain(arg1)
    elseif event == "CHAT_MSG_MONEY" then
        OnMoneyMessage(arg1)
    elseif event == "CHAT_MSG_LOOT" then
        pcall(OnLootMessage, arg1)
    elseif event == "CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS" or event == "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE" then
        OnHostilePlayerHit()
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
        OnLoot()
    elseif event == "PLAYER_XP_UPDATE" then
        OnXPUpdate()
    elseif event == "PLAYER_DEAD" then
        OnPlayerDead()
    elseif event == "PLAYER_TARGET_CHANGED" then
        WD:RememberSeen("target")
        pcall(RememberCorpse, "target")
        pcall(CheckRare, "target")
        pcall(CheckWatchAlert, "target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        WD:RememberSeen("mouseover")
        pcall(RememberCorpse, "mouseover")
        pcall(CheckRare, "mouseover")
        pcall(CheckWatchAlert, "mouseover")
    elseif event == "PLAYER_MONEY" then
        pcall(OnPlayerMoney)
    elseif event == "BANKFRAME_OPENED" then
        bankOpen = true
        pcall(WD.UpdateBagValue, WD)   -- leitura na hora, antes de voce mexer nos itens
    elseif event == "BANKFRAME_CLOSED" then
        pcall(WD.UpdateBagValue, WD)
        bankOpen = false
    elseif event == "NEW_AUCTION_UPDATE" then
        pcall(WD.OnSellSlot, WD)
    elseif event == "AUCTION_HOUSE_SHOW" then
        pcall(WD.UpdateBagValue, WD)
        ahOpen = true
    elseif event == "AUCTION_HOUSE_CLOSED" then
        pcall(WD.UpdateBagValue, WD)
        ahOpen = false
    elseif event == "MAIL_SHOW" then
        pcall(WD.UpdateBagValue, WD)
        pcall(WD.QueueMailHistory, WD)
        mailOpen = true
    elseif event == "MAIL_CLOSED" then
        pcall(WD.UpdateBagValue, WD)
        mailOpen = false
    elseif event == "QUEST_TURNED_IN" then
        pcall(OnQuestTurnedIn, ...)
    elseif event == "PLAYER_REGEN_DISABLED" then
        WD:MarkActive()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if WD._cvarPending and WD.MaxNameplateRange then WD:MaxNameplateRange() end
        if WD._targetPending then WD:UpdateTargetMacro() end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        WD:RememberSeen(arg1)
        pcall(CheckRare, arg1)
        pcall(CheckWatchAlert, arg1)
        if WD.OnNameplateAdded then WD:OnNameplateAdded(arg1) end
    elseif event == "BAG_UPDATE_DELAYED" or event == "BAG_UPDATE" then
        if event == "BAG_UPDATE_DELAYED" then WD:QueueBagValue() end
        WD:Refresh()
    elseif event == "PLAYER_LOGOUT" then
        if WatchdogCharDB then
            pcall(WD.UpdateBagValue, WD)
            WatchdogCharDB.sessionLast = time()
        end
    elseif event == "UNIT_PET" then
        if arg1 == "player" then petGUID = UnitGUID("pet") end
    elseif event == "PLAYER_ENTERING_WORLD" then
        playerGUID = UnitGUID("player")
        petGUID = UnitGUID("pet")
        pcall(WD.SetupAHHooks, WD)
        if arg1 then
            -- Nova sessao a cada login (um /reload mantem a sessao).
            NewSession()
            WatchdogCharDB.loginStamp = time()
        else
            WatchdogCharDB.sessionLast = time()   -- /reload: a sessao continua
        end
        C_Timer.After(5, function() pcall(WD.UpdateBagValue, WD) end)
        SnapshotXP()
        lastMoney = GetMoney and GetMoney() or nil
        WD:Refresh()
    elseif event == "ADDON_LOADED" and arg1 == ADDON then
        ev:UnregisterEvent("ADDON_LOADED")
        Init()
    end
end)

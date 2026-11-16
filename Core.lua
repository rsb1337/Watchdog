-- Watchdog: rastreamento de kills PvE/PvP, honra, drops, dinheiro, EXP e inventario.
-- Usa eventos de chat/XP/honra/loot e o combat log (apenas leitura) para mortes PvP.
-- Tudo vem de eventos de chat, XP, honra, loot e bolsas.
local ADDON, WD = ...
local L = WD.L
WD.version = "1.4.4"
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

-- Guarda a sessao que acabou no historico (se teve atividade).
local function ArchiveSession()
    local s = WatchdogCharDB.session
    if not s then return end
    local start = WatchdogCharDB.sessionStart or time()
    local stop = WatchdogCharDB.sessionLast or time()
    local dur = stop - start
    local kills = 0
    for _, m in pairs(s.mobs) do kills = kills + (m.kills or 0) end
    local pvp = s.pvp or {}
    local active = kills > 0 or (s.xp or 0) > 0 or (pvp.kills or 0) > 0 or (s.money or 0) > 0
    if not active or dur < 60 then return end

    local h = WatchdogCharDB.history
    h[#h + 1] = {
        start = start, stop = stop,
        kills = kills,
        xp = s.xp or 0,
        levels = s.levels or 0,
        pvpKills = pvp.kills or 0,
        deaths = pvp.deaths or 0,
        honor = pvp.honor or 0,
        money = s.money or 0,
        value = WD:BucketValue(s),
    }
    while #h > HISTORY_MAX do table.remove(h, 1) end
end

local function NewSession()
    ArchiveSession()
    local s = NewBucket()
    s.killXP, s.killXPCount, s.levels = 0, 0, 0
    WatchdogCharDB.session = s
    WatchdogCharDB.sessionStart = time()
    WatchdogCharDB.sessionLast = time()
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

-- Valor (cobre) dos itens dropados por um mob, sem o dinheiro.
function WD:MobItemsValue(mob)
    local total = 0
    for id, qty in pairs(mob.loot) do
        local _, _, sell = self:GetItemDisplay(id)
        if sell and sell > 0 then total = total + sell * qty end
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
            return info.iconFileID, info.stackCount or 1, info.quality, info.hyperlink, info.itemID
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
function WD:ScanBags()
    local out = { slots = {}, total = 0, used = 0, value = 0 }
    local maxBag = NUM_BAG_SLOTS or 4
    for bag = 0, maxBag do
        local n = GetNumSlots and GetNumSlots(bag) or 0
        for slot = 1, n do
            local icon, count, quality, link, itemID = ReadSlot(bag, slot)
            local entry = { bag = bag, slot = slot }
            out.total = out.total + 1
            if icon then
                itemID = itemID or (link and tonumber(link:match("item:(%d+)")))
                entry.icon, entry.count, entry.link, entry.itemID = icon, count or 1, link, itemID
                entry.quality = (quality and quality >= 0) and quality or nil
                if itemID then
                    local name, q, sell = self:GetItemDisplay(itemID)
                    entry.name = name
                    entry.quality = entry.quality or q
                    entry.sell = sell
                    entry.value = (sell or 0) * entry.count
                    out.value = out.value + entry.value
                end
                out.used = out.used + 1
            end
            out.slots[#out.slots + 1] = entry
        end
    end
    return out
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

local function CountMobKill(name)
    Each(function(b)
        local m = GetMob(b, name)
        m.kills = m.kills + 1
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
-- Lista premium (mobs destacados na nameplate)
---------------------------------------------------------------------------
local function TrimName(s) return (s or ""):match("^%s*(.-)%s*$") end

function WD:IsWatched(name)
    name = Clean(name)
    if type(name) ~= "string" or not WatchdogDB.watch then return false end
    return WatchdogDB.watch[name:lower()] ~= nil
end

function WD:AddWatch(name)
    name = TrimName(name)
    if name == "" then return false end
    WatchdogDB.watch = WatchdogDB.watch or {}
    WatchdogDB.watch[name:lower()] = name
    if WD.RefreshNameplates then WD:RefreshNameplates() end
    return true
end

function WD:RemoveWatch(name)
    name = TrimName(name)
    if name == "" or not WatchdogDB.watch then return end
    WatchdogDB.watch[name:lower()] = nil
    if WD.RefreshNameplates then WD:RefreshNameplates() end
end

function WD:WatchList()
    local t = {}
    if WatchdogDB.watch then
        for _, disp in pairs(WatchdogDB.watch) do t[#t + 1] = disp end
    end
    table.sort(t, function(a, b) return a:lower() < b:lower() end)
    return t
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
end

---------------------------------------------------------------------------
-- Eventos
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")

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
    "CHAT_MSG_COMBAT_HOSTILE_DEATH",
    "CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS",
    "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE",
    "NAME_PLATE_UNIT_ADDED",
    "PLAYER_REGEN_ENABLED",
    "BAG_UPDATE_DELAYED",
    "BAG_UPDATE",
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

local function Init()
    WatchdogDB = WatchdogDB or {}
    WatchdogDB.items = WatchdogDB.items or {}
    WatchdogDB.rareNames = WatchdogDB.rareNames or {}
    WatchdogDB.watch = WatchdogDB.watch or {}
    WatchdogDB.alerts = WatchdogDB.alerts or {}
    local a = WatchdogDB.alerts
    if a.drop == nil then a.drop = true end
    if a.rare == nil then a.rare = true end
    if a.sound == nil then a.sound = true end
    if a.minQuality == nil then a.minQuality = 3 end
    if WD.ResolveLocale then WD:ResolveLocale() end

    WatchdogCharDB = WatchdogCharDB or {}
    WatchdogCharDB.days = WatchdogCharDB.days or {}
    WatchdogCharDB.history = WatchdogCharDB.history or {}
    if not WatchdogCharDB.session then NewSession() end
    WatchdogCharDB.sessionLast = time()

    BuildPatterns()
    for _, e in ipairs(EVENTS) do Register(e) end
    for _, e in ipairs(OPTIONAL_EVENTS) do pcall(ev.RegisterEvent, ev, e) end

    C_Timer.NewTicker(0.5, function() pcall(ScanPvPThreat) end)
    C_Timer.NewTicker(60, Prune)
    -- Atualiza XP/hora, ouro/hora e tempo de sessao com a janela aberta.
    C_Timer.NewTicker(5, function() WD:Refresh() end)
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
    elseif event == "CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS" or event == "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE" then
        OnHostilePlayerHit()
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
        OnLoot()
    elseif event == "PLAYER_XP_UPDATE" then
        OnXPUpdate()
    elseif event == "PLAYER_DEAD" then
        OnPlayerDead()
    elseif event == "PLAYER_TARGET_CHANGED" then
        pcall(RememberCorpse, "target")
        pcall(CheckRare, "target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        pcall(RememberCorpse, "mouseover")
        pcall(CheckRare, "mouseover")
    elseif event == "PLAYER_REGEN_ENABLED" then
        if WD._cvarPending and WD.MaxNameplateRange then WD:MaxNameplateRange() end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        pcall(CheckRare, arg1)
        if WD.OnNameplateAdded then WD:OnNameplateAdded(arg1) end
    elseif event == "BAG_UPDATE_DELAYED" or event == "BAG_UPDATE" then
        WD:Refresh()
    elseif event == "PLAYER_LOGOUT" then
        if WatchdogCharDB then WatchdogCharDB.sessionLast = time() end
    elseif event == "UNIT_PET" then
        if arg1 == "player" then petGUID = UnitGUID("pet") end
    elseif event == "PLAYER_ENTERING_WORLD" then
        playerGUID = UnitGUID("player")
        petGUID = UnitGUID("pet")
        if arg1 then
            -- Nova sessao a cada login (um /reload mantem a sessao).
            NewSession()
        end
        SnapshotXP()
        WD:Refresh()
    elseif event == "ADDON_LOADED" and arg1 == ADDON then
        ev:UnregisterEvent("ADDON_LOADED")
        Init()
    end
end)

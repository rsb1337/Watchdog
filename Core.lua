-- Watchdog: rastreamento de kills PvE/PvP, honra, drops e EXP.
local ADDON, WD = ...
WD.version = "1.0.0"

local band = bit.band
local GetTime = GetTime
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local strsplit = strsplit

local HOSTILE = COMBATLOG_OBJECT_REACTION_HOSTILE or 0x00000040
local CONTROL_PLAYER = COMBATLOG_OBJECT_CONTROL_PLAYER or 0x00000100
local LOOT_ITEM = LOOT_SLOT_ITEM or 1

local PVP_DEATH_WINDOW = 15   -- segundos apos dano de jogador inimigo para contar morte PvP
local DAMAGED_TTL = 180       -- quanto tempo lembramos que batemos num mob
local KILLED_TTL = 1800       -- quanto tempo um corpo pode ser lootado/skinado

local playerGUID, petGUID
local damaged = {}  -- [guid] = GetTime() do ultimo dano nosso
local killed = {}   -- [guid] = { name = string, t = GetTime(), seen = { [itemID] = true } }
local lastPvPHit = 0
local lastXP, lastMaxXP, lastLevel
local lastKillTime = 0
local pendingXP, pendingXPTime = 0, 0
local KILL_XP_WINDOW = 1.5    -- XP recebida ate 1.5s de uma kill conta como XP de kill

local function AddKillXP(amount)
    local s = WatchdogCharDB.session
    s.killXP = (s.killXP or 0) + amount
    s.killXPCount = (s.killXPCount or 0) + 1
end

---------------------------------------------------------------------------
-- Dados
---------------------------------------------------------------------------
local function NewBucket()
    return { pvp = { kills = 0, deaths = 0, honor = 0 }, mobs = {}, xp = 0 }
end
WD.NewBucket = NewBucket

local function NewSession()
    local s = NewBucket()
    s.killXP, s.killXPCount, s.levels = 0, 0, 0
    WatchdogCharDB.session = s
    WatchdogCharDB.sessionStart = time()
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

local function GetMob(bucket, name)
    local m = bucket.mobs[name]
    if not m then
        m = { kills = 0, loot = {} }
        bucket.mobs[name] = m
    end
    return m
end
WD.GetMob = GetMob

-- Toda contagem vai para o dia de hoje e para a sessao atual.
local function Each(fn)
    fn(GetDay())
    fn(WatchdogCharDB.session)
end

function WD:CacheItem(itemID, name, quality)
    if not itemID or not name or name == "" then return end
    local c = WatchdogDB.items[itemID]
    if not c then
        WatchdogDB.items[itemID] = { n = name, q = quality }
    elseif quality and c.q ~= quality then
        c.q = quality
    end
end

function WD:GetItemDisplay(itemID)
    local c = WatchdogDB.items[itemID]
    local name, quality = c and c.n, c and c.q
    if not name then
        local n, _, q = GetItemInfo(itemID)
        name, quality = n, q
        if n then self:CacheItem(itemID, n, q) end
    end
    return name or ("Item #" .. itemID), quality
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
    for name, m in pairs(b.mobs) do
        local o = GetMob(out, name)
        o.kills = o.kills + (m.kills or 0)
        for id, q in pairs(m.loot) do
            o.loot[id] = (o.loot[id] or 0) + q
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
    NewSession()
    self:Refresh()
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
        -- XP que chega junto com uma kill conta para a media de XP por kill.
        -- O evento de XP pode chegar antes ou depois do evento de morte.
        if GetTime() - lastKillTime <= KILL_XP_WINDOW then
            AddKillXP(gained)
            lastKillTime = 0
        else
            pendingXP, pendingXPTime = gained, GetTime()
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
-- Kills / PvP / Loot
---------------------------------------------------------------------------
local function IsCreature(guid)
    local kind = strsplit("-", guid)
    return kind == "Creature" or kind == "Vehicle"
end

local function IsEnemyPlayer(guid, flags)
    local kind = strsplit("-", guid)
    return kind == "Player" and band(flags or 0, HOSTILE) > 0
end

local function AddMobKill(guid, name)
    if killed[guid] or not name then return end
    killed[guid] = { name = name, t = GetTime(), seen = {} }
    damaged[guid] = nil
    if pendingXP > 0 and GetTime() - pendingXPTime <= KILL_XP_WINDOW then
        AddKillXP(pendingXP)
        pendingXP = 0
    else
        lastKillTime = GetTime()
    end
    Each(function(b)
        local m = GetMob(b, name)
        m.kills = m.kills + 1
    end)
    WD:Refresh()
end

local function OnCombatLog()
    local _, sub, _, srcGUID, _, srcFlags, _, dstGUID, dstName, dstFlags = CombatLogGetCurrentEventInfo()
    if not dstGUID or dstGUID == "" then return end

    local fromMe = srcGUID == playerGUID or (petGUID ~= nil and srcGUID == petGUID)

    if sub == "PARTY_KILL" then
        if fromMe then
            if IsCreature(dstGUID) then
                AddMobKill(dstGUID, dstName)
            elseif IsEnemyPlayer(dstGUID, dstFlags) then
                Each(function(b) b.pvp.kills = b.pvp.kills + 1 end)
                WD:Refresh()
            end
        end
    elseif sub == "UNIT_DIED" then
        if damaged[dstGUID] and IsCreature(dstGUID) then
            AddMobKill(dstGUID, dstName)
        end
    elseif fromMe then
        if IsCreature(dstGUID) and sub:find("_DAMAGE", 1, true) then
            damaged[dstGUID] = GetTime()
        end
    elseif dstGUID == playerGUID and sub:find("_DAMAGE", 1, true) then
        -- Dano vindo de um jogador inimigo (ou do pet dele)
        if srcFlags and band(srcFlags, CONTROL_PLAYER) > 0 and band(srcFlags, HOSTILE) > 0 then
            lastPvPHit = GetTime()
        end
    end
end

local function OnPlayerDead()
    if lastPvPHit > 0 and (GetTime() - lastPvPHit) <= PVP_DEATH_WINDOW then
        Each(function(b) b.pvp.deaths = b.pvp.deaths + 1 end)
        WD:Refresh()
    end
    lastPvPHit = 0
end

-- Pega o ultimo numero da mensagem de honra, que e o valor ganho
-- ("Voce recebeu 50 pontos de honra." / "... (Pontos de Honra Estimados: 12)").
local function OnHonorGain(msg)
    if type(msg) ~= "string" then return end
    local last
    for n in msg:gmatch("%d+") do last = n end
    local value = tonumber(last)
    if value and value > 0 then
        Each(function(b) b.pvp.honor = b.pvp.honor + value end)
        WD:Refresh()
    end
end

local function RecordLoot(guid, itemID, qty)
    local info = guid and killed[guid]
    if not info or info.seen[itemID] then return false end
    info.seen[itemID] = true
    Each(function(b)
        local m = GetMob(b, info.name)
        m.loot[itemID] = (m.loot[itemID] or 0) + qty
    end)
    return true
end

local function FallbackLootGUID()
    for _, unit in ipairs({ "mouseover", "target" }) do
        local guid = UnitGUID(unit)
        if guid and killed[guid] and UnitIsDead(unit) then return guid end
    end
end

local function OnLoot()
    local changed = false
    for slot = 1, GetNumLootItems() do
        if GetLootSlotType(slot) == LOOT_ITEM then
            local link = GetLootSlotLink(slot)
            local itemID = link and tonumber(link:match("item:(%d+)"))
            if itemID then
                local _, itemName, quantity, _, quality = GetLootSlotInfo(slot)
                WD:CacheItem(itemID, itemName, quality)
                if GetLootSourceInfo then
                    local src = { GetLootSourceInfo(slot) }
                    for i = 1, #src, 2 do
                        if RecordLoot(src[i], itemID, src[i + 1] or 1) then changed = true end
                    end
                else
                    if RecordLoot(FallbackLootGUID(), itemID, quantity or 1) then changed = true end
                end
            end
        end
    end
    if changed then WD:Refresh() end
end

local function Prune()
    local now = GetTime()
    for guid, t in pairs(damaged) do
        if now - t > DAMAGED_TTL then damaged[guid] = nil end
    end
    for guid, info in pairs(killed) do
        if now - info.t > KILLED_TTL then killed[guid] = nil end
    end
end

---------------------------------------------------------------------------
-- Eventos
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")

local function SafeRegister(event)
    pcall(ev.RegisterEvent, ev, event)
end

local function Init()
    WatchdogDB = WatchdogDB or {}
    WatchdogDB.items = WatchdogDB.items or {}
    WatchdogCharDB = WatchdogCharDB or {}
    WatchdogCharDB.days = WatchdogCharDB.days or {}
    if not WatchdogCharDB.session then NewSession() end

    SafeRegister("PLAYER_ENTERING_WORLD")
    SafeRegister("COMBAT_LOG_EVENT_UNFILTERED")
    SafeRegister("PLAYER_DEAD")
    SafeRegister("CHAT_MSG_COMBAT_HONOR_GAIN")
    SafeRegister("PLAYER_XP_UPDATE")
    SafeRegister("LOOT_READY")
    SafeRegister("LOOT_OPENED")
    SafeRegister("UNIT_PET")

    C_Timer.NewTicker(60, Prune)
    -- Atualiza XP/hora e tempo de sessao com a janela aberta.
    C_Timer.NewTicker(5, function() WD:Refresh() end)
end

ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(_, event, ...)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLog()
    elseif event == "LOOT_READY" or event == "LOOT_OPENED" then
        OnLoot()
    elseif event == "PLAYER_XP_UPDATE" then
        OnXPUpdate()
    elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN" then
        OnHonorGain(...)
    elseif event == "PLAYER_DEAD" then
        OnPlayerDead()
    elseif event == "UNIT_PET" then
        if ... == "player" then petGUID = UnitGUID("pet") end
    elseif event == "PLAYER_ENTERING_WORLD" then
        local isInitialLogin = ...
        playerGUID = UnitGUID("player")
        petGUID = UnitGUID("pet")
        if isInitialLogin then
            -- Nova sessao a cada login (um /reload mantem a sessao).
            NewSession()
        end
        SnapshotXP()
        WD:Refresh()
    elseif event == "ADDON_LOADED" and ... == ADDON then
        ev:UnregisterEvent("ADDON_LOADED")
        Init()
    end
end)

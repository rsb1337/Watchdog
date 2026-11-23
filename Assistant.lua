-- Watchdog: modulo Assistente
--  1) aviso grande quando buffs / venenos estao acabando
--  2) icone + tempo dos CCs do Rogue sobre o alvo
--  3) aviso de reparo ao entrar em local com NPC de reparo
--  4) aviso de comida baixa ao entrar em local com vendedor de comida
--  5) aviso de consumiveis baixos perto de NPC de profissao / leilao
--  6) menu de configuracao (/wd config)
-- Nao usa o combat log (bloqueado neste cliente) e filtra "secret values".
local _, WD = ...
local L = WD.L
local Clean = WD.Clean or function(v) return v end

local BT = BackdropTemplateMixin and "BackdropTemplate" or nil
local FONT = STANDARD_TEXT_FONT
local GetTime = GetTime

---------------------------------------------------------------------------
-- Configuracao (salva em WatchdogDB.assist)
---------------------------------------------------------------------------
local DEFAULTS = {
    sound = true,
    bigScale = 100,
    buff = { on = true, warnSec = 60, minDur = 5, expired = true, poisons = true, names = {} },
    cc = { on = true, dr = true, size = 48, cats = { stun = true, incap = true, fear = true, root = true, silence = true, other = true }, spells = {} },
    dots = { on = true, size = 28, warn = 3, spells = {} },
    repair = { on = true, pct = 40 },
    food = { on = true, count = 10 },
    cons = { on = true, min = 10, byClass = {} },
    spots = {},
    known = {},
}

local function Copy(t)
    local o = {}
    for k, v in pairs(t) do o[k] = type(v) == "table" and Copy(v) or v end
    return o
end

local function Fill(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = Copy(v)
            elseif v[1] == nil then
                Fill(dst[k], v)   -- tabela de chaves; listas (arrays) nao sao preenchidas de novo
            end
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function ClassFileEarly()
    local ok, _, c = pcall(UnitClass, "player")
    return ok and c or nil
end

local cfg
function WD:Cfg()
    if cfg then return cfg end
    if not WatchdogDB then return DEFAULTS end
    WatchdogDB.assist = WatchdogDB.assist or {}
    Fill(WatchdogDB.assist, DEFAULTS)
    cfg = WatchdogDB.assist
    if cfg.cons.names then   -- lista antiga de nomes (1.5.0 beta)
        cfg.cons.legacy = cfg.cons.legacy or {}
        for _, n in ipairs(cfg.cons.names) do cfg.cons.legacy[#cfg.cons.legacy + 1] = { name = n, min = cfg.cons.min or 10 } end
        cfg.cons.names = nil
    end
    -- buffs curtos importantes da classe (uma vez por classe)
    cfg.buff.seeded = cfg.buff.seeded or {}
    local cls = ClassFileEarly()
    if cls and not cfg.buff.seeded[cls] then
        cfg.buff.seeded[cls] = true
        local BUFF_PRESETS = { ROGUE = { "Slice and Dice", "Adrenaline Rush", "Blade Flurry" }, WARRIOR = { "Battle Shout" } }
        for _, n in ipairs(BUFF_PRESETS[cls] or {}) do
            local have = false
            for _, e in ipairs(cfg.buff.names) do if e:lower() == n:lower() then have = true end end
            if not have then cfg.buff.names[#cfg.buff.names + 1] = n end
        end
    end
    return cfg
end

---------------------------------------------------------------------------
-- Compatibilidade de API
---------------------------------------------------------------------------
local function SpellInfo(id)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, id)
        if ok and type(info) == "table" then return info.name, info.iconID end
    end
    if GetSpellInfo then
        local ok, name, _, icon = pcall(GetSpellInfo, id)
        if ok then return name, icon end
    end
end

local function AuraAt(unit, i, filter)
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        local ok, d = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
        if not ok or not d then return nil end
        return Clean(d.name), Clean(d.icon), Clean(d.duration), Clean(d.expirationTime), Clean(d.sourceUnit), true
    end
    if UnitAura then
        local ok, name, icon, _, _, dur, exp, src = pcall(UnitAura, unit, i, filter)
        if not ok or not name then return nil end
        return Clean(name), Clean(icon), Clean(dur), Clean(exp), Clean(src), true
    end
end

local function PlayerClass()
    local _, c = UnitClass("player")
    return c
end

local PlaySoundSafe = function(id) pcall(PlaySound, id) end

-- roda uma rotina protegida; se der erro, mostra uma vez no chat (antes ficava silencioso)
local shownErr = {}
local function SafeRun(name, fn)
    local ok, err = pcall(fn)
    if not ok and not shownErr[name] then
        shownErr[name] = true
        print("|cffff5555Watchdog (" .. name .. "):|r " .. tostring(err))
    end
end


---------------------------------------------------------------------------
-- Aviso grande (estilo aviso de boss)
---------------------------------------------------------------------------
local bigs, bigQueue = {}, {}

local function CreateBig(slot)
    local K = WD.UIKit
    local C, Flat, FS = K.C, K.Flat, K.FS
    local f = CreateFrame("Frame", "WatchdogBigWarning" .. (slot > 1 and slot or ""), UIParent, K.BT)
    f.slot = slot
    f:SetSize(480, 78)
    f:SetPoint("TOP", UIParent, "TOP", 0, -170)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    Flat(f, C.bg, C.border, 0.94)
    f:Hide()

    f.mark = f:CreateTexture(nil, "BACKGROUND")           -- emblema do Watchdog ao fundo
    f.mark:SetTexture(K.MEDIA .. "emblem")
    f.mark:SetSize(84, 84)
    f.mark:SetPoint("RIGHT", f, "RIGHT", -8, 0)
    f.mark:SetAlpha(0.10)

    f.accent = f:CreateTexture(nil, "ARTWORK")            -- barra colorida a esquerda
    f.accent:SetTexture("Interface\\Buttons\\WHITE8X8")
    f.accent:SetPoint("TOPLEFT", 0, 0)
    f.accent:SetPoint("BOTTOMLEFT", 0, 0)
    f.accent:SetWidth(4)

    f.tile = CreateFrame("Frame", nil, f, K.BT)           -- icone em quadro
    f.tile:SetSize(54, 54)
    f.tile:SetPoint("LEFT", f, "LEFT", 14, 0)
    Flat(f.tile, C.tile, C.border, 1)
    f.icon = f.tile:CreateTexture(nil, "ARTWORK")
    f.icon:SetPoint("TOPLEFT", 2, -2)
    f.icon:SetPoint("BOTTOMRIGHT", -2, 2)

    f.title = FS(f, 19, C.text, "LEFT", "")
    f.title:SetPoint("TOPLEFT", f.tile, "TOPRIGHT", 12, -4)
    f.title:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    f.sub = FS(f, 13, C.dim, "LEFT", "")
    f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -5)
    f.sub:SetPoint("RIGHT", f, "RIGHT", -12, 0)

    f.bar = f:CreateTexture(nil, "OVERLAY")               -- tempo restante do aviso
    f.bar:SetTexture("Interface\\Buttons\\WHITE8X8")
    f.bar:SetHeight(2)
    f.bar:SetPoint("BOTTOMLEFT", 1, 1)

    f.t = 0
    f:SetScript("OnUpdate", function(self, dt)
        self.t = self.t + dt
        local dur = 4.5
        if self.t < 0.2 then
            self:SetAlpha(self.t / 0.2)
        elseif self.t < dur - 0.6 then
            self:SetAlpha(1)
        elseif self.t < dur then
            self:SetAlpha((dur - self.t) / 0.6)
        else
            self:Hide()
            if self.slot == 1 then
                local nxt = table.remove(bigQueue, 1)
                if nxt then WD:BigWarning(nxt.title, nxt.sub, nxt.icon, nxt.color, nil, nxt.rest) end
            end
            return
        end
        self.bar:SetWidth(math.max(1, (self.barMax or 100) * (1 - self.t / dur)))
    end)
    return f
end

-- title grande, sub opcional, icon (textura), color {r,g,b}
-- slot: posicao na pilha (1 = principal; 2, 3... ficam embaixo). rest: lista de avisos extras
-- ({title, sub, icon, color}) mostrados empilhados abaixo do principal ao mesmo tempo.
function WD:BigWarning(title, sub, icon, color, slot, rest)
    slot = slot or 1
    local big = bigs[slot]
    if not big then big = CreateBig(slot); bigs[slot] = big end
    -- aviso anterior ainda na tela? (se travou, ex: interface oculta com Alt+Z, libera depois de 7s)
    if slot == 1 and big:IsShown() and big.startedAt and (GetTime() - big.startedAt) < 7 then
        if #bigQueue < 4 then bigQueue[#bigQueue + 1] = { title = title, sub = sub, icon = icon, color = color, rest = rest } end
        return
    end
    if big:IsShown() then big:Hide() end
    local c = WD:Cfg()
    local s = (c.bigScale or 100) / 100
    color = color or { 1, 0.82, 0 }
    local K = WD.UIKit
    -- Layout em pixels fisicos: 1 unidade do frame = 1 pixel da tela. Assim todas as bordas/linhas
    -- caem exatamente na grade de pixels em qualquer tamanho (sem pedacos sumindo).
    local physW, physH
    if GetPhysicalScreenSize then physW, physH = GetPhysicalScreenSize() end
    if not physH or physH < 100 then physW, physH = 1920, 1080 end
    local ups = UIParent:GetEffectiveScale()
    if not ups or ups <= 0 then ups = 1 end
    big:SetScale((768 / physH) / ups)
    local function S(n) return math.max(1, math.floor(n * s * ups * physH / 768 + 0.5)) end   -- n em "unidades de UI" -> pixels
    local W, H = S(480), S(78)
    local B = math.max(1, S(1))        -- borda do cartao
    local TB = math.max(2, S(2))       -- borda do icone (mais grossa)
    big:SetSize(W, H)
    big:ClearAllPoints()
    big:SetPoint("TOPLEFT", UIParent, "TOPLEFT", math.floor((physW - W) / 2), -S(170) - (slot - 1) * (H + S(8)))
    big:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = B })
    big:SetBackdropColor(K.C.bg[1], K.C.bg[2], K.C.bg[3], 0.94)
    big:SetBackdropBorderColor(K.C.border[1], K.C.border[2], K.C.border[3], 1)
    big.mark:SetSize(S(84), S(84))
    big.mark:ClearAllPoints()
    big.mark:SetPoint("RIGHT", big, "RIGHT", -S(8), 0)
    big.accent:SetWidth(math.max(3, S(4)))
    big.tile:SetSize(S(54), S(54))
    big.tile:ClearAllPoints()
    big.tile:SetPoint("LEFT", big, "LEFT", S(14) + math.max(3, S(4)), 0)
    big.tile:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = TB })
    big.tile:SetBackdropColor(K.C.tile[1], K.C.tile[2], K.C.tile[3], 1)
    big.icon:ClearAllPoints()
    big.icon:SetPoint("TOPLEFT", big.tile, "TOPLEFT", TB, -TB)
    big.icon:SetPoint("BOTTOMRIGHT", big.tile, "BOTTOMRIGHT", -TB, TB)
    big.title:SetFont(K.FONT, math.max(8, S(19)), "")
    big.sub:SetFont(K.FONT, math.max(8, S(13)), "")
    big.title:ClearAllPoints()
    big.title:SetPoint("TOPLEFT", big.tile, "TOPRIGHT", S(12), -S(4))
    big.title:SetPoint("RIGHT", big, "RIGHT", -S(12), 0)
    big.sub:ClearAllPoints()
    big.sub:SetPoint("TOPLEFT", big.title, "BOTTOMLEFT", 0, -S(5))
    big.sub:SetPoint("RIGHT", big, "RIGHT", -S(12), 0)
    big.bar:SetHeight(math.max(2, S(2)))
    big.bar:ClearAllPoints()
    big.bar:SetPoint("BOTTOMLEFT", big, "BOTTOMLEFT", B, B)
    big.barMax = W - 2 * B
    big.title:SetText(title or "")
    big.title:SetTextColor(color[1], color[2], color[3])
    big.sub:SetText(sub or "")
    big.accent:SetVertexColor(color[1], color[2], color[3])
    big.bar:SetVertexColor(color[1], color[2], color[3])
    big.tile:SetBackdropBorderColor(color[1], color[2], color[3], 1)
    big.icon:SetTexture(icon or (WD.UIKit.MEDIA .. "emblem_icon"))
    big.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    big.t = 0
    big.startedAt = GetTime()
    big:SetAlpha(0)
    big:Show()
    print("|cffffd100Watchdog:|r " .. (title or "") .. (sub and (" - " .. sub) or ""))
    if c.sound and slot == 1 then WD:PlayAlertSound("warn") end
    if rest then
        for i, w in ipairs(rest) do
            if i < 4 then WD:BigWarning(w.title, w.sub, w.icon, w.color, i + 1) end
        end
    end
end

---------------------------------------------------------------------------
-- 1) Buffs e venenos acabando
---------------------------------------------------------------------------
local buffSeen = {}      -- nome -> { exp=, icon=, warned=, lastRem= }
local poisonSeen = { main = nil, off = nil }

local function ScanBuffs()
    local c = WD:Cfg().buff
    if not c.on then return end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return end
    local now = GetTime()
    local present = {}
    local namesSet = {}
    for _, n in ipairs(c.names or {}) do namesSet[n:lower()] = true end
    local readable = false
    for i = 1, 40 do
        local name, icon, dur, exp, _, ok = AuraAt("player", i, "HELPFUL")
        if not ok then break end
        readable = true
        if type(name) == "string" and type(dur) == "number" and type(exp) == "number" and exp > 0 then
            local minSec = (c.minDur or 5) * 60
            if dur >= minSec or namesSet[name:lower()] then
                present[name] = true
                local s = buffSeen[name]
                if not s or math.abs((s.exp or 0) - exp) > 2 then
                    s = { exp = exp, icon = icon, warned = false }
                    buffSeen[name] = s
                end
                s.icon = icon
                local rem = exp - now
                s.lastRem = rem
                -- buffs curtos (ex: Slice and Dice) avisam perto do fim, nao assim que sao aplicados
                local thr = c.warnSec or 60
                if dur <= thr * 2 then thr = math.min(8, math.max(4, dur * 0.4)) end
                if rem <= thr and rem > 0 and not s.warned then
                    s.warned = true
                    WD:BigWarning(string.format(L.as_buff_soon, name, math.floor(rem + 0.5)), nil, icon, { 1, 0.6, 0.1 })
                end
            end
        end
    end
    if readable then
        for name, s in pairs(buffSeen) do
            if not present[name] then
                if c.expired and s.lastRem and s.lastRem <= (c.warnSec or 60) + 3 and not s.gone then
                    WD:BigWarning(string.format(L.as_buff_gone, name), nil, s.icon, { 1, 0.25, 0.25 })
                end
                buffSeen[name] = nil
            end
        end
    end
end

local function ScanPoisons()
    local c = WD:Cfg().buff
    if not c.on or not c.poisons or not GetWeaponEnchantInfo then return end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return end
    local ok, hasMain, mainExp, _, _, hasOff, offExp = pcall(GetWeaponEnchantInfo)
    if not ok then return end
    hasMain, hasOff = Clean(hasMain), Clean(hasOff)
    mainExp, offExp = Clean(mainExp), Clean(offExp)
    local function handle(key, has, expMs, label)
        local st = poisonSeen[key]
        if has and type(expMs) == "number" then
            local rem = expMs / 1000
            if not st then st = { warned = false }; poisonSeen[key] = st end
            st.lastRem = rem
            if rem <= (c.warnSec or 60) and not st.warned then
                st.warned = true
                WD:BigWarning(string.format(L.as_buff_soon, label, math.floor(rem + 0.5)), nil, nil, { 0.4, 1, 0.4 })
            end
        else
            if st then
                if c.expired and st.lastRem and st.lastRem <= (c.warnSec or 60) + 3 then
                    WD:BigWarning(string.format(L.as_buff_gone, label), nil, nil, { 1, 0.25, 0.25 })
                end
                poisonSeen[key] = nil
            end
        end
    end
    handle("main", hasMain, mainExp, L.as_poison_main)
    handle("off", hasOff, offExp, L.as_poison_off)
end

---------------------------------------------------------------------------
-- 2) Timer de CC do Rogue sobre o alvo
---------------------------------------------------------------------------
-- Crowd control de todas as classes (Classic). cat: stun | incap | fear | root | silence | other
-- ids = todos os ranks conhecidos (o nome em ingles tambem e usado); fallback = segundos se o tooltip nao der.
local CC_DEFS = {
    -- Rogue
    { key = "cheap", class = "ROGUE",   en = "Cheap Shot",      cat = "stun",    ids = { 1833 },                      fallback = 4 },
    { key = "kidney", class = "ROGUE",  en = "Kidney Shot",     cat = "stun",    ids = { 408, 8643 },                 fallback = 0 },   -- 1 s + 1 s por combo point
    { key = "gouge", class = "ROGUE",   en = "Gouge",           cat = "incap",   ids = { 1776, 1777, 8629, 11285, 11286 }, fallback = 4 },
    { key = "sap", class = "ROGUE",     en = "Sap",             cat = "incap",   ids = { 6770, 2070, 11297 },         fallback = 25 },
    { key = "blind", class = "ROGUE",   en = "Blind",           cat = "fear",    ids = { 2094, 21060 },               fallback = 10 },
    { key = "kick", class = "ROGUE",    en = "Kick",            cat = "silence", ids = { 1766, 1767, 1768, 1769 },    fallback = 5 },
    -- Mage
    { key = "poly", class = "MAGE",    en = "Polymorph",       cat = "incap",   ids = { 118, 12824, 12825, 12826 },  fallback = 20, pvpCap = 10 },
    { key = "fnova", class = "MAGE",   en = "Frost Nova",      cat = "root",    ids = { 122, 865, 6131, 10230 },     fallback = 8 },
    { key = "cspell", class = "MAGE",  en = "Counterspell",    cat = "silence", ids = { 2139 },                      fallback = 4 },
    -- Priest
    { key = "pscream", class = "PRIEST", en = "Psychic Scream",  cat = "fear",    ids = { 8122, 8124, 10888, 10890 },  fallback = 8 },
    { key = "mcontrol", class = "PRIEST",en = "Mind Control",    cat = "other",   ids = { 605, 10911, 10912 },         fallback = 60 },
    { key = "shackle", class = "PRIEST", en = "Shackle Undead",  cat = "other",   ids = { 9484, 9485, 10955 },         fallback = 30 },
    { key = "silence", class = "PRIEST", en = "Silence",         cat = "silence", ids = { 15487 },                     fallback = 5 },
    -- Warlock
    { key = "fear", class = "WARLOCK",    en = "Fear",            cat = "fear",    ids = { 5782, 6213, 6215 },          fallback = 10, pvpCap = 10 },
    { key = "howl", class = "WARLOCK",    en = "Howl of Terror",  cat = "fear",    ids = { 5484, 17928 },               fallback = 10 },
    { key = "dcoil", class = "WARLOCK",   en = "Death Coil",      cat = "other",   ids = { 6789, 17925, 17926 },        fallback = 3 },
    { key = "banish", class = "WARLOCK",  en = "Banish",          cat = "other",   ids = { 710, 18647 },                fallback = 20 },
    { key = "seduce", class = "WARLOCK",  en = "Seduction",       cat = "other",   ids = { 6358 },                      fallback = 15 },
    { key = "slock", class = "WARLOCK",   en = "Spell Lock",      cat = "silence", ids = { 19244, 19647 },              fallback = 3 },
    -- Druid
    { key = "bash", class = "DRUID",    en = "Bash",            cat = "stun",    ids = { 5211, 6798, 8983 },          fallback = 4 },
    { key = "pounce", class = "DRUID",  en = "Pounce",          cat = "stun",    ids = { 9005, 9823, 9827 },          fallback = 3 },
    { key = "roots", class = "DRUID",   en = "Entangling Roots",cat = "root",    ids = { 339, 1062, 5195, 5196, 9852, 9853 }, fallback = 12 },
    { key = "hibern", class = "DRUID",  en = "Hibernate",       cat = "incap",   ids = { 2637, 18657, 18658 },        fallback = 20 },
    { key = "fcharge", class = "DRUID", en = "Feral Charge",    cat = "root",    ids = { 16979 },                     fallback = 4 },
    -- Hunter
    { key = "scatter", class = "HUNTER", en = "Scatter Shot",    cat = "incap",   ids = { 19503 },                     fallback = 4 },
    { key = "wyvern", class = "HUNTER",  en = "Wyvern Sting",    cat = "incap",   ids = { 19386, 24132, 24133 },       fallback = 12 },
    { key = "intim", class = "HUNTER",   en = "Intimidation",    cat = "stun",    ids = { 19577, 24394 },              fallback = 3 },
    { key = "scareb", class = "HUNTER",  en = "Scare Beast",     cat = "fear",    ids = { 1513, 14326, 14327 },        fallback = 10 },
    -- Paladin
    { key = "hoj", class = "PALADIN",     en = "Hammer of Justice", cat = "stun",  ids = { 853, 5588, 5589, 10308 },    fallback = 3 },
    { key = "repent", class = "PALADIN",  en = "Repentance",      cat = "incap",   ids = { 20066 },                     fallback = 6 },
    { key = "turnund", class = "PALADIN", en = "Turn Undead",     cat = "fear",    ids = { 2878, 5627, 10326 },         fallback = 10 },
    -- Warrior
    { key = "ishout", class = "WARRIOR",  en = "Intimidating Shout", cat = "fear", ids = { 5246 },                      fallback = 8 },
    { key = "cblow", class = "WARRIOR",   en = "Concussion Blow", cat = "stun",    ids = { 12809 },                     fallback = 5 },
    { key = "icept", class = "WARRIOR",   en = "Intercept",       cat = "stun",    ids = { 20252, 20616, 20617 },       fallback = 3 },
    { key = "sbash", class = "WARRIOR",   en = "Shield Bash",     cat = "silence", ids = { 72, 1671, 1672 },            fallback = 6 },
    { key = "charge", class = "WARRIOR",  en = "Charge",          cat = "stun",    ids = { 100, 6178, 11578 },          fallback = 1 },
    -- Shaman
    { key = "eshock",  class = "SHAMAN", en = "Earth Shock", cat = "silence", ids = { 8042, 8044, 8045, 8046, 10412, 10413, 10414 }, fallback = 2 },
    -- Racial
    { key = "wstomp", race = "Tauren", en = "War Stomp",       cat = "stun",    ids = { 20549 },                     fallback = 2 },
}
local CC_CATS = { "stun", "incap", "fear", "root", "silence", "other" }
local DR_CATS = { stun = true, incap = true, fear = true, root = true }
local function ClassFile()
    local ok, _, c = pcall(UnitClass, "player")
    return ok and Clean(c) or nil
end
local function RaceFile()
    local ok, _, r = pcall(UnitRace, "player")
    return ok and Clean(r) or nil
end
-- so os CCs da classe (e raca) do jogador
local function Relevant(d)
    if d.class then return d.class == ClassFile() end
    if d.race then return d.race == RaceFile() end
    return true
end
local function MyCCs()
    local out = {}
    for _, d in ipairs(CC_DEFS) do if Relevant(d) then out[#out + 1] = d end end
    return out
end

local ccByName, ccById = {}, {}
local function BuildCCNames()
    wipe(ccByName); wipe(ccById)
    for _, d in ipairs(MyCCs()) do
        d.id = d.ids[1]
        ccByName[d.en] = d
        d.name = d.en
        for _, id in ipairs(d.ids) do
            ccById[id] = d
            local name, icon = SpellInfo(id)
            name = Clean(name)
            if type(name) == "string" then
                ccByName[name] = d
                if not d.icon and icon then d.icon = icon end
                if id == d.ids[1] then d.name = name end
            end
        end
    end
end

local function DebugCC(...)
    if WD.debug then print("|cff66ccff[Watchdog CC]|r", ...) end
end

-- feiticos que so podem estar em UM alvo por vez (por conjurador)
local CC_SINGLE = { sap = true, poly = true, shackle = true, mcontrol = true, banish = true, seduce = true, hibern = true, scareb = true }

local ccFrames = {}
local ccActive = {}
local lastCP, lastCPTime = 0, 0

local function GetCCFrame()
    for _, f in ipairs(ccFrames) do
        if not f.inUse then return f end
    end
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetFrameStrata("HIGH")
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.border = f:CreateTexture(nil, "BACKGROUND")
    f.border:SetPoint("TOPLEFT", -2, 2)
    f.border:SetPoint("BOTTOMRIGHT", 2, -2)
    f.border:SetColorTexture(0, 0, 0, 0.9)
    f.time = f:CreateFontString(nil, "OVERLAY")
    f.time:SetFont(FONT, 24, "THICKOUTLINE")
    f.time:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.label = f:CreateFontString(nil, "OVERLAY")
    f.label:SetFont(FONT, 11, "OUTLINE")
    f.label:SetPoint("BOTTOM", f, "TOP", 0, 2)
    f:Hide()
    ccFrames[#ccFrames + 1] = f
    return f
end

local function FindNameplate(entry)
    if not C_NamePlate or not C_NamePlate.GetNamePlateForUnit then return nil end
    local np = entry.token and C_NamePlate.GetNamePlateForUnit(entry.token)
    if np and entry.guid then
        local g = Clean(entry.token and UnitGUID(entry.token))
        if type(g) == "string" and g ~= entry.guid then np = nil end
    end
    if not np and entry.guid and C_NamePlate.GetNamePlates then
        for _, p in ipairs(C_NamePlate.GetNamePlates()) do
            local tok = Clean(p.namePlateUnitToken or (p.UnitFrame and p.UnitFrame.unit))
            if type(tok) == "string" then
                local g = Clean(UnitGUID(tok))
                if g == entry.guid then entry.token = tok; return p end
            end
        end
    end
    return np
end

-- Retorna dur, exp, status: "ok" (achou e leu), "missing" (leu tudo e nao achou), "unreadable"
local function ReadDebuff(unit, name)
    local unreadable = false
    for i = 1, 40 do
        local n, _, dur, exp, src, ok = AuraAt(unit, i, "HARMFUL")
        if not ok then
            if i == 1 and n == nil and not C_UnitAuras and not UnitAura then return nil, nil, "unreadable" end
            break
        end
        if type(n) ~= "string" then
            unreadable = true
        elseif n == name and (src == nil or src == "player" or src == "pet") then
            if type(dur) == "number" and dur > 0 and type(exp) == "number" then
                return dur, exp, "ok"
            end
            return nil, nil, "unreadable"
        end
    end
    return nil, nil, unreadable and "unreadable" or "missing"
end

local function ReleaseCC(entry)
    if entry.frame then entry.frame.inUse = false; entry.frame:Hide(); entry.frame = nil end
    for i, e in ipairs(ccActive) do
        if e == entry then table.remove(ccActive, i); break end
    end
end

local ccTicker
local function CCUpdate()
    local now = GetTime()
    local size = WD:Cfg().cc.size or 48
    local fallbackIdx = 0
    for i = #ccActive, 1, -1 do
        local e = ccActive[i]
        local rem = e.exp - now
        if rem <= 0 then
            ReleaseCC(e)
        else
            -- esconde cedo (CC quebrou) so se ja confirmamos o debuff antes e ele sumiu varias vezes seguidas
            if e.token and e.defName and now - e.t0 > 0.6 and now >= (e.nextCheck or 0) then
                e.nextCheck = now + 0.25
                local g = Clean(UnitGUID(e.token))
                if e.guid == nil or g == e.guid then
                    local _, exp, status = ReadDebuff(e.token, e.defName)
                    if status == "ok" then
                        e.misses = 0
                        e.confirmed = true
                        if exp and math.abs(exp - e.exp) > 0.4 then e.exp = exp; rem = e.exp - now end
                    elseif status == "missing" and e.confirmed then
                        e.misses = (e.misses or 0) + 1
                        if e.misses >= 6 then ReleaseCC(e); rem = -1 end
                    end
                end
            end
            if rem > 0 then
                local f = e.frame
                if not f then f = GetCCFrame(); f.inUse = true; e.frame = f end
                f:SetSize(size, size)
                f.icon:SetTexture(e.icon)
                f.time:SetFont(FONT, math.max(14, math.floor(size * 0.5)), "THICKOUTLINE")
                f.time:SetText(rem >= 10 and string.format("%d", rem) or string.format("%.1f", rem))
                f.time:SetTextColor(rem < 2 and 1 or 1, rem < 2 and 0.3 or 0.9, rem < 2 and 0.3 or 0.2)
                f.label:SetText(e.label or "")
                local np = FindNameplate(e)
                f:ClearAllPoints()
                if np then
                    f:SetPoint("BOTTOM", np, "TOP", 0, 8)
                    f:Show()
                elseif e.test or not e.token then
                    -- so o botao de teste usa a posicao fixa na tela
                    f:SetPoint("TOP", UIParent, "TOP", (fallbackIdx * (size + 12)) - 0, -300)
                    fallbackIdx = fallbackIdx + 1
                    f:Show()
                else
                    -- alvo real sem nameplate (longe ou fora de vista): esconde; o tempo continua correndo
                    f:Hide()
                end
            end
        end
    end
    if #ccActive == 0 and ccTicker then ccTicker:Cancel(); ccTicker = nil end
end

local function StartCC(def, unit, spellName, dur, test)
    local now = GetTime()
    local icon = def.icon or select(2, SpellInfo(def.id))
    local entry = {
        exp = now + dur, t0 = now, icon = icon, label = spellName, defName = def.name,
        token = unit, test = test,
    }
    if unit then
        local g = Clean(UnitGUID(unit))
        if type(g) == "string" then entry.guid = g end
        local np = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
        if np then
            local tok = Clean(np.namePlateUnitToken or (np.UnitFrame and np.UnitFrame.unit))
            if type(tok) == "string" then entry.token = tok end
        end
    end
    entry.key = def.key
    -- CCs de alvo unico (Sap, Polymorph...): usar em outro alvo remove o anterior,
    -- entao so um pode ficar na tela por feitico
    if def.key and CC_SINGLE[def.key] and not test then
        for i = #ccActive, 1, -1 do
            local e = ccActive[i]
            if e.key == def.key and not e.test then ReleaseCC(e) end
        end
    end
    -- substitui um CC anterior do mesmo alvo/feitico
    for i = #ccActive, 1, -1 do
        local e = ccActive[i]
        if e.guid and e.guid == entry.guid and e.defName == entry.defName then ReleaseCC(e) end
    end
    ccActive[#ccActive + 1] = entry
    if not ccTicker then ccTicker = C_Timer.NewTicker(0.05, CCUpdate) end
    CCUpdate()
    return entry
end

local function ComboPoints()
    local cp = 0
    if GetComboPoints then
        local ok, v = pcall(GetComboPoints, "player", "target")
        if ok and type(v) == "number" and v > cp then cp = v end
        ok, v = pcall(GetComboPoints, "player")
        if ok and type(v) == "number" and v > cp then cp = v end
    end
    if UnitPower then
        local ok, v = pcall(UnitPower, "player", 4)   -- 4 = combo points
        v = Clean(v)
        if ok and type(v) == "number" and v > cp then cp = v end
    end
    return cp
end

local function OnCCSent()
    local cp = ComboPoints()
    -- so guarda se tiver pontos: um SENT posterior de outra magia nao zera o valor do Kidney Shot
    if cp > 0 then lastCP = cp; lastCPTime = GetTime() end
end

-- Duracao lida do tooltip da magia (o spellID do evento ja e o rank que voce conhece).
local function SpellDesc(id)
    local d
    if C_Spell and C_Spell.GetSpellDescription then
        local ok, v = pcall(C_Spell.GetSpellDescription, id)
        if ok then d = Clean(v) end
    end
    if not d and GetSpellDescription then
        local ok, v = pcall(GetSpellDescription, id)
        if ok then d = Clean(v) end
    end
    return type(d) == "string" and d or nil
end

local function DescDuration(def, spellID, cp)
    local d = SpellDesc(spellID)
    if not d then return nil end
    if def.key == "kidney" then
        -- "1 point : 2 seconds 2 points: 3 seconds ..."
        for pts, secs in d:gmatch("(%d+)%s*points?%s*:?%s*(%d+%.?%d*)%s*sec") do
            if tonumber(pts) == cp then return tonumber(secs) end
        end
        return nil
    end
    local secs = d:match("(%d+%.?%d*)%s*sec")
    return secs and tonumber(secs) or nil
end

-- Diminishing returns (so em stuns): 100% -> 50% -> 25% -> imune; reseta ~18 s apos o fim.
local DR_MULT = { 1, 0.5, 0.25 }
local drState = {}
local function ApplyDR(key, dur)
    local now = GetTime()
    for k, st in pairs(drState) do if now > st.resetAt + 30 then drState[k] = nil end end
    local st = drState[key]
    if not st or now > st.resetAt then st = { count = 0 } end
    local mult = DR_MULT[st.count + 1] or 0
    st.count = st.count + 1
    st.resetAt = now + dur * mult + 18
    drState[key] = st
    return mult, st
end

local function OnCCCast(...)
    local c = WD:Cfg().cc
    -- o spellID e o 3o argumento (unit, castGUID, spellID); aceita variacoes
    local spellID
    for i = 1, select("#", ...) do
        local v = Clean((select(i, ...)))
        if type(v) == "number" then spellID = v end
    end
    if not spellID then DebugCC("cast sem spellID") return end
    local name, icon = SpellInfo(spellID)
    name = Clean(name)
    DebugCC("cast", tostring(name), spellID)
    if not c.on then return end
    local def = ccById[spellID] or (type(name) == "string" and ccByName[name]) or nil
    if not def then return end
    name = name or def.en
    if c.spells[def.key] == false or (c.cats and c.cats[def.cat] == false) then return end
    if not UnitExists("target") then DebugCC("sem alvo") return end
    local cp = 0
    if def.key == "kidney" then
        cp = ComboPoints()
        if cp == 0 and GetTime() - lastCPTime < 1.5 then cp = lastCP end
        if cp == 0 then cp = 3; DebugCC("pontos de combo desconhecidos, assumindo 3") end
    end
    local base = DescDuration(def, spellID, cp)
    local fallback = base or def.fallback
    if not base and def.key == "kidney" then fallback = 1 + cp end
    DebugCC("duracao base", def.en, fallback, base and "(tooltip)" or "(padrao)", "cp=" .. cp)
    local mult, drKey = 1, nil
    local isPlayer = Clean(UnitIsPlayer("target")) == true
    if isPlayer and def.pvpCap and fallback > def.pvpCap then fallback = def.pvpCap end
    if c.dr and DR_CATS[def.cat] and isPlayer then
        drKey = Clean(UnitGUID("target"))
        if type(drKey) ~= "string" then drKey = Clean(UnitName("target")) end
        if type(drKey) ~= "string" then drKey = "target" end
        local st
        drKey = drKey .. ":" .. def.cat
        mult, st = ApplyDR(drKey, fallback)
        DebugCC("DR", drKey, "x" .. mult, "stun #" .. st.count)
        if mult == 0 then
            WD:BigWarning(L.as_cc_immune, name, nil, { 1, 0.4, 0.4 })
            return
        end
        fallback = fallback * mult
    end
    def.icon = def.icon or icon
    DebugCC("mostrando", def.en, fallback)
    local entry = StartCC(def, "target", mult < 1 and string.format("%s (%d%%)", name, math.floor(mult * 100 + 0.5)) or name, fallback, false)
    entry.defName = name
    -- refina com o tempo real do debuff assim que ele aparecer
    local function refine()
        if not entry.token then return end
        local dur, exp, status = ReadDebuff(entry.token, name)
        DebugCC("debuff", name, status, exp and (exp - GetTime()) or "-")
        if status == "ok" and exp then
            entry.exp = exp; entry.confirmed = true
            if drKey and drState[drKey] then drState[drKey].resetAt = exp + 18 end
        end
    end
    C_Timer.After(0.15, refine)
    C_Timer.After(0.5, refine)
    C_Timer.After(1.2, refine)
end

function WD:TestCC()
    BuildCCNames()
    local mine = MyCCs()
    if #mine == 0 then return end
    local d1, d2 = mine[1], mine[2] or mine[1]
    StartCC(d1, nil, d1.name or d1.en, 6, true)
    if UnitExists("target") then
        StartCC(d2, "target", d2.name or d2.en, 5, false)
    end
end

---------------------------------------------------------------------------
-- 2b) Debuffs / DoTs seus no alvo (fileira de icones pequenos embaixo da plaquinha)
---------------------------------------------------------------------------
-- en = nome do debuff (ingles); dur = duracao aproximada, so usada se o jogo nao deixar ler a aura
local DOT_DEFS = {
    ROGUE   = { { key = "rupture", en = "Rupture", dur = 16 }, { key = "garrote", en = "Garrote", dur = 18 },
                { key = "expose", en = "Expose Armor", dur = 30 }, { key = "hemo", en = "Hemorrhage", dur = 15 },
                { key = "dpoison", en = "Deadly Poison", dur = 12 } },
    WARLOCK = { { key = "corruption", en = "Corruption", dur = 18 }, { key = "agony", en = "Curse of Agony", dur = 24 },
                { key = "immolate", en = "Immolate", dur = 15 }, { key = "siphon", en = "Siphon Life", dur = 30 },
                { key = "cweak", en = "Curse of Weakness", dur = 120 }, { key = "creck", en = "Curse of Recklessness", dur = 120 },
                { key = "celem", en = "Curse of the Elements", dur = 300 }, { key = "ctongues", en = "Curse of Tongues", dur = 30 },
                { key = "cdoom", en = "Curse of Doom", dur = 60 } },
    PRIEST  = { { key = "swp", en = "Shadow Word: Pain", dur = 18 }, { key = "plague", en = "Devouring Plague", dur = 24 },
                { key = "vampemb", en = "Vampiric Embrace", dur = 60 }, { key = "holyfire", en = "Holy Fire", dur = 10 } },
    MAGE    = { { key = "fireball", en = "Fireball", dur = 8 }, { key = "pyro", en = "Pyroblast", dur = 12 } },
    DRUID   = { { key = "moonfire", en = "Moonfire", dur = 12 }, { key = "rake", en = "Rake", dur = 9 },
                { key = "rip", en = "Rip", dur = 12 }, { key = "ff", en = "Faerie Fire", dur = 40 },
                { key = "demroar", en = "Demoralizing Roar", dur = 30 } },
    WARRIOR = { { key = "rend", en = "Rend", dur = 21 }, { key = "sunder", en = "Sunder Armor", dur = 30 },
                { key = "demshout", en = "Demoralizing Shout", dur = 30 }, { key = "tclap", en = "Thunder Clap", dur = 10 },
                { key = "hamstring", en = "Hamstring", dur = 15 }, { key = "deepw", en = "Deep Wounds", dur = 12 } },
    HUNTER  = { { key = "serpent", en = "Serpent Sting", dur = 15 }, { key = "hmark", en = "Hunter's Mark", dur = 120 },
                { key = "wingclip", en = "Wing Clip", dur = 10 }, { key = "viper", en = "Viper Sting", dur = 8 },
                { key = "scorpid", en = "Scorpid Sting", dur = 20 } },
    PALADIN = { { key = "jol", en = "Judgement of Light", dur = 10 }, { key = "jow", en = "Judgement of Wisdom", dur = 10 },
                { key = "joj", en = "Judgement of Justice", dur = 10 } },
    SHAMAN  = { { key = "flameshock", en = "Flame Shock", dur = 12 } },
}

local function MyDots() return DOT_DEFS[ClassFileEarly() or ""] or {} end

local dotFrames = {}
local dotRow
local dotEst = {}          -- guid -> { key -> exp } (estimativa por cast, so se a aura nao for legivel)
local dotTest

local function GetDotRow()
    if dotRow then return dotRow end
    dotRow = CreateFrame("Frame", nil, UIParent)
    dotRow:SetFrameStrata("HIGH")
    dotRow:SetSize(10, 10)
    dotRow:Hide()
    return dotRow
end

local function GetDotFrame(i)
    local f = dotFrames[i]
    if f then return f end
    f = CreateFrame("Frame", nil, GetDotRow())
    f.border = f:CreateTexture(nil, "BACKGROUND")
    f.border:SetTexture("Interface\\Buttons\\WHITE8X8")
    f.border:SetPoint("TOPLEFT", -2, 2)
    f.border:SetPoint("BOTTOMRIGHT", 2, -2)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.time = f:CreateFontString(nil, "OVERLAY")
    f.time:SetFont(FONT, 12, "THICKOUTLINE")
    f.time:SetPoint("BOTTOM", f, "BOTTOM", 0, -2)
    dotFrames[i] = f
    return f
end

local function DotMatches(auraName, en)
    return type(auraName) == "string" and auraName:sub(1, #en) == en
end

local function DotNameplate()
    if C_NamePlate and C_NamePlate.GetNamePlateForUnit then
        local ok, np = pcall(C_NamePlate.GetNamePlateForUnit, "target")
        if ok then return np end
    end
end

local function DotsUpdate()
    local c = WD:Cfg().dots
    local row = GetDotRow()
    local list = {}
    local now = GetTime()
    if c.on then
        local defs = MyDots()
        if dotTest and now < dotTest then
            for i = 1, math.min(3, #defs) do
                local d = defs[i]
                local ic = select(2, SpellInfo(d.en)) or "Interface\\Icons\\INV_Misc_QuestionMark"
                list[#list + 1] = { icon = ic, rem = (dotTest - now) + (i - 1) * 4 }
            end
        elseif UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target") and #defs > 0 then
            local g = Clean(UnitGUID("target"))
            local found, unreadable = {}, false
            for i = 1, 40 do
                local n, icon, dur, exp, src, ok = AuraAt("target", i, "HARMFUL")
                if not ok then break end
                if type(n) ~= "string" then
                    unreadable = true
                elseif src == "player" and type(exp) == "number" and exp > 0 then
                    for _, d in ipairs(defs) do
                        if c.spells[d.key] ~= false and not found[d.key] and DotMatches(n, d.en) then
                            found[d.key] = true
                            list[#list + 1] = { icon = icon, rem = exp - now, order = _ }
                        end
                    end
                end
            end
            if unreadable and type(g) == "string" and dotEst[g] then
                for i, d in ipairs(defs) do
                    local e = dotEst[g][d.key]
                    if e and c.spells[d.key] ~= false and not found[d.key] and e.exp > now then
                        list[#list + 1] = { icon = e.icon, rem = e.exp - now, order = i }
                    end
                end
            end
            table.sort(list, function(a, b) return (a.order or 0) < (b.order or 0) end)
        end
    end
    local n = #list
    WD.dotsShown = n
    if n == 0 then
        row:Hide()
        for _, f in ipairs(dotFrames) do f:Hide() end
        return
    end
    local size = c.size or 28
    local gap = 6
    local total = n * size + (n - 1) * gap
    row:SetSize(total, size)
    row:ClearAllPoints()
    local np = DotNameplate()
    if np then
        row:SetPoint("TOP", np, "BOTTOM", 0, -6)
    else
        row:SetPoint("TOP", UIParent, "TOP", 0, -370)
    end
    row:Show()
    for i = 1, n do
        local f = GetDotFrame(i)
        local e = list[i]
        f:SetSize(size, size)
        f:ClearAllPoints()
        f:SetPoint("LEFT", row, "LEFT", (i - 1) * (size + gap), 0)
        f.icon:SetTexture(e.icon)
        f.time:SetFont(FONT, math.max(10, math.floor(size * 0.42)), "THICKOUTLINE")
        local rem = e.rem
        f.time:SetText(rem >= 60 and string.format("%dm", math.floor(rem / 60 + 0.5)) or (rem >= 10 and string.format("%d", rem) or string.format("%.1f", rem)))
        if rem <= (c.warn or 3) then
            f.time:SetTextColor(1, 0.3, 0.3)
            f.border:SetVertexColor(1, 0.25, 0.25)
        else
            f.time:SetTextColor(1, 0.9, 0.3)
            f.border:SetVertexColor(0.07, 0.08, 0.1)
        end
        f:Show()
    end
    for i = n + 1, #dotFrames do dotFrames[i]:Hide() end
end

-- estimativa por cast (so e usada se o jogo esconder as auras do alvo)
local function OnDotCast(_, spellID)
    if not UnitExists("target") then return end
    local name, icon = SpellInfo(spellID)
    if type(name) ~= "string" then return end
    for _, d in ipairs(MyDots()) do
        if DotMatches(name, d.en) then
            local g = Clean(UnitGUID("target"))
            if type(g) == "string" then
                dotEst[g] = dotEst[g] or {}
                dotEst[g][d.key] = { exp = GetTime() + d.dur, icon = icon }
            end
            return
        end
    end
end

function WD:TestDots()
    dotTest = GetTime() + 12
    DotsUpdate()
end

C_Timer.NewTicker(0.2, function()
    if not WatchdogDB then return end
    SafeRun("dots", DotsUpdate)
end)

---------------------------------------------------------------------------
-- 3/4/5) Reparo, comida e consumiveis (locais aprendidos + cidades)
---------------------------------------------------------------------------
local CITY_MAPS = { [1453] = true, [1455] = true, [1457] = true, [1454] = true, [1456] = true, [1458] = true }

local function SpotKey()
    local mapID = 0
    if C_Map and C_Map.GetBestMapForUnit then
        local ok, m = pcall(C_Map.GetBestMapForUnit, "player")
        if ok and type(m) == "number" then mapID = m end
    end
    local sub = Clean(GetSubZoneText and GetSubZoneText()) or ""
    if type(sub) ~= "string" then sub = "" end
    local zone = Clean(GetRealZoneText and GetRealZoneText()) or ""
    if type(zone) ~= "string" then zone = "" end
    return mapID .. ":" .. sub, mapID, (sub ~= "" and sub or zone)
end

local function CountSpots()
    local n = 0
    for _ in pairs(WD:Cfg().spots) do n = n + 1 end
    return n
end

local function LearnSpot(kind)
    local key, _, label = SpotKey()
    local spots = WD:Cfg().spots
    local s = spots[key] or { name = label }
    s[kind] = true
    s.name = label
    spots[key] = s
end

local function SpotInfo()
    local key, mapID, label = SpotKey()
    local s = WD:Cfg().spots[key]
    local city = CITY_MAPS[mapID]
    return {
        key = key, name = label,
        repair = city or (s and s.repair),
        food = city or (s and s.food),
        craft = city or (s and s.craft),
    }
end

local function Lowest()
    local worst, any = 101, false
    for slot = 1, 18 do
        if slot ~= 4 then
            local ok, cur, max = pcall(GetInventoryItemDurability, slot)
            cur, max = Clean(cur), Clean(max)
            if ok and type(cur) == "number" and type(max) == "number" and max > 0 then
                any = true
                local pct = math.floor(cur / max * 100)
                if pct < worst then worst = pct end
            end
        end
    end
    return any and worst or nil
end

local GetNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local function BagItem(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then return info.itemID, info.hyperlink, info.stackCount or 1 end
        return nil
    end
    if GetContainerItemInfo then
        local _, count, _, _, _, _, link, _, _, itemID = GetContainerItemInfo(bag, slot)
        if itemID then return itemID, link, count or 1 end
    end
end

local function ForEachBagItem(fn)
    if not GetNumSlots then return end
    for bag = 0, 4 do
        local n = GetNumSlots(bag) or 0
        for slot = 1, n do
            local itemID, link, count = BagItem(bag, slot)
            if itemID then fn(itemID, link, count) end
        end
    end
end

local function IsFoodItem(itemID)
    local classID, subID
    if C_Item and C_Item.GetItemInfoInstant then
        local _, _, _, _, _, c, s = C_Item.GetItemInfoInstant(itemID)
        classID, subID = c, s
    elseif GetItemInfoInstant then
        local _, _, _, _, _, c, s = GetItemInfoInstant(itemID)
        classID, subID = c, s
    end
    return classID == 0 and subID == 5
end

local function CountFood()
    local total = 0
    ForEachBagItem(function(itemID, _, count)
        if IsFoodItem(itemID) then total = total + count end
    end)
    return total
end

local function ItemName(itemID, link)
    -- 1) cache salvo (nomes ja vistos em outras sessoes: nao depende do jogo ja ter carregado o item)
    local cached = WatchdogDB and WatchdogDB.items and WatchdogDB.items[itemID]
    if cached and cached.n then return cached.n end
    -- 2) API do jogo
    local name
    if C_Item and C_Item.GetItemNameByID then name = C_Item.GetItemNameByID(itemID) end
    if not name and GetItemInfo then name = GetItemInfo(link or itemID) end
    if name and WD.CacheItem then pcall(WD.CacheItem, WD, itemID, name) end
    return name
end

-- Listas iniciais de consumiveis por classe (minLevel = so avisa a partir desse nivel; kind="ammo" = qualquer municao)
local CONS_PRESETS = {
    ROGUE   = { { name = "Deadly Poison", min = 10 }, { name = "Instant Poison", min = 10 },
                { name = "Flash Powder", min = 5, minLevel = 22 }, { name = "Blinding Powder", min = 5, minLevel = 34 } },
    HUNTER  = { { name = "@ammo", kind = "ammo", min = 200 } },
    MAGE    = { { name = "Rune of Teleportation", min = 3, minLevel = 20 }, { name = "Rune of Portals", min = 3, minLevel = 40 },
                { name = "Arcane Powder", min = 10, minLevel = 56 } },
    PRIEST  = { { name = "Holy Candle", min = 5, minLevel = 48 }, { name = "Sacred Candle", min = 5, minLevel = 56 } },
    WARLOCK = { { name = "Soul Shard", min = 5, minLevel = 10 } },
    SHAMAN  = { { name = "Ankh", min = 2, minLevel = 30 } },
    PALADIN = { { name = "Symbol of Kings", min = 20, minLevel = 52 }, { name = "Symbol of Divinity", min = 2, minLevel = 30 } },
    DRUID   = { { name = "Maple Seed", min = 2, minLevel = 20 }, { name = "Stranglethorn Seed", min = 2, minLevel = 30 },
                { name = "Ashwood Seed", min = 2, minLevel = 40 }, { name = "Hornbeam Seed", min = 2, minLevel = 50 },
                { name = "Ironwood Seed", min = 2, minLevel = 60 }, { name = "Wild Thornroot", min = 5, minLevel = 50 } },
}

local function ItemLabel(it)
    local n = it.name
    if n == "@ammo" then n = L.cfg_ammo end
    return n
end

-- Lista de consumiveis da classe atual (criada com o preset na primeira vez).
function WD:ConsItems()
    local c = WD:Cfg().cons
    c.byClass = c.byClass or {}
    local cls = ClassFileEarly() or "ANY"
    local list = c.byClass[cls]
    if not list then
        list = {}
        c.byClass[cls] = list
        local function add(it)
            for _, e in ipairs(list) do if e.name:lower() == it.name:lower() then return end end
            local copy = {}
            for k, v in pairs(it) do copy[k] = v end
            list[#list + 1] = copy
        end
        if c.legacy and not c.legacyUsed then
            for _, it in ipairs(c.legacy) do add(it) end
            c.legacyUsed = true
        end
        if c.items and #c.items > 0 and not c.itemsMigrated then   -- lista da versao anterior (conta inteira)
            for _, it in ipairs(c.items) do add(it) end
            c.itemsMigrated = true
        end
        for _, it in ipairs(CONS_PRESETS[cls] or {}) do add(it) end
    end
    return list
end

-- Conta cada item da lista: por itemID quando conhecido, senao pelo nome.
local function IsAmmo(itemID)
    local classID
    if C_Item and C_Item.GetItemInfoInstant then classID = select(6, C_Item.GetItemInfoInstant(itemID))
    elseif GetItemInfoInstant then classID = select(6, GetItemInfoInstant(itemID)) end
    return classID == 6
end

local function CountConsumables(items)
    local counts = {}
    local pending = false
    local lvl = UnitLevel and UnitLevel("player") or 80
    local needName = false
    for i = 1, #items do
        counts[i] = 0
        if items[i].kind ~= "ammo" and not items[i].id then needName = true end
    end
    ForEachBagItem(function(itemID, link, count)
        local nm
        local ammo
        for i, want in ipairs(items) do
            if want.kind == "ammo" then
                if ammo == nil then ammo = IsAmmo(itemID) end
                if ammo then counts[i] = counts[i] + count end
            elseif want.id then
                if want.id == itemID then counts[i] = counts[i] + count end
            else
                nm = nm or ItemName(itemID, link)
                if not nm then
                    -- o jogo ainda nao carregou o nome deste item: nao da pra contar certo agora
                    pending = true
                    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, itemID) end
                elseif nm:lower():find(want.name:lower(), 1, true) then counts[i] = counts[i] + count end
            end
        end
    end)
    return counts, lvl, (pending and needName)
end

local spotCooldown = {}
local function Cooldown(kind, key)
    local k = kind .. "|" .. key
    local now = GetTime()
    if spotCooldown[k] and now - spotCooldown[k] < 600 then return false end
    spotCooldown[k] = now
    return true
end

local function CheckSpot(tries)
    tries = tonumber(tries) or 0
    local c = WD:Cfg()
    local sp = SpotInfo()
    local place = (sp.name and sp.name ~= "") and sp.name or L.as_place_unknown
    if c.repair.on and sp.repair then
        local low = Lowest()
        if low and low <= c.repair.pct and Cooldown("repair", sp.key) then
            WD:BigWarning(L.as_repair_title, string.format(L.as_repair_body, place, low, c.repair.pct),
                "Interface\\Icons\\Trade_BlackSmithing", { 1, 0.5, 0.2 })
        end
    end
    if c.food.on and sp.food then
        local n = CountFood()
        if n <= c.food.count and Cooldown("food", sp.key) then
            WD:BigWarning(L.as_food_title, string.format(L.as_food_body, place, n, c.food.count),
                "Interface\\Icons\\INV_Misc_Food_15", { 0.5, 0.9, 0.3 })
        end
    end
    local items = WD:ConsItems()
    if c.cons.on and (sp.craft or sp.food or sp.repair) and #items > 0 then
        local counts, lvl, pending = CountConsumables(items)
        -- Itens ainda sem nome carregado (logo apos logar): espera e conta de novo, em vez de avisar errado.
        if pending then
            if tries < 4 then C_Timer.After(2.5, function() CheckSpot(tries + 1) end) end
            return
        end
        local cards = {}
        for i, it in ipairs(items) do
            if (not it.minLevel or lvl >= it.minLevel) and counts[i] < math.max(1, it.min or 0) then
                local ic
                if it.id and it.id ~= "@ammo" then
                    local ok, v
                    if C_Item and C_Item.GetItemIconByID then ok, v = pcall(C_Item.GetItemIconByID, it.id) end
                    if not (ok and v) and GetItemIcon then ok, v = pcall(GetItemIcon, it.id) end
                    if ok and v then ic = v end
                end
                cards[#cards + 1] = {
                    title = L.as_cons_title,
                    sub = string.format(L.as_cons_body, place, string.format("%s %d/%d", ItemLabel(it), counts[i], it.min or 0)),
                    icon = ic,   -- sem icone: o aviso usa o emblema do Watchdog
                    color = { 0.6, 0.5, 1 },
                }
            end
        end
        if #cards > 0 and Cooldown("cons", sp.key) then
            local first = table.remove(cards, 1)
            WD:BigWarning(first.title, first.sub, first.icon, first.color, 1, #cards > 0 and cards or nil)
        end
    end
end

-- /wd consumiveis: mostra a contagem atual de cada item vigiado (pra conferir os avisos).
function WD:PrintConsumables()
    local items = WD:ConsItems()
    local counts, lvl, pending = CountConsumables(items)
    print("|cffffd100Watchdog:|r " .. L.as_cons_title)
    for i, it in ipairs(items) do
        local note = (it.minLevel and lvl < it.minLevel) and (" (lvl " .. it.minLevel .. ")") or ""
        print(string.format("  %s: %d / %d%s", ItemLabel(it), counts[i], it.min or 0, note))
    end
    if pending then print("  ...") end
end

local lastSpot
local function OnZone()
    local key = SpotKey()
    if key == lastSpot then return end
    lastSpot = key
    C_Timer.After(1.5, CheckSpot)
end

local function OnMerchant()
    if CanMerchantRepair and CanMerchantRepair() then LearnSpot("repair") end
    local num = GetMerchantNumItems and GetMerchantNumItems() or 0
    local foodSeen = false
    for i = 1, num do
        local link = GetMerchantItemLink and GetMerchantItemLink(i)
        if link then
            local id = tonumber(tostring(link):match("item:(%d+)"))
            if id then
                local classID
                if C_Item and C_Item.GetItemInfoInstant then classID = select(6, C_Item.GetItemInfoInstant(id))
                elseif GetItemInfoInstant then classID = select(6, GetItemInfoInstant(id)) end
                if classID == 0 then
                    local nm = tostring(link):match("%[(.-)%]")
                    if nm then WD:LearnItem(nm, id) end
                end
                if not foodSeen and IsFoodItem(id) then LearnSpot("food"); foodSeen = true end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Lista de consumiveis: Ctrl+Alt+clique em um item das bolsas
---------------------------------------------------------------------------
function WD:AddConsumableEntry(name, id)
    local c = WD:Cfg().cons
    local items = WD:ConsItems()
    if type(name) ~= "string" or name == "" then return false end
    for _, it in ipairs(items) do
        if (id and it.id == id) or it.name:lower() == name:lower() then
            print("|cffffd100Watchdog:|r " .. string.format(L.cfg_cons_exists, it.name, it.min or 0))
            return false
        end
    end
    items[#items + 1] = { id = id, name = name, min = c.min or 10 }
    print("|cffffd100Watchdog:|r " .. string.format(L.cfg_cons_added, name, c.min or 10))
    if WD.RefreshConfig then WD:RefreshConfig() end
    return true
end

function WD:AddConsumable(link, nameOnly)
    local id, name
    if link and not nameOnly then
        id = tonumber(tostring(link):match("item:(%d+)"))
        name = tostring(link):match("%[(.-)%]") or (id and ItemName(id, link))
        if id and name then WD:LearnItem(name, id) end
    else
        name = link
        -- se o nome bate com um item conhecido, usa o itemID dele
        local known = WD:Cfg().known
        local low = tostring(name):lower()
        for n, kid in pairs(known) do
            if n:lower() == low then name, id = n, (kid ~= 0 and kid or nil); break end
        end
    end
    return WD:AddConsumableEntry(name, id)
end

-- Base de nomes conhecidos + o que o addon aprende (bolsas, vendedores, receitas).
local SEED = {
    "Instant Poison","Deadly Poison","Crippling Poison","Mind-numbing Poison","Wound Poison","Flash Powder","Blinding Powder","Thistle Tea",
    "Minor Healing Potion","Lesser Healing Potion","Healing Potion","Greater Healing Potion","Superior Healing Potion","Major Healing Potion",
    "Minor Mana Potion","Lesser Mana Potion","Mana Potion","Greater Mana Potion","Superior Mana Potion","Major Mana Potion",
    "Minor Rejuvenation Potion","Major Rejuvenation Potion","Swiftness Potion","Free Action Potion","Limited Invulnerability Potion",
    "Rage Potion","Great Rage Potion","Mighty Rage Potion","Lesser Invisibility Potion","Invisibility Potion","Fire Protection Potion","Nature Protection Potion",
    "Elixir of the Mongoose","Elixir of Agility","Elixir of Greater Agility","Elixir of Lesser Agility","Elixir of Minor Agility","Elixir of Giants",
    "Elixir of Brute Force","Elixir of Fortitude","Elixir of Ogre's Strength","Elixir of Giant Growth","Elixir of Defense","Elixir of Greater Defense","Elixir of Superior Defense",
    "Elixir of Firepower","Elixir of Shadow Power","Elixir of Frost Power","Elixir of Wisdom","Elixir of the Sages","Elixir of Detect Lesser Invisibility","Elixir of Water Breathing",
    "Winterfall Firewater","Juju Power","Juju Might","Ground Scorpok Assay","R.O.I.D.S.","Spirit of Zanza","Swiftness of Zanza","Sheen of Zanza",
    "Linen Bandage","Heavy Linen Bandage","Wool Bandage","Heavy Wool Bandage","Silk Bandage","Heavy Silk Bandage","Mageweave Bandage","Heavy Mageweave Bandage","Runecloth Bandage","Heavy Runecloth Bandage",
    "Rough Sharpening Stone","Coarse Sharpening Stone","Heavy Sharpening Stone","Solid Sharpening Stone","Dense Sharpening Stone","Elemental Sharpening Stone",
    "Rough Weightstone","Coarse Weightstone","Heavy Weightstone","Solid Weightstone","Dense Weightstone",
    "Tough Jerky","Haunch of Meat","Mutton Chop","Spiced Wolf Meat","Smoked Bear Meat","Cooked Crab Claw","Soothing Turtle Bisque","Spider Sausage","Grilled Squid","Baked Salmon",
    "Lean Wolf Steak","Tasty Lion Steak","Roasted Quail","Hot Wolf Ribs","Conjured Water","Conjured Muffin","Refreshing Spring Water","Ice Cold Milk","Morning Glory Dew","Moonberry Juice","Sweet Nectar","Melon Juice",
}

function WD:LearnItem(name, id)
    if type(name) ~= "string" or name == "" then return end
    local known = WD:Cfg().known
    if known[name] == nil or (known[name] == 0 and id) then
        local n = 0
        for _ in pairs(known) do n = n + 1 end
        if n < 800 then known[name] = id or 0 end
    end
end

local function LearnFromBags()
    ForEachBagItem(function(itemID, link)
        local classID
        if C_Item and C_Item.GetItemInfoInstant then classID = select(6, C_Item.GetItemInfoInstant(itemID))
        elseif GetItemInfoInstant then classID = select(6, GetItemInfoInstant(itemID)) end
        if classID == 0 then
            local nm = ItemName(itemID, link)
            if nm then WD:LearnItem(nm, itemID) end
        end
    end)
end

-- Sugestoes para o autopreenchimento: comeca com o texto primeiro, depois contem.
function WD:SuggestItems(text, limit)
    text = strtrim(text or ""):lower()
    local out = {}
    if text == "" then return out end
    local seen, starts, contains = {}, {}, {}
    local function consider(name, id)
        if seen[name:lower()] then return end
        local low = name:lower()
        local pos = low:find(text, 1, true)
        if pos then
            seen[low] = true
            local e = { name = name, id = (id and id ~= 0) and id or nil }
            if pos == 1 then starts[#starts + 1] = e else contains[#contains + 1] = e end
        end
    end
    for name, id in pairs(WD:Cfg().known) do consider(name, id) end
    for _, name in ipairs(SEED) do consider(name, nil) end
    local function byName(a, b) return a.name < b.name end
    table.sort(starts, byName); table.sort(contains, byName)
    for _, e in ipairs(starts) do if #out < (limit or 6) then out[#out + 1] = e end end
    for _, e in ipairs(contains) do if #out < (limit or 6) then out[#out + 1] = e end end
    return out
end

local lastAddT, lastAddLink = 0, nil
local function OnItemClick(link)
    if not (IsControlKeyDown and IsControlKeyDown() and IsAltKeyDown and IsAltKeyDown()) then return end
    if type(link) ~= "string" then return end
    local now = GetTime()
    if link == lastAddLink and now - lastAddT < 0.4 then return end
    lastAddLink, lastAddT = link, now
    pcall(WD.AddConsumable, WD, link)
end

if hooksecurefunc then
    if _G.HandleModifiedItemClick then
        pcall(hooksecurefunc, "HandleModifiedItemClick", OnItemClick)
    end
    if _G.ContainerFrameItemButton_OnModifiedClick then
        pcall(hooksecurefunc, "ContainerFrameItemButton_OnModifiedClick", function(self)
            local ok, link = pcall(function()
                local bag, slot = self:GetParent():GetID(), self:GetID()
                if C_Container and C_Container.GetContainerItemLink then return C_Container.GetContainerItemLink(bag, slot) end
                return GetContainerItemLink and GetContainerItemLink(bag, slot)
            end)
            if ok then OnItemClick(link) end
        end)
    end
end

---------------------------------------------------------------------------
-- Eventos
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
local function Reg(e) pcall(ev.RegisterEvent, ev, e) end
local function RegUnit(e, ...) pcall(ev.RegisterUnitEvent, ev, e, ...) end

ev:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        BuildCCNames()
        WD:Cfg()
        OnZone()
        pcall(LearnFromBags)
    elseif event == "UNIT_SPELLCAST_SENT" then
        OnCCSent()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit = ...
        if unit == "player" or unit == "pet" then pcall(OnCCCast, select(2, ...)) end
        if unit == "player" then pcall(OnDotCast, select(2, ...)) end
    elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" or event == "ZONE_CHANGED_INDOORS" then
        OnZone()
    elseif event == "BAG_UPDATE_DELAYED" then
        pcall(LearnFromBags)
    elseif event == "MERCHANT_SHOW" then
        pcall(OnMerchant)
    elseif event == "AUCTION_HOUSE_SHOW" or event == "TRADE_SKILL_SHOW" or event == "CRAFT_SHOW" then
        pcall(LearnSpot, "craft")
    end
end)

Reg("PLAYER_LOGIN")
Reg("PLAYER_ENTERING_WORLD")
Reg("ZONE_CHANGED")
Reg("ZONE_CHANGED_NEW_AREA")
Reg("ZONE_CHANGED_INDOORS")
Reg("MERCHANT_SHOW")
Reg("BAG_UPDATE_DELAYED")
Reg("AUCTION_HOUSE_SHOW")
Reg("TRADE_SKILL_SHOW")
Reg("CRAFT_SHOW")
RegUnit("UNIT_SPELLCAST_SENT", "player", "pet")
RegUnit("UNIT_SPELLCAST_SUCCEEDED", "player", "pet")

C_Timer.NewTicker(1, function()
    if not WatchdogDB then return end
    SafeRun("buffs", ScanBuffs)
    SafeRun("poisons", ScanPoisons)
end)

---------------------------------------------------------------------------
-- 6) Menu de configuracao (mesmo visual da janela principal do Watchdog)
---------------------------------------------------------------------------
local cf

local PAGES = {
    { key = "general", labelK = "cfg_page_general", subK = "sub_general" },
    { key = "buffs",   labelK = "cfg_page_buffs", subK = "sub_buffs" },
    { key = "cc",      labelK = "cfg_page_cc", subK = "sub_cc" },
    { key = "dots",    labelK = "cfg_page_dots", subK = "sub_dots" },
    { key = "repair",  labelK = "cfg_page_repair", subK = "sub_repair" },
    { key = "food",    labelK = "cfg_page_food", subK = "sub_food" },
    { key = "cons",    labelK = "cfg_page_cons", subK = "sub_cons" },
    { key = "alerts",  labelK = "cfg_page_alerts", subK = "sub_alerts" },
}

local function BuildConfig(host, left)
    local K = WD.UIKit
    if not K or not host then return nil end
    local C, Flat, FS, MakeChip, BT2, MEDIA = K.C, K.Flat, K.FS, K.MakeChip, K.BT, K.MEDIA
    local SIDE_W, PAD = K.SIDE_W or 170, K.PAD or 20
    local CONTENT_W = 740 - SIDE_W - PAD * 2

    -- Painel embutido na janela principal (aba ALERTAS)
    local f = CreateFrame("Frame", nil, host)
    f:SetAllPoints(host)
    f:Hide()
    f.refreshers = {}
    f.tabs = {}
    f.pages = {}

    local area = CreateFrame("Frame", nil, f)
    area:SetPoint("TOPLEFT", host, "TOPLEFT", left, -112)
    area:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -PAD, PAD)

    ---------------------------------------------------------------- widgets
    local function NewPage(key)
        local p = CreateFrame("Frame", nil, area)
        p:SetAllPoints(area)
        p:Hide()
        p.y, p.n = 0, 0
        f.pages[key] = p
        return p
    end

    local function Row(page, h)
        local r = CreateFrame("Frame", nil, page)
        r:SetHeight(h)
        r:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -page.y)
        r:SetPoint("RIGHT", page, "RIGHT", 0, 0)
        local bg = r:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        page.n = page.n + 1
        bg:SetColorTexture(C.card[1], C.card[2], C.card[3], (page.n % 2 == 0) and 0.55 or 0.25)
        page.y = page.y + h
        return r
    end

    local function Toggle(page, label, get, set, h)
        local r = Row(page, h or 36)
        local lab = FS(r, 13, C.text, "LEFT")
        lab:SetPoint("LEFT", 12, 0)
        lab:SetText(label)
        local b = MakeChip(r, "", 56)
        b:SetPoint("RIGHT", -10, 0)
        local function paint()
            local on = get() and true or false
            b.active = on
            b.text:SetText(on and L.cfg_on or L.cfg_off)
            if on then
                Flat(b, C.tile, C.green, 1)
                b.text:SetTextColor(C.green[1], C.green[2], C.green[3])
            else
                Flat(b, C.card, C.border, 0.9)
                b.text:SetTextColor(C.mute[1], C.mute[2], C.mute[3])
            end
        end
        b:SetScript("OnClick", function() set(not get()); paint() end)
        f.refreshers[#f.refreshers + 1] = paint
        return r
    end

    local function Slider(page, fmt, min, max, step, get, set)
        local r = Row(page, 46)
        local lab = FS(r, 13, C.text, "LEFT")
        lab:SetPoint("TOPLEFT", 12, -8)
        local track = CreateFrame("Frame", nil, r, BT2)
        track:SetSize(CONTENT_W - 24, 8)
        track:SetPoint("TOPLEFT", 12, -29)
        Flat(track, C.tile, C.border, 1)
        track:EnableMouse(true)
        track:SetHitRectInsets(0, 0, -9, -9)
        local fill = track:CreateTexture(nil, "ARTWORK")
        fill:SetPoint("TOPLEFT", 1, -1)
        fill:SetPoint("BOTTOMLEFT", 1, 1)
        fill:SetColorTexture(C.red[1], C.red[2], C.red[3], 0.9)
        local thumb = CreateFrame("Frame", nil, track, BT2)
        thumb:SetSize(8, 18)
        Flat(thumb, C.text, C.text, 1)
        local trackW = CONTENT_W - 24 - 2
        local cur
        local function show(v)
            cur = v
            lab:SetText(type(fmt) == "function" and fmt(v) or string.format(fmt, v))
            local frac = (v - min) / math.max(1, (max - min))
            fill:SetWidth(math.max(1, trackW * frac))
            thumb:ClearAllPoints()
            thumb:SetPoint("CENTER", track, "LEFT", 1 + trackW * frac, 0)
        end
        local function fromCursor()
            local x = GetCursorPosition() / track:GetEffectiveScale()
            local frac = (x - (track:GetLeft() or 0) - 1) / trackW
            frac = math.max(0, math.min(1, frac))
            local v = min + frac * (max - min)
            v = math.floor(v / step + 0.5) * step
            v = math.max(min, math.min(max, v))
            if v ~= cur then show(v); set(v) end
        end
        track:SetScript("OnMouseDown", function(self) self.drag = true; fromCursor() end)
        track:SetScript("OnMouseUp", function(self) self.drag = false end)
        track:SetScript("OnHide", function(self) self.drag = false end)
        track:SetScript("OnUpdate", function(self) if self.drag then fromCursor() end end)
        f.refreshers[#f.refreshers + 1] = function() show(get()) end
        return r
    end

    local function Text(page, text, h)
        local r = Row(page, h or 34)
        local fs = FS(r, 11, C.dim, "LEFT")
        fs:SetPoint("TOPLEFT", 12, -8)
        fs:SetPoint("RIGHT", r, "RIGHT", -12, 0)
        fs:SetJustifyV("TOP")
        fs:SetText(text)
        return r, fs
    end

    local function ChipRow(page, text, width, onClick, h)
        local r = Row(page, h or 36)
        local b = MakeChip(r, text, width)
        b:SetPoint("LEFT", 10, 0)
        b:SetScript("OnClick", onClick)
        return r, b
    end

    -- caixa de texto (como a da lista premium) + botao Adicionar + sugestoes
    local function AddBox(page, onAdd, suggest)
        local r = Row(page, 36)
        local box = CreateFrame("Frame", nil, r, BT2)
        box:SetPoint("LEFT", 10, 0)
        box:SetSize(CONTENT_W - 20 - 100, 26)
        Flat(box, C.card, C.border, 1)
        local eb = CreateFrame("EditBox", nil, box)
        eb:SetAutoFocus(false)
        eb:SetFont(K.FONT, 13, "")
        eb:SetTextColor(C.text[1], C.text[2], C.text[3])
        eb:SetPoint("TOPLEFT", 8, -2)
        eb:SetPoint("BOTTOMRIGHT", -8, 2)
        local add = MakeChip(r, L.cfg_add, 84)
        add:SetPoint("RIGHT", -10, 0)
        local sugg = {}
        local function hide() for _, b in ipairs(sugg) do b:Hide() end end
        local function commit()
            local v = strtrim(eb:GetText() or "")
            if v ~= "" then onAdd(v) end
            eb:SetText("")
            hide()
            eb:ClearFocus()
        end
        add:SetScript("OnClick", commit)
        eb:SetScript("OnEnterPressed", commit)
        eb:SetScript("OnEscapePressed", function(self) self:SetText(""); hide(); self:ClearFocus() end)
        if suggest then
            for i = 1, 6 do
                local b = CreateFrame("Button", nil, box, BT2)
                b:SetSize(CONTENT_W - 20 - 100, 22)
                b:SetPoint("TOPLEFT", box, "BOTTOMLEFT", 0, -1 - (i - 1) * 22)
                b:SetFrameStrata("FULLSCREEN_DIALOG")
                Flat(b, C.tile, C.border, 1)
                b.text = FS(b, 12, C.text, "LEFT")
                b.text:SetPoint("LEFT", 8, 0)
                b:SetScript("OnEnter", function(self) self.text:SetTextColor(C.blue[1], C.blue[2], C.blue[3]) end)
                b:SetScript("OnLeave", function(self) self.text:SetTextColor(C.text[1], C.text[2], C.text[3]) end)
                b:SetScript("OnClick", function(self)
                    if self.entry then WD:AddConsumableEntry(self.entry.name, self.entry.id) end
                    eb:SetText("")
                    hide()
                end)
                b:Hide()
                sugg[i] = b
            end
            eb:SetScript("OnTextChanged", function(self)
                hide()
                for i, e in ipairs(WD:SuggestItems(self:GetText(), 6)) do
                    sugg[i].entry = e
                    sugg[i].text:SetText(e.name)
                    sugg[i]:Show()
                end
            end)
            eb:SetScript("OnEditFocusLost", function() C_Timer.After(0.4, hide) end)
        end
        return r
    end

    -- lista com X vermelho; hasQty => campo ( N ) editavel
    -- Janelinha com a lista COMPLETA (abre ao clicar em "... e mais N")
    local popup
    local function ListPopup()
        if popup then return popup end
        local p = CreateFrame("Frame", "WatchdogListPopup", UIParent, BT2)
        p:SetSize(380, 330)
        p:SetPoint("CENTER", 0, 20)
        Flat(p, C.bg, C.border, 0.98)
        p:SetFrameStrata("FULLSCREEN_DIALOG")
        p:SetToplevel(true)
        p:SetClampedToScreen(true)
        p:SetMovable(true)
        p:EnableMouse(true)
        p:RegisterForDrag("LeftButton")
        p:SetScript("OnDragStart", p.StartMoving)
        p:SetScript("OnDragStop", p.StopMovingOrSizing)
        if UISpecialFrames then table.insert(UISpecialFrames, "WatchdogListPopup") end
        p:Hide()

        local title = FS(p, 14, C.text, "LEFT")
        title:SetPoint("TOPLEFT", 14, -14)
        title:SetText(L.cfg_list_all)
        local close = CreateFrame("Button", nil, p)
        close:SetSize(24, 24)
        close:SetPoint("TOPRIGHT", -8, -8)
        close.text = FS(close, 14, C.dim, "CENTER")
        close.text:SetPoint("CENTER")
        close.text:SetText("x")
        close:SetScript("OnClick", function() p:Hide() end)

        local scroll = CreateFrame("ScrollFrame", nil, p)
        scroll:SetPoint("TOPLEFT", 12, -44)
        scroll:SetPoint("BOTTOMRIGHT", -12, 12)
        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(354, 1)
        scroll:SetScrollChild(content)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local max = math.max(0, content:GetHeight() - self:GetHeight())
            self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * 56)))
        end)
        p.rows = {}

        function p:Fill(getList, hasQty)
            self.getList, self.hasQty = getList, hasQty
            local list = getList()
            for i = 1, math.max(#list, #self.rows) do
                local r = self.rows[i]
                if not r then
                    r = CreateFrame("Frame", nil, content)
                    r:SetSize(354, 28)
                    r:SetPoint("TOPLEFT", 0, -(i - 1) * 28)
                    r.label = FS(r, 13, C.blue, "LEFT")
                    r.label:SetPoint("LEFT", 8, 0)
                    r.label:SetWordWrap(false)
                    r.x = CreateFrame("Button", nil, r)
                    r.x:SetSize(26, 24)
                    r.x:SetPoint("RIGHT", -4, 0)
                    r.x.text = FS(r.x, 14, C.red, "CENTER")
                    r.x.text:SetPoint("CENTER")
                    r.x.text:SetText("X")
                    r.x:SetScript("OnClick", function()
                        table.remove(p.getList(), i)
                        p:Fill(p.getList, p.hasQty)
                        WD:RefreshConfig()
                    end)
                    r.box = CreateFrame("Frame", nil, r, BT2)
                    r.box:SetSize(56, 22)
                    r.box:SetPoint("RIGHT", r.x, "LEFT", -8, 0)
                    Flat(r.box, C.card, C.border, 1)
                    r.eb = CreateFrame("EditBox", nil, r.box)
                    r.eb:SetAutoFocus(false)
                    r.eb:SetNumeric(true)
                    r.eb:SetMaxLetters(4)
                    r.eb:SetFont(K.FONT, 13, "")
                    r.eb:SetJustifyH("CENTER")
                    r.eb:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
                    r.eb:SetPoint("TOPLEFT", 4, -2)
                    r.eb:SetPoint("BOTTOMRIGHT", -4, 2)
                    local function save(self2)
                        local it = p.getList()[i]
                        if it and type(it) == "table" then it.min = math.max(0, math.min(9999, tonumber(self2:GetText()) or 0)) end
                    end
                    r.eb:SetScript("OnEnterPressed", function(self2) save(self2); self2:ClearFocus() end)
                    r.eb:SetScript("OnEditFocusLost", save)
                    self.rows[i] = r
                end
                local it = list[i]
                if it then
                    local nm = type(it) == "table" and it.name or it
                    if nm == "@ammo" then nm = L.cfg_ammo end
                    if type(it) == "table" and it.minLevel then nm = nm .. " |cff9ca3af(lvl " .. it.minLevel .. "+)|r" end
                    r.label:SetText(nm)
                    r.label:SetWidth(hasQty and 220 or 280)
                    r.box:SetShown(hasQty and true or false)
                    if hasQty then r.eb:SetText(tostring(type(it) == "table" and it.min or 0)) end
                    r:Show()
                else
                    r:Hide()
                end
            end
            content:SetHeight(math.max(1, #list * 28))
            if #list == 0 then self:Hide() end
        end
        popup = p
        return p
    end
    f:HookScript("OnHide", function() if popup then popup:Hide() end end)

    local function ListRows(page, n, getList, hasQty)
        local rows = {}
        local first = page.y
        local more = CreateFrame("Button", nil, page)
        more:SetSize(360, 20)
        more.text = FS(more, 11, C.blue, "LEFT")
        more.text:SetPoint("LEFT", 0, 0)
        more:SetScript("OnEnter", function() more.text:SetTextColor(C.gold[1], C.gold[2], C.gold[3]) end)
        more:SetScript("OnLeave", function() more.text:SetTextColor(C.blue[1], C.blue[2], C.blue[3]) end)
        more:SetScript("OnClick", function()
            local p = ListPopup()
            p:Fill(getList, hasQty)
            p:Show()
        end)
        more:Hide()
        for i = 1, n do
            local r = Row(page, 28)
            local label = FS(r, 13, C.blue, "LEFT")
            label:SetPoint("LEFT", 12, 0)
            label:SetWidth(hasQty and 230 or 360)
            label:SetWordWrap(false)
            local x = CreateFrame("Button", nil, r)
            x:SetSize(26, 24)
            x:SetPoint("RIGHT", -8, 0)
            x.text = FS(x, 14, C.red, "CENTER")
            x.text:SetPoint("CENTER")
            x.text:SetText("X")
            x:SetScript("OnClick", function() table.remove(getList(), i); WD:RefreshConfig() end)
            r.label, r.x = label, x
            if hasQty then
                local box = CreateFrame("Frame", nil, r, BT2)
                box:SetSize(60, 22)
                box:SetPoint("RIGHT", x, "LEFT", -10, 0)
                Flat(box, C.card, C.border, 1)
                local eb = CreateFrame("EditBox", nil, box)
                eb:SetAutoFocus(false)
                eb:SetNumeric(true)
                eb:SetMaxLetters(4)
                eb:SetFont(K.FONT, 13, "")
                eb:SetJustifyH("CENTER")
                eb:SetTextColor(C.gold[1], C.gold[2], C.gold[3])
                eb:SetPoint("TOPLEFT", 4, -2)
                eb:SetPoint("BOTTOMRIGHT", -4, 2)
                local function save(self)
                    local it = getList()[i]
                    if it then it.min = math.max(0, math.min(9999, tonumber(self:GetText()) or 0)) end
                end
                eb:SetScript("OnEnterPressed", function(self) save(self); self:ClearFocus() end)
                eb:SetScript("OnEditFocusLost", save)
                eb:SetScript("OnEscapePressed", function(self) self:ClearFocus(); WD:RefreshConfig() end)
                local lp = FS(r, 14, C.dim, "RIGHT"); lp:SetPoint("RIGHT", box, "LEFT", -3, 0); lp:SetText("(")
                local rp = FS(r, 14, C.dim, "LEFT"); rp:SetPoint("LEFT", box, "RIGHT", 3, 0); rp:SetText(")")
                r.edit, r.lp, r.rp = eb, lp, rp
            end
            rows[i] = r
        end
        more:SetPoint("TOPLEFT", page, "TOPLEFT", 12, -(page.y + 6))
        f.refreshers[#f.refreshers + 1] = function()
            local list = getList()
            for i = 1, n do
                local r, it = rows[i], list[i]
                if it then
                    local nm = type(it) == "table" and it.name or it
                    if nm == "@ammo" then nm = L.cfg_ammo end
                    if type(it) == "table" and it.minLevel then nm = nm .. " |cff9ca3af(lvl " .. it.minLevel .. "+)|r" end
                    r.label:SetText(nm)
                    if r.edit then r.edit:SetText(tostring(it.min or 0)) end
                    r:Show()
                else
                    r:Hide()
                end
            end
            if #list == 0 then
                rows[1].label:SetText(L.cfg_none)
                rows[1].label:SetTextColor(C.mute[1], C.mute[2], C.mute[3])
                rows[1].x:Hide()
                if rows[1].edit then rows[1].edit:GetParent():Hide(); rows[1].lp:Hide(); rows[1].rp:Hide() end
                rows[1]:Show()
            else
                rows[1].label:SetTextColor(C.blue[1], C.blue[2], C.blue[3])
                rows[1].x:Show()
                if rows[1].edit then rows[1].edit:GetParent():Show(); rows[1].lp:Show(); rows[1].rp:Show() end
            end
            if #list > n then
                more.text:SetText(string.format(L.cfg_more, #list - n))
                more:Show()
            else
                more:Hide()
            end
            if popup and popup:IsShown() then popup:Fill(getList, hasQty) end
        end
    end

    local c = function() return WD:Cfg() end

    ---------------------------------------------------------------- paginas
    local p = NewPage("general")
    Toggle(p, L.cfg_sound, function() return c().sound end, function(v) c().sound = v end)
    Slider(p, L.cfg_bigscale, 60, 200, 10, function() return c().bigScale end, function(v) c().bigScale = v end)
    ChipRow(p, L.cfg_test, 90, function()
        WD:BigWarning(string.format(L.as_buff_soon, "Deadly Poison", 60), nil, "Interface\\Icons\\Ability_Poisons", { 1, 0.6, 0.1 })
    end)
    local _, placesFS = Text(p, "", 34)
    f.refreshers[#f.refreshers + 1] = function() placesFS:SetText(string.format(L.cfg_places, CountSpots())) end
    ChipRow(p, L.cfg_places_reset, 140, function()
        wipe(WD:Cfg().spots)
        print("|cffffd100Watchdog:|r " .. L.cfg_places_cleared)
        WD:RefreshConfig()
    end)

    p = NewPage("buffs")
    Toggle(p, L.cfg_buffs_on, function() return c().buff.on end, function(v) c().buff.on = v end)
    Toggle(p, (ClassFile() == "ROGUE") and L.cfg_buffs_poison or L.cfg_buffs_weapon, function() return c().buff.poisons end, function(v) c().buff.poisons = v end)
    Toggle(p, L.cfg_buffs_expired, function() return c().buff.expired end, function(v) c().buff.expired = v end)
    Slider(p, L.cfg_buffs_warn, 10, 300, 5, function() return c().buff.warnSec end, function(v) c().buff.warnSec = v end)
    Slider(p, L.cfg_buffs_mindur, 1, 60, 1, function() return c().buff.minDur end, function(v) c().buff.minDur = v end)
    Text(p, L.cfg_buffs_names, 24)
    AddBox(p, function(v)
        local l = c().buff.names
        for _, e in ipairs(l) do if e:lower() == v:lower() then return end end
        l[#l + 1] = v
        WD:RefreshConfig()
    end, false)
    ListRows(p, 2, function() return c().buff.names end, false)

    p = NewPage("cc")
    Toggle(p, L.cfg_cc_on, function() return c().cc.on end, function(v) c().cc.on = v end)
    Slider(p, L.cfg_cc_size, 24, 96, 4, function() return c().cc.size end, function(v) c().cc.size = v end)
    Toggle(p, L.cfg_cc_dr, function() return c().cc.dr end, function(v) c().cc.dr = v end)
    local mine = MyCCs()
    if #mine == 0 then
        Text(p, L.cfg_cc_none, 40)
    else
        for _, d in ipairs(mine) do
            local key = d.key
            local label = (SpellInfo(d.ids[1])) or d.en
            Toggle(p, label, function() return c().cc.spells[key] ~= false end, function(v) c().cc.spells[key] = v end, 28)
        end
    end
    ChipRow(p, L.cfg_test, 90, function() WD:TestCC() end)

    p = NewPage("dots")
    Toggle(p, L.cfg_dots_on, function() return c().dots.on end, function(v) c().dots.on = v end)
    Slider(p, L.cfg_dots_size, 16, 48, 2, function() return c().dots.size end, function(v) c().dots.size = v end)
    Slider(p, L.cfg_dots_warn, 0, 10, 1, function() return c().dots.warn end, function(v) c().dots.warn = v end)
    local mydots = MyDots()
    if #mydots == 0 then
        Text(p, L.cfg_dots_none, 40)
    else
        for _, d in ipairs(mydots) do
            local key = d.key
            Toggle(p, d.en, function() return c().dots.spells[key] ~= false end, function(v) c().dots.spells[key] = v end, 28)
        end
    end
    ChipRow(p, L.cfg_test, 90, function() WD:TestDots() end)

    p = NewPage("repair")
    Toggle(p, L.cfg_repair_on, function() return c().repair.on end, function(v) c().repair.on = v end)
    Slider(p, L.cfg_repair_pct, 5, 100, 5, function() return c().repair.pct end, function(v) c().repair.pct = v end)
    Text(p, L.cfg_repair_hint, 40)

    p = NewPage("food")
    Toggle(p, L.cfg_food_on, function() return c().food.on end, function(v) c().food.on = v end)
    Slider(p, L.cfg_food_count, 0, 100, 1, function() return c().food.count end, function(v) c().food.count = v end)
    Text(p, L.cfg_food_hint, 40)

    p = NewPage("cons")
    Toggle(p, L.cfg_cons_on, function() return c().cons.on end, function(v) c().cons.on = v end)
    Slider(p, L.cfg_cons_min, 0, 100, 1, function() return c().cons.min end, function(v) c().cons.min = v end)
    Text(p, L.cfg_cons_hint, 34)
    AddBox(p, function(v) WD:AddConsumable(v, true) end, true)
    ListRows(p, 5, function() return WD:ConsItems() end, true)

    p = NewPage("alerts")
    local QK = { [0] = "q_gray", "q_common", "q_uncommon", "q_rare", "q_epic", "q_legendary" }
    local QCOL = { [0] = "9d9d9d", "ffffff", "1eff00", "0070dd", "a335ee", "ff8000" }
    local function A() WatchdogDB.alerts = WatchdogDB.alerts or {}; return WatchdogDB.alerts end
    Toggle(p, L.cfg_alert_drop, function() return A().drop ~= false end, function(v) A().drop = v end)
    Slider(p, function(v)
        v = math.max(0, math.min(5, v))
        return string.format(L.cfg_alert_q, v, "|cff" .. QCOL[v] .. (L[QK[v]] or "?") .. "|r")
    end, 0, 5, 1, function() return A().minQuality or 3 end, function(v) A().minQuality = v end)
    Toggle(p, L.cfg_alert_rare, function() return A().rare ~= false end, function(v) A().rare = v end)
    Toggle(p, L.cfg_alert_sound, function() return A().sound ~= false end, function(v) A().sound = v end)
    local function SoundRow(cat, labelKey)
        local r = Row(p, 36)
        local lab = FS(r, 13, C.text, "LEFT")
        lab:SetPoint("LEFT", 12, 0)
        lab:SetText(L[labelKey])
        local test = MakeChip(r, L.cfg_snd_test, 54)
        test:SetPoint("RIGHT", -10, 0)
        local pick = MakeChip(r, "", 150)
        pick:SetPoint("RIGHT", test, "LEFT", -6, 0)
        local function paint() pick.text:SetText(L["snd_" .. WD.SOUNDS[WD:SoundIndex(cat)].key] or "?") end
        local function play()
            if not WD:PlayAlertSound(cat) then print("|cffffd100Watchdog:|r " .. L.cfg_snd_missing) end
        end
        pick:RegisterForClicks("AnyUp")
        pick:SetScript("OnClick", function(_, btn)
            local n, i = #WD.SOUNDS, WD:SoundIndex(cat)
            i = (btn == "RightButton") and ((i - 2) % n + 1) or (i % n + 1)
            WD:SetSound(cat, i); paint(); play()
        end)
        test:SetScript("OnClick", play)
        f.refreshers[#f.refreshers + 1] = paint
        paint()
    end
    SoundRow("rare", "cfg_snd_rare")
    SoundRow("drop", "cfg_snd_drop")
    SoundRow("rarekill", "cfg_snd_rarekill")
    SoundRow("warn", "cfg_snd_warn")
    Text(p, L.cfg_alert_hint, 40)

    ---------------------------------------------------------------- abas
    local function ShowPage(key)
        for k, pg in pairs(f.pages) do pg:SetShown(k == key) end
        for k, b in pairs(f.tabs) do b:SetActive(k == key) end
        f.current = key
    end
    -- Sub-menu horizontal (chips) no topo
    local prev
    for _, pdef in ipairs(PAGES) do
        local key = pdef.key
        local b = MakeChip(f, L[pdef.subK] or L[pdef.labelK], 60)
        local okw, tw = pcall(function() return b.text:GetStringWidth() end)
        b:SetWidth(math.max(44, ((okw and tw) or 40) + 18))
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", host, "TOPLEFT", left, -76) end
        b:SetScript("OnClick", function() ShowPage(key) end)
        f.tabs[key] = b
        prev = b
    end

    f.ShowPage = ShowPage
    f:SetScript("OnShow", function()
        for _, fn in ipairs(f.refreshers) do pcall(fn) end
        ShowPage(f.current or "general")
    end)
    return f
end

function WD:CreateConfigPanel(host, left)
    WD:Cfg()
    if not cf then cf = BuildConfig(host, left) end
    return cf
end

function WD:RefreshConfig()
    if cf and cf.refreshers then
        for _, fn in ipairs(cf.refreshers) do pcall(fn) end
    end
end

---------------------------------------------------------------------------
-- 7) Janela de comandos (mesmo visual do Watchdog)
---------------------------------------------------------------------------
local cmdF
local CMD_KEYS = { "help_open", "help_config", "help_new", "help_report", "help_hist", "help_cons", "help_session", "help_wizard", "help_inv", "help_alerts",
    "help_premium", "help_watch", "help_unwatch", "help_nameplates", "help_minimap", "help_goldbar", "help_expbar",
    "help_sgoldbar", "help_igoldbar", "help_lang", "help_status", "help_debug" }

local function BuildCommands()
    local K = WD.UIKit
    if not K then return nil end
    local C, Flat, FS, MEDIA = K.C, K.Flat, K.FS, K.MEDIA
    local PAD = K.PAD or 20
    local W, H = 720, 470
    local f = CreateFrame("Frame", "WatchdogCommandsFrame", UIParent, K.BT)
    f:SetSize(W, H)
    f:SetPoint("CENTER", 20, 0)
    Flat(f, C.bg, C.border, 0.97)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    tinsert(UISpecialFrames, "WatchdogCommandsFrame")

    local mark = f:CreateTexture(nil, "BACKGROUND")
    mark:SetTexture(MEDIA .. "emblem")
    mark:SetSize(160, 160)
    mark:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -24, 16)
    mark:SetAlpha(0.06)

    local wordmark = f:CreateTexture(nil, "ARTWORK")
    wordmark:SetTexture(MEDIA .. "wordmark")
    wordmark:SetSize(136, 17)
    wordmark:SetPoint("TOPLEFT", PAD, -24)

    local title = FS(f, 22, C.text, "LEFT", "")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -52)
    title:SetText(L.chip_commands)
    local sub = FS(f, 12, C.dim, "LEFT")
    sub:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -80)
    sub:SetText(L.cmd_sub)

    local close = CreateFrame("Button", nil, f)
    close:SetSize(26, 26)
    close:SetPoint("TOPRIGHT", -10, -10)
    close.text = FS(close, 16, C.mute, "CENTER")
    close.text:SetPoint("CENTER", 0, 1)
    close.text:SetText("x")
    close:SetScript("OnEnter", function(self) self.text:SetTextColor(C.red[1], C.red[2], C.red[3]) end)
    close:SetScript("OnLeave", function(self) self.text:SetTextColor(C.mute[1], C.mute[2], C.mute[3]) end)
    close:SetScript("OnClick", function() f:Hide() end)

    local line = f:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -104)
    line:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -104)
    line:SetHeight(1)
    line:SetColorTexture(1, 1, 1, 0.07)

    local sc = CreateFrame("ScrollFrame", nil, f)
    sc:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -112)
    sc:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD - 10, PAD)
    local content = CreateFrame("Frame", nil, sc)
    content:SetSize(W - PAD * 2 - 10, 10)
    sc:SetScrollChild(content)

    local ROW_H, CMD_W = 36, 270
    local n = 0
    for _, key in ipairs(CMD_KEYS) do
        local text = L[key]
        if text then
            local cmd, desc = text:match("^%s*(.-)%s+%-%s+(.+)$")
            if cmd then
                local row = CreateFrame("Frame", nil, content, K.BT)
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -n * (ROW_H + 4))
                row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
                row:SetHeight(ROW_H)
                Flat(row, C.card, C.border, 0.9)
                local c = FS(row, 13, C.gold, "LEFT", "")
                c:SetPoint("LEFT", row, "LEFT", 12, 0)
                c:SetWidth(CMD_W)
                c:SetText(cmd)
                local d = FS(row, 12, C.dim, "LEFT", "")
                d:SetPoint("LEFT", row, "LEFT", CMD_W + 24, 0)
                d:SetPoint("RIGHT", row, "RIGHT", -12, 0)
                d:SetText(desc)
                n = n + 1
            end
        end
    end
    content:SetHeight(math.max(10, n * (ROW_H + 4)))

    -- barra de rolagem fina
    local track = f:CreateTexture(nil, "ARTWORK")
    track:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -112)
    track:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
    track:SetWidth(4)
    track:SetColorTexture(1, 1, 1, 0.06)
    local thumb = f:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(4)
    thumb:SetColorTexture(C.gold[1], C.gold[2], C.gold[3], 0.8)
    local function UpdateThumb()
        local viewH = sc:GetHeight() or 1
        local total = content:GetHeight()
        local max = math.max(0, total - viewH)
        if max <= 0 then thumb:Hide() return end
        thumb:Show()
        local th = math.max(24, viewH * viewH / total)
        thumb:SetHeight(th)
        local off = (sc:GetVerticalScroll() / max) * (viewH - th)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -112 - off)
    end
    sc:EnableMouseWheel(true)
    sc:SetScript("OnMouseWheel", function(self, delta)
        local max = math.max(0, content:GetHeight() - self:GetHeight())
        local v = math.min(max, math.max(0, self:GetVerticalScroll() - delta * 48))
        self:SetVerticalScroll(v)
        UpdateThumb()
    end)
    f:SetScript("OnShow", function(self) self:Raise(); sc:SetVerticalScroll(0); UpdateThumb() end)
    return f
end

function WD:ToggleCommands()
    if not cmdF then cmdF = BuildCommands() end
    if not cmdF then return end
    if cmdF:IsShown() then cmdF:Hide() else cmdF:Show() end
end

function WD:ToggleConfig()
    WD:Cfg()
    WD:Toggle("alerts")
end

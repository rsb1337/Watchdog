-- Watchdog: sistema de idiomas / localization system.
-- Para adicionar um novo idioma, copie o bloco WD:RegisterLocale("enUS", {...})
-- abaixo, troque "enUS" pelo código do idioma (ex.: "deDE", "frFR", "esES"),
-- traduza os valores e adicione o código em WD.localeOrder.
--
-- To add a new language, copy the WD:RegisterLocale("enUS", {...}) block below,
-- change "enUS" to the language code, translate the values, and add the code to
-- WD.localeOrder. Missing keys fall back to English automatically.

local _, WD = ...

WD.locales = WD.locales or {}
-- Idiomas oferecidos na troca pelo /wd lang (enUS é sempre o fallback).
WD.localeOrder = { "enUS", "ptBR" }
WD.localeNames = { enUS = "English", ptBR = "Português (BR)" }

function WD:RegisterLocale(code, tbl)
    local t = WD.locales[code] or {}
    for k, v in pairs(tbl) do t[k] = v end
    WD.locales[code] = t
end

-- L resolve a chave no idioma ativo; se faltar, cai no inglês; se faltar, a própria chave.
WD.activeLocale = "enUS"
WD.L = setmetatable({}, {
    __index = function(_, key)
        local code = WD.activeLocale or "enUS"
        local loc = WD.locales[code]
        local v = loc and loc[key]
        if v ~= nil then return v end
        local en = WD.locales.enUS
        if en and en[key] ~= nil then return en[key] end
        return key
    end,
})

-- Define/troca o idioma ativo. Aceita um código conhecido; senão, inglês.
function WD:SetLocale(code)
    if not code or not WD.locales[code] then code = "enUS" end
    WD.activeLocale = code
    return code
end

-- Escolhe o idioma: salvo pelo usuário, senão o do cliente, senão inglês.
function WD:ResolveLocale()
    local saved = WatchdogDB and WatchdogDB.locale
    if saved and WD.locales[saved] then return WD:SetLocale(saved) end
    local client = GetLocale and GetLocale() or "enUS"
    if WD.locales[client] then return WD:SetLocale(client) end
    return WD:SetLocale("enUS")
end

---------------------------------------------------------------------------
-- English (base / fallback)
---------------------------------------------------------------------------
WD:RegisterLocale("enUS", {
    -- períodos
    period_all = "Total", period_month = "Month", period_week = "Week",
    period_day = "Day", period_session = "Session",
    -- abas
    tab_pve = "PvE", tab_pvp = "PvP", tab_xp = "EXP",
    tab_inv = "Inventory", tab_hist = "History",
    title_pve = "PvE", title_pvp = "PvP", title_xp = "Experience",
    title_inv = "Inventory", title_hist = "Session history",
    -- ordenação / visões
    sort_kills = "Sort: Kills", sort_value = "Sort: Value",
    sort_perkill = "Sort: $/kill", sort_hit = "Sort: Drop %",
    inv_bag = "Bag", inv_list = "List",
    -- tiles
    t_kills = "KILLS", t_deaths = "DEATHS", t_honor = "HONOR GAINED",
    t_xp_period = "XP THIS PERIOD", t_xp_hour = "XP PER HOUR",
    t_xp_session = "XP THIS SESSION", t_levels = "LEVELS GAINED",
    t_time_level = "TIME TO LEVEL", t_kills_level = "KILLS TO LEVEL",
    t_remaining = "XP TO LEVEL", rested_prefix = "rested ", worth_prefix = "worth ",
    -- textos diversos da janela
    session_since = "Session (since ",
    value_label = "Value: ",
    level_prefix = "Level ",
    max_level = "max level",
    rare_tag = "[Rare] ",
    dropped_suffix = " dropped",
    money_dropped = "Money dropped",
    killed_suffix = " killed",
    total_items_money = "Total (items + money)",
    no_value = "no value",
    no_drops = "No drops recorded yet.",
    click_drops = "Click to see drops",
    no_kills = "No kills recorded in this period.",
    kills_word = " kills",
    bags_label = "Bags: ",
    slots_word = " slots",
    bags_empty = "Bags empty.",
    sessions_saved = " saved sessions",
    current_session = "Current session",
    session_active = "ACTIVE SESSION",
    back = "< Back",
    per_hour = "  /hour",
    session_colon = "session: ",
    in_session = "  this session",
    in_inventory = "  in inventory",
    bar_gold = "gold/hour", bar_exp = "XP/hour",
    bar_sgold = "session gold", bar_igold = "inventory value",
    xp_hour_suffix = " XP/hour",
    level_up_in = "levels in ",   -- unused placeholder
    ups_in = "up in ",
    -- história (tooltip de sessão)
    hist_tooltip = "Duration: %s\nKills: %s\nXP: %s (levels: %d)\nTotal gold: %s\nMoney: %s\nPvP: %d kills, %d deaths, %s honor",
    hist_line_mid = " xp/h  ·  ",
    hist_line_end = " coin/h",
    -- relatório
    report_title = "Session report",
    report_hint = "Ctrl+C to copy and paste in chat or Discord.",
    report_header = "Watchdog - session %s (%s)",
    report_kills = "Kills: %s | XP: %s (%s/h) | Levels: %d",
    report_gold = "Gold: %s (%s/h) | Money: %s | Drops: %s",
    report_pvp = "PvP: %d kills, %d deaths, %s honor",
    report_topmobs = "Top mobs (by value):",
    report_mobline = "%d. %s - %d kills - %s (%s/kill)",
    btn_close = "Close", btn_refresh = "Refresh",
    -- chips laterais
    chip_premium = "Premium list", chip_report = "Report", chip_newsession = "New session",
    -- lista premium
    watch_title = "Premium list",
    watch_hint = "Mobs on the list get a blue name on the nameplate. Type a name or target the mob and use Add.",
    watch_count = "%d in list",
    watch_add = "Add", watch_add_target = "Add current target",
    watch_empty = "No mobs in the list yet.",
    watch_more = "... and %d more (use /wd unwatch)",
    watch_remove = "Click to remove",
    -- tooltips
    tip_drag_move = "Drag to move",
    tip_right_close = "Right-click: close",
    tip_click_toggle = "Click: open/close",
    tip_drag_button = "Drag: move button",
    tip_bar_title = "Watchdog · %s",
    -- qualidades
    q_gray = "gray", q_common = "common", q_uncommon = "uncommon",
    q_rare = "rare", q_epic = "epic", q_legendary = "legendary",
    -- alertas (toasts)
    alert_rarekill = "Rare mob slain",
    alert_drop = "Rare drop!",
    alert_rare = "Rare mob spotted!",
    alert_rare_body = "%s (level %s)",
    -- avisos / feedback de comando
    msg_new_session = "new session started.",
    msg_nameplates = "enemy names on and nameplate range maxed.",
    msg_watch_added = "'%s' added to the premium list (blue name on the nameplate).",
    msg_watch_usage = "use /wd watch <mob name> or target the mob and type /wd watch.",
    msg_watch_removed = "'%s' removed from the premium list.",
    msg_lang_set = "language set to %s.",
    msg_lang_reload = "type /reload to apply it to the window.",
    msg_lang_usage = "use /wd lang en | pt",
    bar_on = "bar on.", bar_off = "bar off.",
    bar_toggle = "%s bar %s",
    on_word = "on", off_word = "off",
    debug_on = "debug ON", debug_off = "debug off",
    -- alertas de config
    alerts_header = "Watchdog alerts:",
    alerts_drop = "  drop: %s (min quality %d = %s)",
    alerts_rare = "  rare mob: %s",
    alerts_sound = "  sound: %s",
    alerts_usage = "usage: /wd alertas [drop | rare | sound | 0-5]",
    enabled = "enabled", disabled = "disabled",
    -- ajuda
    help_header = "Watchdog commands:",
    help_open = "  /wd - open/close the window",
    help_new = "  /wd new - start a new session",
    help_report = "  /wd report - session report to copy",
    help_hist = "  /wd history - open the session history",
    help_inv = "  /wd inventory - open the inventory",
    help_alerts = "  /wd alertas [drop | rare | sound | 0-5] - drop/rare mob alerts",
    help_premium = "  /wd premium - open the premium list (blue mob names)",
    help_watch = "  /wd watch <name> (or target and /wd watch) - add mob to premium list",
    help_unwatch = "  /wd unwatch <name> - remove mob from premium list",
    help_nameplates = "  /wd nameplates - enable enemy names and max range (blue from farther)",
    help_minimap = "  /wd minimap - show/hide the minimap button",
    help_goldbar = "  /wd goldbar  (or /wdgoldbar) - floating gold/hour bar",
    help_expbar = "  /wd expbar  (or /wdexpbar) - floating XP/hour bar",
    help_sgoldbar = "  /wd sgoldbar  (or /wdsgoldbar) - session total gold bar",
    help_igoldbar = "  /wd igoldbar  (or /wdigoldbar) - inventory sell-value bar",
    help_lang = "  /wd lang en | pt - change language",
    help_status = "  /wd status - show registered events and counters",
    help_debug = "  /wd debug - toggle debug messages",
    -- status
    status_title = "status:",
    status_optional = "(optional)",
    status_missing = "missing",
})

---------------------------------------------------------------------------
-- Português (Brasil)
---------------------------------------------------------------------------
WD:RegisterLocale("ptBR", {
    period_all = "Total", period_month = "Mês", period_week = "Semana",
    period_day = "Dia", period_session = "Sessão",
    tab_pve = "PvE", tab_pvp = "PvP", tab_xp = "EXP",
    tab_inv = "Inventário", tab_hist = "Histórico",
    title_pve = "PvE", title_pvp = "PvP", title_xp = "Experiência",
    title_inv = "Inventário", title_hist = "Histórico de sessões",
    sort_kills = "Ordem: Kills", sort_value = "Ordem: Valor",
    sort_perkill = "Ordem: $/kill", sort_hit = "Ordem: Drop %",
    inv_bag = "Bolsa", inv_list = "Lista",
    t_kills = "KILLS", t_deaths = "MORTES", t_honor = "HONRA GANHA",
    t_xp_period = "XP NO PERÍODO", t_xp_hour = "XP POR HORA",
    t_xp_session = "XP NA SESSÃO", t_levels = "NÍVEIS GANHOS",
    t_time_level = "TEMPO PARA UPAR", t_kills_level = "KILLS PARA UPAR",
    t_remaining = "FALTA PARA UPAR", rested_prefix = "descansada ", worth_prefix = "vale ",
    session_since = "Sessão (desde ",
    value_label = "Valor: ",
    level_prefix = "Nível ",
    max_level = "nível máximo",
    rare_tag = "[Raro] ",
    dropped_suffix = " dropados",
    money_dropped = "Dinheiro dropado",
    killed_suffix = " mortos",
    total_items_money = "Total (itens + dinheiro)",
    no_value = "sem valor",
    no_drops = "Nenhum drop registrado ainda.",
    click_drops = "Clique para ver os drops",
    no_kills = "Nenhuma kill registrada nesse período.",
    kills_word = " kills",
    bags_label = "Bolsas: ",
    slots_word = " slots",
    bags_empty = "Bolsas vazias.",
    sessions_saved = " sessões salvas",
    current_session = "Sessão atual",
    session_active = "SESSÃO ATIVA",
    back = "< Voltar",
    per_hour = "  /hora",
    session_colon = "sessão: ",
    in_session = "  na sessão",
    in_inventory = "  no inventário",
    bar_gold = "ouro/hora", bar_exp = "XP/hora",
    bar_sgold = "ouro da sessão", bar_igold = "valor do inventário",
    xp_hour_suffix = " XP/hora",
    level_up_in = "upa em ",
    ups_in = "upa em ",
    hist_tooltip = "Duração: %s\nKills: %s\nXP: %s (níveis: %d)\nOuro total: %s\nDinheiro: %s\nPvP: %d kills, %d mortes, %s honra",
    hist_line_mid = " xp/h  ·  ",
    hist_line_end = " ouro/h",
    report_title = "Relatório da sessão",
    report_hint = "Ctrl+C para copiar e cole no chat ou no Discord.",
    report_header = "Watchdog - sessão %s (%s)",
    report_kills = "Kills: %s | XP: %s (%s/h) | Níveis: %d",
    report_gold = "Ouro: %s (%s/h) | Dinheiro: %s | Drops: %s",
    report_pvp = "PvP: %d kills, %d mortes, %s honra",
    report_topmobs = "Melhores mobs (por valor):",
    report_mobline = "%d. %s - %d kills - %s (%s/kill)",
    btn_close = "Fechar", btn_refresh = "Atualizar",
    chip_premium = "Lista premium", chip_report = "Relatório", chip_newsession = "Nova sessão",
    watch_title = "Lista premium",
    watch_hint = "Mobs da lista ficam com o nome azul na plaquinha. Digite ou mire no mob e use Adicionar.",
    watch_count = "%d na lista",
    watch_add = "Adicionar", watch_add_target = "Adicionar alvo atual",
    watch_empty = "Nenhum mob na lista ainda.",
    watch_more = "... e mais %d (use /wd unwatch)",
    watch_remove = "Clique para remover",
    tip_drag_move = "Arraste para mover",
    tip_right_close = "Botão direito: fechar",
    tip_click_toggle = "Clique: abrir/fechar",
    tip_drag_button = "Arrastar: mover botão",
    tip_bar_title = "Watchdog · %s",
    q_gray = "cinza", q_common = "comum", q_uncommon = "incomum",
    q_rare = "raro", q_epic = "épico", q_legendary = "lendário",
    alert_rarekill = "Mob raro abatido",
    alert_drop = "Drop raro!",
    alert_rare = "Mob raro avistado!",
    alert_rare_body = "%s (nível %s)",
    msg_new_session = "nova sessão iniciada.",
    msg_nameplates = "nomes de inimigos ligados e alcance das plaquinhas no máximo.",
    msg_watch_added = "'%s' adicionado à lista premium (nome azul na plaquinha).",
    msg_watch_usage = "use /wd watch <nome do mob> ou mire no mob e digite /wd watch.",
    msg_watch_removed = "'%s' removido da lista premium.",
    msg_lang_set = "idioma alterado para %s.",
    msg_lang_reload = "digite /reload para aplicar na janela.",
    msg_lang_usage = "use /wd lang en | pt",
    bar_on = "ligada.", bar_off = "desligada.",
    bar_toggle = "barra de %s %s",
    on_word = "ligada", off_word = "desligada",
    debug_on = "debug LIGADO", debug_off = "debug desligado",
    alerts_header = "Watchdog alertas:",
    alerts_drop = "  drop: %s (qualidade mínima %d = %s)",
    alerts_rare = "  mob raro: %s",
    alerts_sound = "  som: %s",
    alerts_usage = "uso: /wd alertas [drop | raro | som | 0-5]",
    enabled = "ligado", disabled = "desligado",
    help_header = "Watchdog comandos:",
    help_open = "  /wd - abre/fecha a janela",
    help_new = "  /wd nova - começa uma nova sessão",
    help_report = "  /wd relatorio - relatório da sessão para copiar",
    help_hist = "  /wd historico - abre o histórico de sessões",
    help_inv = "  /wd inventario - abre o inventário",
    help_alerts = "  /wd alertas [drop | raro | som | 0-5] - avisos de drop/mob raro",
    help_premium = "  /wd premium - abre a lista premium (nomes de mob em azul)",
    help_watch = "  /wd watch <nome> (ou mire e /wd watch) - adiciona mob à lista premium",
    help_unwatch = "  /wd unwatch <nome> - remove mob da lista premium",
    help_nameplates = "  /wd nameplates - liga nomes de inimigos e alcance máximo (azul de mais longe)",
    help_minimap = "  /wd minimapa - mostra/esconde o botão do minimapa",
    help_goldbar = "  /wd goldbar  (ou /wdgoldbar) - barra flutuante de ouro/hora",
    help_expbar = "  /wd expbar  (ou /wdexpbar) - barra flutuante de XP/hora",
    help_sgoldbar = "  /wd sgoldbar  (ou /wdsgoldbar) - barra do ouro total da sessão",
    help_igoldbar = "  /wd igoldbar  (ou /wdigoldbar) - barra do valor de venda do inventário",
    help_lang = "  /wd lang en | pt - troca o idioma",
    help_status = "  /wd status - mostra eventos registrados e contadores",
    help_debug = "  /wd debug - liga/desliga mensagens de depuração",
    status_title = "status:",
    status_optional = "(opcional)",
    status_missing = "não existe",
})

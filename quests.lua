-- quests.lua — quêtes de hints et envoi des hints AP.
-- À chaque tick (~1 fois/s via le wrapper de Game:update), si un seuil de quête
-- est franchi, send_hint() annonce un hint gratuit sur le serveur AP.
--
-- send_hint(): piocher une location au hasard dans client.missing_locations
-- (locations non checkées, maintenues par lua-apclientpp — JAMAIS une location
-- déjà checkée ni une location d'un autre slot) puis
--   client:LocationScouts({ loc }, 1)   -- create_as_hint = 1 = CreateAndAnnounce
-- Les hints d'un client taggé HintGame sont gratuits (pas de hint points) et le
-- serveur skippe silencieusement les hints déjà existants.
-- Cooldown global entre deux hints: settings.hint_cooldown (défaut 150 s), pour
-- viser ~1 hint / 2-3 min.

local BHM = G.BHM

local TICK_INTERVAL = 1.0 -- secondes entre deux ticks de quêtes

-- Définition des quêtes: id, label, in_run (ignorée hors run quand pertinent),
-- seuils croissants, et fonction de lecture de la valeur courante.
-- chips_total est un double LuaJIT (peut dépasser 2^53): comparaisons de
-- doubles uniquement, jamais de conversion en entier 64 bits.
local QUESTS = {
    { id = 'boss_blinds_beaten', label = 'boss blinds battus', in_run = true,
      thresholds = { 1, 2, 3, 4, 5, 6, 8, 10 },
      get = function() return BHM.counters.boss_blinds_beaten end },
    { id = 'runs_won', label = 'runs gagnés', in_run = false, -- compté uniquement en fin de run
      thresholds = { 1, 2, 3 },
      get = function() return BHM.counters.runs_won end },
    { id = 'hands_played', label = 'mains jouées', in_run = true,
      thresholds = { 10, 25, 50, 100, 200 },
      get = function() return BHM.counters.hands_played end },
    { id = 'jokers_bought', label = 'jokers achetés', in_run = true,
      thresholds = { 3, 6, 10, 15 },
      get = function() return BHM.counters.jokers_bought end },
    { id = 'ante_max', label = 'ante max atteint', in_run = true,
      thresholds = { 2, 3, 4, 5, 6, 8 },
      get = function() return BHM.max_ante end },
    { id = 'chips_total', label = 'chips cumulés', in_run = true,
      thresholds = { 1e6, 1e8, 1e10, 1e12, 1e15, 1e18, 1e21 },
      get = function() return BHM.counters.chips_total end },
}
for _, q in ipairs(QUESTS) do q.next_idx = 1 end

-- Envoie un hint (si cooldown écoulé et missing_locations non vide).
-- Retourne true si un hint a effectivement été envoyé.
function BHM.send_hint(reason)
    local c = BHM.client
    if not c or not BHM.connected then return false end
    local now = love.timer.getTime()
    local cooldown = tonumber(BHM.settings and BHM.settings.hint_cooldown) or 150
    if now - BHM.last_hint_at < cooldown then return false end
    local missing = c.missing_locations
    if type(missing) ~= 'table' or #missing == 0 then
        return false -- rien à hinter (ex. slot spectateur sans locations)
    end
    local loc = missing[math.random(#missing)]
    local ok, res = pcall(function() return c:LocationScouts({ loc }, 1) end)
    if not ok then
        BHM.log_warn('LocationScouts failed: ' .. tostring(res))
        return false
    end
    if res then
        BHM.last_hint_at = now
        BHM.log_info('hint sent for location ' .. tostring(loc) .. ' (quête: ' .. tostring(reason) .. ')')
        return true
    end
    return false
end

local function in_run()
    return G and G.STAGES and G.STAGE == G.STAGES.RUN
end

function BHM.quest_tick()
    for _, q in ipairs(QUESTS) do
        if not q.in_run or in_run() then
            local v = q.get()
            while q.next_idx <= #q.thresholds and v >= q.thresholds[q.next_idx] do
                if BHM.send_hint(q.label .. ' >= ' .. tostring(q.thresholds[q.next_idx])) then
                    q.next_idx = q.next_idx + 1
                else
                    break -- cooldown actif ou pas de missing_locations: on réessaie au prochain tick
                end
            end
        end
    end
end

-- Wrapper chaîné de Game:update, tick de quêtes ~1 fois/s.
local game_updateRef = Game.update
function Game:update(dt)
    local ret = game_updateRef(self, dt)
    BHM._quest_acc = BHM._quest_acc + (dt or 0)
    if BHM._quest_acc >= TICK_INTERVAL then
        BHM._quest_acc = 0
        local ok, err = pcall(BHM.quest_tick)
        if not ok then BHM.log_warn('quest_tick error: ' .. tostring(err)) end
    end
    return ret
end

BHM.log_info('quests installed')

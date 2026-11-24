-- state.lua — extraction d'état in-process + wrappers de hooks (chaînés).
-- Reprend les wrappers de l'ancien hintbridge.lua, SANS aucune écriture de
-- fichier: plus de pont HintMachine/state.json (seq, checksum, throttle).
-- L'état se lit directement via G.GAME / G.STAGE et les compteurs vivent dans
-- G.BHM.counters.

local BHM = G.BHM

local function in_run()
    return G and G.STAGES and G.STAGE == G.STAGES.RUN
end

-- Appelé à chaque frame via le wrapper de Game:update.
function BHM.on_update(dt)
    -- hands_played: diff de G.GAME.current_round.hands_played (reset à chaque
    -- round, donc on ne compte que les deltas positifs).
    if G and G.GAME and G.GAME.current_round then
        local hp = G.GAME.current_round.hands_played or 0
        if not BHM._hands_init then
            -- 1re lecture (ex. chargement d'une save en milieu de round):
            -- on initialise sans compter, sinon les mains déjà jouées de la
            -- round chargée seraient comptées comme des mains jouées.
            BHM._hands_init = true
        elseif hp > BHM._last_hands_played then
            BHM.counters.hands_played = BHM.counters.hands_played + (hp - BHM._last_hands_played)
        end
        BHM._last_hands_played = hp
    end
    -- chips_total: cumul des deltas positifs de G.GAME.chips. "chips" est un
    -- double LuaJIT pouvant dépasser 2^53 (ex 1e+20): on ne fait que des
    -- comparaisons et additions de doubles, jamais de conversion en entier 64 bits.
    if G and G.GAME then
        local ch = G.GAME.chips or 0
        if not BHM._chips_init then
            -- idem: 1re lecture = initialisation, pas de delta fantôme
            BHM._chips_init = true
        elseif ch > BHM._last_chips then
            BHM.counters.chips_total = BHM.counters.chips_total + (ch - BHM._last_chips)
        end
        BHM._last_chips = ch
        if in_run() and G.GAME.round_resets and G.GAME.round_resets.ante then
            local ante = G.GAME.round_resets.ante
            if ante > BHM.max_ante then BHM.max_ante = ante end
        end
    end
    -- On quitte l'écran de game over: la prochaine victoire pourra être comptée.
    if G and G.STATES and G.STATE ~= G.STATES.GAME_OVER then
        BHM._won_counted = false
    end
end

-- ==== Wrappers (chaînables: coexistence possible avec BalatroAP) ====

-- Game:update -> mise à jour des compteurs
local game_updateRef = Game.update
function Game:update(dt)
    local ret = game_updateRef(self, dt)
    local ok, err = pcall(BHM.on_update, dt)
    if not ok then BHM.log_warn('on_update error: ' .. tostring(err)) end
    return ret
end

-- Blind:defeat -> boss_blinds_beaten
local blind_defeatRef = Blind.defeat
function Blind:defeat(silent)
    local was_boss = self.boss and true or false
    local ret = blind_defeatRef(self, silent)
    if was_boss then
        BHM.counters.boss_blinds_beaten = BHM.counters.boss_blinds_beaten + 1
    end
    return ret
end

-- Game:update_game_over + G.GAME.won -> runs_won (une fois par game over)
local update_game_overRef = Game.update_game_over
function Game:update_game_over(dt)
    local ret = update_game_overRef(self, dt)
    if G and G.GAME and G.GAME.won and not BHM._won_counted then
        BHM._won_counted = true
        BHM.counters.runs_won = BHM.counters.runs_won + 1
    end
    return ret
end

-- Achat d'un joker en shop (bouton Buy -> G.FUNCS.buy_from_shop, cf. le patch
-- de functions/common_events.lua dans BalatroAP) -> jokers_bought
if G.FUNCS and type(G.FUNCS.buy_from_shop) == 'function' then
    local buy_from_shopRef = G.FUNCS.buy_from_shop
    G.FUNCS.buy_from_shop = function(e)
        local c1 = e and e.config and e.config.ref_table
        local jokers_before = (G.jokers and #G.jokers.cards) or 0
        local ret = buy_from_shopRef(e)
        -- On compte uniquement si un joker a réellement été ajouté: buy_from_shop
        -- retourne nil (pas false) quand l'achat est refusé (fonds insuffisants),
        -- donc tester la valeur de retour ne suffit pas.
        if c1 and c1.ability and c1.ability.set == 'Joker'
           and G.jokers and #G.jokers.cards > jokers_before then
            BHM.counters.jokers_bought = BHM.counters.jokers_bought + 1
        end
        return ret
    end
end

BHM.log_info('state hooks installed')

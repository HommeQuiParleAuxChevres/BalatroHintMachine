-- hintbridge.lua — logique du pont Balatro -> HintMachine (protocole v1).
-- Contrat exact avec HintMachine/Models/Games/BalatroConnector.cs :
--   fichier  : %AppData%/Roaming/Balatro/HintMachine/state.json  (chemin relatif NFS)
--   payload  : {"protocol":1,"seq":N,"in_run":bool,"ante":N,"chips":"...",
--               "counters":{...},"checksum":C}
--   checksum : somme des octets du payload SANS le champ "checksum":N
--              body = json(objet sans checksum) ; head = body sans '}' final ;
--              C = somme des octets de (head .. ",}") ;
--              payload = head .. ',"checksum":' .. C .. '}'
--   écriture : NFS.write('HintMachine/state.json', payload), ~4 Hz max,
--              uniquement si le contenu a changé (seq incrémenté à chaque écrit).

local HB = HintMachineBridge
local json = HB.json

local PROTOCOL_VERSION = 1
local BRIDGE_DIR = 'HintMachine'
local STATE_PATH = 'HintMachine/state.json'
local WRITE_INTERVAL = 0.25 -- ~4 Hz max

local function log_info(msg)
    if sendInfoMessage then sendInfoMessage('[BalatroHintMachine] ' .. msg, 'HintMachineBridge') end
end
local function log_warn(msg)
    if sendWarnMessage then sendWarnMessage('[BalatroHintMachine] ' .. msg, 'HintMachineBridge') end
end

HB._acc = 0
HB._last_body = nil        -- signature (json sans seq) du dernier état écrit
HB._last_hands_played = 0
HB._won_counted = false
HB._dir_ready = false

local function ensure_dir()
    local info = NFS.getInfo(BRIDGE_DIR)
    if not info or info.type ~= 'directory' then
        NFS.createDirectory(BRIDGE_DIR)
    end
    HB._dir_ready = true
end

-- Objet d'état (protocole v1). "chips" est une STRING car c'est un double
-- LuaJIT qui peut dépasser 2^53 (ex "1e+20").
local function build_state(seq)
    local in_run = false
    local ante = 0
    local chips = '0'
    if G and G.STAGES then
        in_run = (G.STAGE == G.STAGES.RUN)
    end
    if G and G.GAME then
        if G.GAME.round_resets and G.GAME.round_resets.ante then
            ante = G.GAME.round_resets.ante
        end
        chips = tostring(G.GAME.chips or 0)
    end
    return {
        protocol = PROTOCOL_VERSION,
        seq = seq,
        in_run = in_run and true or false,
        ante = ante,
        chips = chips,
        counters = {
            boss_blinds_beaten = HB.counters.boss_blinds_beaten,
            runs_won = HB.counters.runs_won,
            hands_played = HB.counters.hands_played,
            jokers_bought = HB.counters.jokers_bought,
        },
    }
end

-- Construit le payload final avec son checksum (voir contrat en tête de fichier).
-- Le payload reste ASCII: json.lua n'échappe que les caractères de contrôle,
-- et toutes nos valeurs sont ASCII (chips vient de tostring(double)).
local function build_payload(state)
    local body = json.encode(state)      -- objet SANS checksum
    local head = body:sub(1, -2)         -- body sans l'accolade finale
    local s = head .. ',}'
    local cs = 0
    for i = 1, #s do cs = cs + s:byte(i) end
    return head .. ',"checksum":' .. cs .. '}'
end

-- Écrit state.json si l'état a changé depuis la dernière écriture.
function HB.write_if_changed()
    if not json then return end
    if not HB._dir_ready then ensure_dir() end
    -- Signature sans seq: tant que l'état ne change pas, on ne réécrit rien.
    local sig = json.encode(build_state(0))
    if sig == HB._last_body then return end
    HB.seq = HB.seq + 1
    local payload = build_payload(build_state(HB.seq))
    local ok, err = NFS.write(STATE_PATH, payload)
    if not ok then
        ensure_dir() -- le dossier a peut-être disparu: on retente une fois
        ok, err = NFS.write(STATE_PATH, payload)
    end
    if ok then
        HB._last_body = sig
    else
        log_warn('write of ' .. STATE_PATH .. ' failed: ' .. tostring(err))
    end
end

-- Appelé à chaque frame via le wrapper de Game:update.
function HB.on_update(dt)
    -- hands_played: diff de G.GAME.current_round.hands_played (reset à chaque
    -- round, donc on ne compte que les deltas positifs, échantilloné à chaque frame).
    if G and G.GAME and G.GAME.current_round then
        local hp = G.GAME.current_round.hands_played or 0
        if hp > HB._last_hands_played then
            HB.counters.hands_played = HB.counters.hands_played + (hp - HB._last_hands_played)
        end
        HB._last_hands_played = hp
    end
    -- On quitte l'écran de game over: la prochaine victoire pourra être comptée.
    if G and G.STATES and G.STATE ~= G.STATES.GAME_OVER then
        HB._won_counted = false
    end
    -- Écriture throttlée à ~4 Hz max.
    HB._acc = HB._acc + (dt or 0)
    if HB._acc < WRITE_INTERVAL then return end
    HB._acc = 0
    HB.write_if_changed()
end

-- ==== Wrappers (chaînables: coexistence possible avec BalatroAP) ====

-- Game:update -> heartbeat du pont
local game_updateRef = Game.update
function Game:update(dt)
    local ret = game_updateRef(self, dt)
    local ok, err = pcall(HB.on_update, dt)
    if not ok then log_warn('on_update error: ' .. tostring(err)) end
    return ret
end

-- Blind:defeat -> boss_blinds_beaten
local blind_defeatRef = Blind.defeat
function Blind:defeat(silent)
    local was_boss = self.boss and true or false
    local ret = blind_defeatRef(self, silent)
    if was_boss then
        HB.counters.boss_blinds_beaten = HB.counters.boss_blinds_beaten + 1
    end
    return ret
end

-- Game:update_game_over + G.GAME.won -> runs_won (une fois par game over)
local update_game_overRef = Game.update_game_over
function Game:update_game_over(dt)
    local ret = update_game_overRef(self, dt)
    if G and G.GAME and G.GAME.won and not HB._won_counted then
        HB._won_counted = true
        HB.counters.runs_won = HB.counters.runs_won + 1
    end
    return ret
end

-- Achat d'un joker en shop (bouton Buy -> G.FUNCS.buy_from_shop, cf. le patch
-- de functions/common_events.lua dans BalatroAP) -> jokers_bought
if G.FUNCS and type(G.FUNCS.buy_from_shop) == 'function' then
    local buy_from_shopRef = G.FUNCS.buy_from_shop
    G.FUNCS.buy_from_shop = function(e)
        local c1 = e and e.config and e.config.ref_table
        local ret = buy_from_shopRef(e)
        if ret ~= false and c1 and c1.ability and c1.ability.set == 'Joker' then
            HB.counters.jokers_bought = HB.counters.jokers_bought + 1
        end
        return ret
    end
end

-- Premier état écrit dès le chargement: HintMachine exige que le fichier existe.
ensure_dir()
HB.write_if_changed()
log_info('bridge initialized, writing ' .. STATE_PATH)

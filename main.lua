--- STEAMODDED HEADER
--- MOD_NAME: BalatroHintMachine
--- MOD_ID: HintMachineBridge
--- MOD_AUTHOR: [HommeQuiParleAuxChevres]
--- MOD_DESCRIPTION: Autonomous Archipelago hint client for Balatro. Connects by itself to an AP server as a dedicated HintGame slot (NoItems) and announces free hints (LocationScouts create_as_hint=1) when in-game quests progress. No HintMachine app, no state.json bridge.
--- DISPLAY_NAME: BalatroHintMachine
--- PRIORITY: 0
--- DEPENDENCIES: [Steamodded>=1.0.0]
--- VERSION: 2.0.0
----------------------------------------------
------------MOD CODE --------------------------

-- BalatroHintMachine v2: client Archipelago 100% autonome (style CloverPitAPHints).
-- Plus de pont fichier avec HintMachine: l'état du jeu se lit in-process
-- (G.GAME / G.STAGE) et les hints partent directement vers le serveur AP via
-- la lib lua-apclientpp (dossier lua-apclientpp/, copié depuis BalatroAP).
--
-- Sandbox Lovely: os/io/package/loadstring sont nil. On utilise UNIQUEMENT
-- l'API NFS de Steamodded (working dir = %AppData%/Roaming/Balatro), love.*,
-- et le require injecté par Lovely pour charger la DLL lua-apclientpp
-- (même pattern que BalatroAP: NFS.setWorkingDirectory vers le dossier de la
-- DLL le temps du require).
--
-- Coexistence avec BalatroAP: on chaine les wrappers (local old = X; function
-- X(...) ... return old(...) end), on n'écrase aucun global de l'autre mod, et
-- on ne touche jamais à G.AP: toutes nos globales vivent sous G.BHM.

local this_mod = SMODS.current_mod or (SMODS.Mods and SMODS.Mods['HintMachineBridge'])

local function mod_path(name)
    local p = (this_mod and this_mod.path) or ''
    if p:sub(-1) ~= '/' and p:sub(-1) ~= '\\' then p = p .. '/' end
    return p .. name
end

-- Namespace global du mod (préfixe G.BHM). Les compteurs sont initialisés ici:
-- le mod n'est chargé qu'une fois par lancement du jeu, donc ils repartent de
-- zéro à chaque lancement.
G.BHM = {
    mod = this_mod,
    mod_path = mod_path, -- réutilisé par ap_client.lua (dossier lua-apclientpp)
    json = nil,          -- json.lua (encode/decode)
    AP = nil,            -- lib lua-apclientpp (DLL native)
    client = nil,        -- instance APClient courante
    connected = false,   -- true quand le slot est connecté (SlotConnected reçu)
    settings = nil,      -- config BalatroHintMachineSettings.json
    last_attempt = 0,    -- love.timer.getTime() de la dernière tentative de connexion
    last_hint_at = -1e9, -- love.timer.getTime() du dernier hint envoyé
    counters = {
        boss_blinds_beaten = 0,
        runs_won = 0,
        hands_played = 0,
        jokers_bought = 0,
        chips_total = 0, -- double LuaJIT, peut dépasser 2^53: jamais de conversion en entier
    },
    max_ante = 0,
    _last_hands_played = 0,
    _last_chips = 0,
    _won_counted = false,
    _quest_acc = 0,
    _socket_down = true,  -- dernier état connu du socket (true = tombé/jamais connecté)
    _room_info_at = 0,    -- love.timer.getTime() du dernier RoomInfo reçu
    _refused = false,     -- true après un SlotRefused (backoff des tentatives)
    _hands_init = false,  -- _last_hands_played initialisé à la 1re lecture (évite un delta fantôme au chargement d'une save)
    _chips_init = false,  -- idem pour _last_chips
}

-- Seed du PRNG: LuaJIT démarre avec une seed fixe, donc math.random produirait
-- la même séquence (et les mêmes locations hintées) à chaque lancement.
-- os est nil dans le sandbox Lovely: on seed via love.timer.
pcall(function()
    if love and love.timer then
        local micros = love.timer.getMicro and love.timer.getMicro() or 0
        math.randomseed(love.timer.getTime() * 1e6 + micros)
    end
end)

function G.BHM.log_info(msg)
    if sendInfoMessage then sendInfoMessage('[BalatroHintMachine] ' .. msg, 'HintMachineBridge') end
end
function G.BHM.log_warn(msg)
    if sendWarnMessage then sendWarnMessage('[BalatroHintMachine] ' .. msg, 'HintMachineBridge') end
end
function G.BHM.log_error(msg)
    if sendErrorMessage then sendErrorMessage('[BalatroHintMachine] ' .. msg, 'HintMachineBridge') end
end

-- json.lua (copié depuis BalatroAP, rxi/json.lua) fournit json.encode/decode.
local json_chunk = NFS.load(mod_path('json.lua'))
if not json_chunk then
    G.BHM.log_error('cannot load json.lua')
else
    G.BHM.json = json_chunk()
end

-- Charge un fichier du mod via NFS.load (pattern BalatroAP).
local function load_file(name)
    local chunk = NFS.load(mod_path(name))
    if not chunk then
        G.BHM.log_error('cannot load ' .. name)
        return false
    end
    local ok, err = pcall(chunk)
    if not ok then G.BHM.log_error('error while running ' .. name .. ': ' .. tostring(err)) end
    return ok
end

-- Ordre: ap_client a besoin de json (settings), state pose les wrappers de
-- compteurs, quests consomme compteurs + client AP.
load_file('ap_client.lua')
load_file('state.lua')
load_file('quests.lua')

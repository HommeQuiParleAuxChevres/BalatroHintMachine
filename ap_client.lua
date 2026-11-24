-- ap_client.lua — connexion au serveur Archipelago en slot dédié HintGame (NoItems).
--
-- Config lue/écrite dans %AppData%/Roaming/Balatro/BalatroHintMachineSettings.json
-- (chemin relatif NFS, working dir = %AppData%/Roaming/Balatro) :
--   {
--     "server": "host:port",     -- ex "localhost:38281"
--     "slot": "BalatroHints",    -- nom du slot dédié (yaml game: Archipelago)
--     "password": "",            -- mot de passe de la room ("" si none)
--     "game": "",                -- game envoyé dans Connect; "" = ignoré (tag HintGame)
--     "hint_cooldown": 150,      -- secondes entre deux hints (global)
--     "reconnect_interval": 10   -- secondes entre deux tentatives de reconnexion
--   }
--
-- Connexion: APClient("", game, server) puis, sur RoomInfo,
--   ConnectSlot(slot, password, 0, {"AP", "HintGame", "TextOnly"}, {0, 5, 0})
--   items_handling 0 = NoItems (comme CloverPit), version {0,5,0} = min client AP.
-- Reconnexion auto si le socket tombe: reset() au prochain poll (les handlers
-- restent en place, on_room_info renvoie ConnectSlot), throttlé dans le
-- wrapper de Game:update. Le reset n'est déclenché que si le socket est tombé
-- (ou si le handshake bloque plus de reconnect_interval); backoff x4 (max 120 s)
-- après un SlotRefused.

local BHM = G.BHM
local json = BHM.json

local SETTINGS_PATH = 'BalatroHintMachineSettings.json'
local DEFAULTS = {
    server = 'localhost:38281',
    slot = '',
    password = '',
    game = '',
    hint_cooldown = 150,
    reconnect_interval = 10,
}
local TAGS = { 'AP', 'HintGame', 'TextOnly' }
local VERSION = { 0, 5, 0 }
local ITEMS_HANDLING_NO_ITEMS = 0

function BHM.load_settings()
    local s = {}
    for k, v in pairs(DEFAULTS) do s[k] = v end
    local raw = NFS.read(SETTINGS_PATH)
    if raw then
        local ok, decoded = pcall(json.decode, raw)
        if ok and type(decoded) == 'table' then
            for k, v in pairs(decoded) do s[k] = v end
        else
            BHM.log_warn(SETTINGS_PATH .. ' unreadable, using defaults')
        end
    else
        -- écrit le gabarit pour que l'utilisateur le remplisse
        -- (repli en chaîne littérale si json.lua n'a pas pu être chargé)
        local template
        if json then
            template = json.encode(DEFAULTS)
        else
            template = [[
{
  "server": "localhost:38281",
  "slot": "",
  "password": "",
  "game": "",
  "hint_cooldown": 150,
  "reconnect_interval": 10
}
]]
        end
        NFS.write(SETTINGS_PATH, template)
        BHM.log_info('wrote default settings template to ' .. SETTINGS_PATH)
    end
    BHM.settings = s
    return s
end

function BHM.save_settings()
    if BHM.settings and json then
        NFS.write(SETTINGS_PATH, json.encode(BHM.settings))
    end
end

-- Charge la DLL lua-apclientpp (pattern BalatroAP: on se place dans le dossier
-- de la DLL le temps du require, puis on restaure le working dir).
function BHM.load_ap_lib()
    if BHM.AP then return true end
    local workdir = NFS.getWorkingDirectory()
    -- mod_path gère l'ajout du séparateur si mod.path ne se termine pas par '/' ou '\'
    local dll_dir = BHM.mod_path('lua-apclientpp')
    NFS.setWorkingDirectory(dll_dir)
    local ok, lib = pcall(require, 'lua-apclientpp')
    NFS.setWorkingDirectory(workdir)
    if ok and lib then
        BHM.AP = lib
        BHM.log_info('lua-apclientpp loaded')
        return true
    end
    BHM.log_error('failed to load lua-apclientpp: ' .. tostring(lib))
    return false
end

local function on_socket_connected()
    BHM._socket_down = false
    BHM.log_info('socket connected')
end

local function on_socket_error(msg)
    BHM.log_warn('socket error: ' .. tostring(msg))
    BHM.connected = false
    BHM._socket_down = true
end

local function on_socket_disconnected()
    BHM.log_warn('socket disconnected')
    BHM.connected = false
    BHM._socket_down = true
end

local function on_room_info()
    local c = BHM.client
    if not c or BHM.connected then return end -- ne pas renvoyer ConnectSlot si déjà connecté
    BHM._room_info_at = love.timer.getTime()
    BHM.log_info('room info received, connecting slot "' .. tostring(BHM.settings.slot) .. '"')
    local ok, err = pcall(function()
        c:ConnectSlot(BHM.settings.slot, BHM.settings.password or '', ITEMS_HANDLING_NO_ITEMS, TAGS, VERSION)
    end)
    if not ok then BHM.log_warn('ConnectSlot failed: ' .. tostring(err)) end
end

local function on_slot_connected(slot_data)
    BHM.connected = true
    BHM._refused = false
    local team = select(2, pcall(function() return BHM.client:get_team_number() end))
    local player = select(2, pcall(function() return BHM.client:get_player_number() end))
    BHM.log_info('slot connected (team=' .. tostring(team) .. ', player=' .. tostring(player) .. ')')
end

local function on_slot_refused(reasons)
    BHM.connected = false
    BHM._refused = true -- backoff des tentatives (mauvais slot/mdp: inutile de spammer)
    BHM.log_warn('slot refused: ' .. tostring(reasons))
end

local function on_print_json(msg)
    -- Ne PAS appeler c:render_json ici : c'est un appel natif ré-entrant depuis
    -- un callback de la DLL (déclenché pendant c:poll()) et ça peut faire
    -- crasher le process (constaté sur la réponse à "!hint"). On loggue le
    -- JSON brut avec notre json.lua (pur Lua) à la place.
    if not BHM.json then return end
    local ok, raw = pcall(BHM.json.encode, msg)
    -- chat AP en debug: ne pas spammer la console Lovely à chaque message de la room
    if ok and raw and sendDebugMessage then sendDebugMessage('[BalatroHintMachine] chat: ' .. raw, 'HintMachineBridge') end
end

function BHM.connect()
    local s = BHM.settings
    if not s or not s.server or s.server == '' or not s.slot or s.slot == '' then
        BHM.log_warn('settings incomplete (server/slot empty), not connecting — edit ' .. SETTINGS_PATH)
        return false
    end
    if not BHM.load_ap_lib() then return false end
    BHM.last_attempt = love.timer.getTime()
    local ok, client = pcall(function() return BHM.AP('', s.game or '', s.server) end)
    if not ok or not client then
        BHM.log_error('cannot create APClient: ' .. tostring(client))
        return false
    end
    BHM.client = client
    BHM.connected = false
    client:set_socket_connected_handler(on_socket_connected)
    client:set_socket_error_handler(on_socket_error)
    client:set_socket_disconnected_handler(on_socket_disconnected)
    client:set_room_info_handler(on_room_info)
    client:set_slot_connected_handler(on_slot_connected)
    client:set_slot_refused_handler(on_slot_refused)
    client:set_print_json_handler(on_print_json)
    BHM.log_info('connecting to ' .. s.server .. ' as slot "' .. s.slot .. '" (tags HintGame, items_handling=0)')
    return true
end

-- Appelé à chaque frame via le wrapper de Game:update: poll du client + logique
-- de reconnexion throttlée.
function BHM.ap_tick()
    local c = BHM.client
    if c then
        pcall(function() c:poll() end)
    end
    local s = BHM.settings
    if not s or not s.server or s.server == '' or not s.slot or s.slot == '' then return end
    if BHM.connected then return end
    local now = love.timer.getTime()
    local base = tonumber(s.reconnect_interval) or 10
    -- backoff après un SlotRefused (mauvais slot/mdp): on espace les tentatives
    local interval = BHM._refused and math.min(base * 4, 120) or base
    if now - BHM.last_attempt < interval then return end
    -- ne reset pas un handshake en cours: si le socket est up et qu'un RoomInfo
    -- est arrivé il y a moins de 3x l'intervalle, on laisse le serveur répondre
    -- (Connected/Refused); au-delà, le handshake est considéré comme bloqué
    if c and not BHM._socket_down and now - BHM._room_info_at < base * 3 then return end
    BHM.last_attempt = now
    if c then
        -- reset() efface l'état réseau et reconnecte au prochain poll();
        -- les handlers restent en place, on_room_info renverra ConnectSlot.
        local ok, err = pcall(function() c:reset() end)
        if not ok then
            BHM.log_warn('reset failed (' .. tostring(err) .. '), recreating client')
            BHM.client = nil
            BHM.connect()
        end
    else
        BHM.connect()
    end
end

-- Wrapper chaîné de Game:update (coexistence BalatroAP: on appelle l'ancien d'abord).
local game_updateRef = Game.update
function Game:update(dt)
    local ret = game_updateRef(self, dt)
    local ok, err = pcall(BHM.ap_tick)
    if not ok then BHM.log_warn('ap_tick error: ' .. tostring(err)) end
    return ret
end

BHM.load_settings()
BHM.connect()
BHM.log_info('ap_client initialized')

--- STEAMODDED HEADER
--- MOD_NAME: BalatroHintMachine
--- MOD_ID: HintMachineBridge
--- MOD_AUTHOR: [HommeQuiParleAuxChevres]
--- MOD_DESCRIPTION: Local bridge between Balatro and the HintMachine app (Archipelago hint client). Writes a JSON snapshot of the game state to %AppData%/Roaming/Balatro/HintMachine/state.json, read by HintMachine's Balatro connector.
--- DISPLAY_NAME: BalatroHintMachine
--- PRIORITY: 0
--- DEPENDENCIES: [Steamodded>=1.0.0]
--- VERSION: 1.1.0
----------------------------------------------
------------MOD CODE --------------------------

-- BalatroHintMachine: pont local Balatro <-> HintMachine.
-- Lovely sandboxe os/io/package/require/loadstring: on n'utilise QUE l'API NFS
-- de Steamodded (working dir = %AppData%/Roaming/Balatro) et les globales du jeu.
-- Ce mod fonctionne seul; il coexiste avec BalatroAP s'il est installé (chacun
-- chaine ses propres wrappers, aucun champ global partagé).

local this_mod = SMODS.current_mod or (SMODS.Mods and SMODS.Mods['HintMachineBridge'])

local function mod_path(name)
    local p = (this_mod and this_mod.path) or ''
    if p:sub(-1) ~= '/' and p:sub(-1) ~= '\\' then p = p .. '/' end
    return p .. name
end

-- Namespace global du mod. Les compteurs sont initialisés ici: le mod n'est
-- chargé qu'une fois par lancement du jeu, donc ils repartent de zéro à chaque
-- lancement.
HintMachineBridge = {
    mod = this_mod,
    json = nil,
    seq = 0,
    counters = {
        boss_blinds_beaten = 0,
        runs_won = 0,
        hands_played = 0,
        jokers_bought = 0,
    },
}

-- json.lua (copié depuis BalatroAP, rxi/json.lua) fournit json.encode/decode.
local json_chunk = NFS.load(mod_path('json.lua'))
if not json_chunk then
    if sendErrorMessage then sendErrorMessage('[BalatroHintMachine] cannot load json.lua', 'HintMachineBridge') end
else
    HintMachineBridge.json = json_chunk()
end

-- Logique du pont (état, checksum, écriture throttlée, wrappers de hooks).
local bridge_chunk = NFS.load(mod_path('hintbridge.lua'))
if not bridge_chunk then
    if sendErrorMessage then sendErrorMessage('[BalatroHintMachine] cannot load hintbridge.lua', 'HintMachineBridge') end
else
    bridge_chunk()
end

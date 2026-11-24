# BalatroHintMachine

🇬🇧 English version (default): [README.md](README.md)

Mod [Steamodded](https://github.com/Steamodded/smods) pour **Balatro** (version Steam) qui est un
**client de hints Archipelago 100 % autonome**.
Le mod se connecte lui-même au serveur AP comme **slot dédié taggé `HintGame`**
et envoie des hints quand des quêtes in-game avancent.

## Principe

- Le mod charge `lua-apclientpp/` (DLL native copiée depuis
  [BalatroAP](https://github.com/BurndiL/BalatroAP)) et ouvre un
  websocket vers le serveur AP.
- Les hints d'un client taggé `HintGame` sont **gratuits** (aucun hint point ; seuls les hints
  demandés via la commande chat `!hint` sont payants) et apparaissent dans le chat / l'onglet
  Hints de la room. Le serveur ignore silencieusement les hints déjà existants.

## Installation

### 1. Installer Steamodded (Lovely)

1. Télécharger le dernier injecteur Lovely :
   <https://github.com/ethangreen-dev/lovely-injector/releases/latest> → asset
   `lovely-x86_64-pc-windows-msvc.zip`.
2. Extraire le zip : il contient `winmm.dll`.
3. Copier `winmm.dll` **à côté de `Balatro.exe`**, dans le dossier d'installation du jeu
   (ex `C:\SteamLibrary\steamapps\common\Balatro\`) : Steam → clic droit sur **Balatro** →
   *Propriétés* → *Fichiers installés* → *Parcourir*.

 Le mod est **Windows uniquement**.

### 2. Installer le mod

Copier le mod dans `%AppData%\Roaming\Balatro\Mods\` — trois options équivalentes :

- **Recommandé :** télécharger `BalatroHintMachine-vX.Y.Z.zip` dans les
  [Releases](../../releases) du repo (le zip contient déjà le dossier `BalatroHintMachine/` à sa
  racine, **avec `lua-apclientpp/` et sa DLL**), puis :
  ```powershell
  Expand-Archive BalatroHintMachine-vX.Y.Z.zip "$env:AppData\Roaming\Balatro\Mods\"
  ```
- **Manuellement :** copier le contenu de ce repo dans
  `%AppData%\Roaming\Balatro\Mods\BalatroHintMachine\` (le dossier doit contenir `main.lua`,
  `ap_client.lua`, `state.lua`, `quests.lua`, `json.lua`, `lua-apclientpp/`, `README.md`) :
  ```powershell
  Copy-Item -Recurse E:\Code\BalatroHintMachine\* "$env:AppData\Roaming\Balatro\Mods\BalatroHintMachine\"
  ```
- **Git :** `git clone <url-du-repo> "$env:AppData\Roaming\Balatro\Mods\BalatroHintMachine"`

Ne pas imbriquer : on veut `Mods\BalatroHintMachine\main.lua`, pas `Mods\BalatroHintMachine\BalatroHintMachine\main.lua`.

### 3. Activer le mod dans le jeu

1. Lancer Balatro.
2. Menu principal → **Mods** → activer **BalatroHintMachine** → quitter et relancer le jeu
   (les mods ne se chargent qu'au lancement).
3. Remplir la configuration (créée automatiquement au premier lancement) :
   `%AppData%\Roaming\Balatro\BalatroHintMachineSettings.json`
   ```json
   {
     "server": "localhost:38281",
     "slot": "BalatroHints",
     "password": "",
     "game": "",
     "hint_cooldown": 150,
     "reconnect_interval": 10
   }
   ```

   | Champ | Sémantique |
   |---|---|
   | `server` | `host:port` du serveur AP (ex `archipelago.gg:38281` ou `localhost:38281`). |
   | `slot` | Nom du slot dédié auquel le mod se connecte (voir § multiworld). |
   | `password` | Mot de passe de la room (`""` si aucun). |
   | `game` | Game envoyé dans le packet `Connect`. `""` = validation game/version skippée côté serveur (grâce au tag `HintGame`), le mod peut alors se connecter à n'importe quel slot. |
   | `hint_cooldown` | Cooldown global entre deux hints, en secondes (défaut **150**, soit ~1 hint / 2-3 min). |
   | `reconnect_interval` | Délai entre deux tentatives de reconnexion, en secondes (défaut 10). |

4. Relancer Balatro via Steam. Dans la console Lovely au lancement, chercher `[BalatroHintMachine]` :
   `lua-apclientpp loaded`, `connecting to <server> as slot "<slot>"`, puis `socket connected`,
   `room info received`, `slot connected (team=…, player=…)`.

## Côté multiworld (génération)

Le slot du mod est un **slot spectateur** ajouté à la génération, par ex. `BalatroHints` :

```yaml
# players/BalatroHints.yaml
description: Slot de hints Balatro
name: BalatroHints
game: Archipelago
Archipelago: {}
```

- **Un seul client par slot** : si [BalatroAP](https://github.com/BurndiL/BalatroAP) est connecté
  au slot Balatro, le mod de hints se connecte au slot spectateur `BalatroHints`, **pas** au slot
  Balatro (un second `Connect` sur le même slot éjecterait le premier client).
- Les hints envoyés sont gratuits (tag `HintGame`) et apparaissent dans le chat / l'onglet Hints
  de la room.

## Quêtes et cooldown

Déclencheurs suivis in-process (`state.lua`, wrappers chaînés de `Blind:defeat`,
`Game:update_game_over`, `Game:update`, `G.FUNCS.buy_from_shop`) :

| Quête | Valeur suivie | Seuils (un hint par seuil franchi) | Hors run ? |
|---|---|---|---|
| `boss_blinds_beaten` | boss blinds battus | 1, 2, 3, 4, 5, 6, 8, 10 | ignorée |
| `runs_won` | runs gagnés (fin de run uniquement) | 1, 2, 3 | évaluée partout (le compteur ne bouge qu'au game over) |
| `hands_played` | mains jouées | 10, 25, 50, 100, 200 | ignorée |
| `jokers_bought` | jokers achetés en shop | 3, 6, 10, 15 | ignorée |
| `ante_max` | ante max atteint | 2, 3, 4, 5, 6, 8 | ignorée |
| `chips_total` | chips cumulés (somme des deltas positifs de `G.GAME.chips`) | 1e6, 1e8, 1e10, 1e12, 1e15, 1e18, 1e21 | ignorée |

À chaque tick (~1 fois/s, wrapper de `Game:update`), si un seuil est franchi → `send_hint()`.
Un **cooldown global** (`hint_cooldown`, défaut 150 s) s'applique entre deux hints : si le
cooldown est actif, le seuil n'est pas consommé et sera réévalué au tick suivant. Aucun hint si
`missing_locations` est vide. 

## Désinstallation

- Supprimer `%AppData%\Roaming\Balatro\Mods\BalatroHintMachine\`.
- Supprimer `%AppData%\Roaming\Balatro\BalatroHintMachineSettings.json` si tu veux repartir de zéro.
- Supprimer `%AppData%\Roaming\Balatro\HintMachine\` (reste de la v1, plus utilisé).
- Supprimer `winmm.dll` du dossier d'installation de Balatro si tu ne veux plus aucun mod.

## IA générative

Une partie de ce mod (code, tests, documentation) a été développée avec l'aide d'un modèle
d'IA générative (Mistral). L'ensemble a été revu et testé manuellement.

## Licence

Voir `LICENSE`. `lua-apclientpp/` est distribué sous licence MIT (voir
`lua-apclientpp/lua-apclientpp-license.txt`, © black-sliver et contributeurs).

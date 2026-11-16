# BalatroHintMachine

Mod [Steamodded](https://github.com/Steamodded/smods) pour **Balatro** (version Steam) qui fait
**pont local** avec l'application **HintMachine** (client « BK Game » pour
[Archipelago](https://archipelago.gg), <https://github.com/HintMachine/hintMachine>).

Le seul rôle de ce mod est d'écrire un snapshot JSON de l'état du jeu dans un fichier que le
connecteur `Balatro` de HintMachine
(`HintMachine/Models/Games/BalatroConnector.cs`) surveille en permanence et à partir duquel
il alimente ses quêtes de hints. Le mod ne lit pas la RAM du jeu côté C# : toute la lecture se
fait ici, dans le jeu, via des wrappers Lua.

Le mod fonctionne **seul**. Il coexiste avec [BalatroAP](https://github.com/BurndiL/BalatroAP)
s'il est installé (chacun chaîne ses propres wrappers de `Game:update`, `Blind:defeat`, etc. ;
aucun état global partagé).

## Installation

### 1. Installer Steamodded (Lovely)

Sans Lovely, aucun mod ne tourne. Procédure validée (Windows, Balatro Steam) :

1. Télécharger le dernier injecteur Lovely :
   <https://github.com/ethangreen-dev/lovely-injector/releases/latest> → asset
   `lovely-x86_64-pc-windows-msvc.zip`.
2. Extraire le zip : il contient `winmm.dll`.
3. Copier `winmm.dll` **à côté de `Balatro.exe`**, dans le dossier d'installation du jeu
   (ex `F:\SteamLibrary\steamapps\common\Balatro\`). Pour trouver ce dossier :
   Steam → clic droit sur **Balatro** → *Propriétés* → *Fichiers installés* → *Parcourir*.
4. Vérifier : `winmm.dll` est bien présent à côté de `Balatro.exe`.

> Ne pas lancer `Balatro.exe` directement hors de Steam : le jeu quitte immédiatement
> (code d'erreur 2). Toujours lancer Balatro **via Steam** (bibliothèque ou raccourci Steam).

### 2. Installer le mod

Copier le mod dans `%AppData%\Roaming\Balatro\Mods\` — trois options équivalentes :

- **Recommandé :** télécharger `BalatroHintMachine-vX.Y.Z.zip` dans les
  [Releases](../../releases) du repo (le zip contient déjà le dossier
  `BalatroHintMachine/` à sa racine), puis :
  ```powershell
  Expand-Archive BalatroHintMachine-vX.Y.Z.zip "$env:AppData\Roaming\Balatro\Mods\"
  ```
- **Manuellement :** copier le contenu de ce repo dans
  `%AppData%\Roaming\Balatro\Mods\BalatroHintMachine\`
  (le dossier doit contenir `main.lua`, `hintbridge.lua`, `json.lua`, `README.md`) :
  ```powershell
  New-Item -ItemType Directory -Force "$env:AppData\Roaming\Balatro\Mods\BalatroHintMachine"
  Copy-Item E:\Code\BalatroHintMachine\*.lua, E:\Code\BalatroHintMachine\README.md, E:\Code\BalatroHintMachine\LICENSE "$env:AppData\Roaming\Balatro\Mods\BalatroHintMachine\"
  ```
- **Git :** `git clone <url-du-repo> "$env:AppData\Roaming\Balatro\Mods\BalatroHintMachine"`

Ne pas imbriquer : on veut `Mods\BalatroHintMachine\main.lua`, pas `Mods\BalatroHintMachine\BalatroHintMachine\main.lua`.

### 3. Activer le mod dans le jeu

1. Lancer Balatro **via Steam**.
2. Menu principal → **Mods** → activer **BalatroHintMachine** → quitter et relancer le jeu
   (les mods ne se chargent qu'au lancement).
3. Vérification immédiate : dès le menu principal, le mod écrit son premier état. Le fichier
   suivant doit exister :
   ```powershell
   Get-Content "$env:AppData\Roaming\Balatro\HintMachine\state.json"
   ```
   Contenu attendu (hors run) :
   ```json
   {"protocol":2,"seq":1,"in_run":false,"ante":0,"chips":"0","counters":{"boss_blinds_beaten":0,"runs_won":0,"hands_played":0,"jokers_bought":0},"checksum":NNN}
   ```
   Si le fichier n'existe pas : ouvrir la console Lovely au lancement du jeu et chercher une
   erreur `[BalatroHintMachine]`, et vérifier que le mod est bien coché dans le menu Mods.

### 4. Côté HintMachine

Lancer l'app, choisir le connecteur **« Balatro »** — il se connecte dès que le process
`Balatro` tourne et que le fichier d'état existe.

## Désinstallation

- Supprimer `winmm.dll` du dossier d'installation de Balatro (à côté de `Balatro.exe`).
- Supprimer `%AppData%\Roaming\Balatro\Mods\BalatroHintMachine\` et
  `%AppData%\Roaming\Balatro\HintMachine\`.

## Fichiers

```
BalatroHintMachine/
├── main.lua         -- header SMODS + chargement des autres fichiers via NFS.load
├── hintbridge.lua   -- logique du pont (état, checksum, écriture throttlée, hooks)
├── json.lua         -- encodeur/décodeur JSON (rxi/json.lua, copié depuis BalatroAP)
└── README.md        -- ce fichier (install + spec du protocole)
```

Contraintes Lovely : `os`, `io`, `package`, `require`, `loadstring` sont nil dans le sandbox.
Le mod utilise **uniquement** l'API **NFS** de Steamodded (`NFS.read/write/load/getInfo`,
`NFS.createDirectory`) — working directory = `%AppData%\Roaming\Balatro` — et les API `love.*`.
Aucun socket : pas de DLL C++ native.

`main.lua` :

```lua
--- STEAMODDED HEADER
--- MOD_NAME: BalatroHintMachine
--- MOD_ID: HintMachineBridge
--- PRIORITY: 0
--- DEPENDENCIES: [Steamodded>=1.0.0]
...
```

charge `json.lua` puis `hintbridge.lua` avec `NFS.load(SMODS.current_mod.path .. '<fichier>')()`
(pattern identique à BalatroAP).

## Protocole pont — version 2 (contrat avec `BalatroConnector.cs`)

### Fichier

```
%AppData%\Roaming\Balatro\HintMachine\state.json
```

Le mod crée le sous-dossier `HintMachine/` (`NFS.createDirectory('HintMachine')`) puis écrit
avec `NFS.write('HintMachine/state.json', payload)`.

### Schéma

```json
{
  "protocol": 2,
  "seq": 1284,
  "in_run": true,
  "ante": 3,
  "chips": "125000000",
  "counters": {
    "boss_blinds_beaten": 5,
    "runs_won": 1,
    "hands_played": 42,
    "jokers_bought": 6
  },
  "checksum": 9182
}
```

| Champ | Type | Sémantique |
|---|---|---|
| `protocol` | entier | Version du protocole, doit valoir **2** (`BRIDGE_PROTOCOL_VERSION`). |
| `seq` | entier | Incrémenté **à chaque écrit** ; le connecteur ignore tout `seq <=` dernier seq vu. |
| `in_run` | booléen | `G.STAGE == G.STAGES.RUN`. |
| `ante` | entier | `G.GAME.round_resets.ante`. |
| `chips` | **string** | `tostring(G.GAME.chips)` — string car c'est un double LuaJIT pouvant dépasser 2^53 (ex `"1e+20"`). |
| `counters.boss_blinds_beaten` | entier | Boss blinds battus (wrapper de `Blind:defeat()` quand `self.boss`). |
| `counters.runs_won` | entier | Runs gagnés (wrapper de `Game:update_game_over` + `G.GAME.won`). |
| `counters.hands_played` | entier | Mains jouées (diff de `G.GAME.current_round.hands_played`). |
| `counters.jokers_bought` | entier | Jokers achetés en shop (wrapper de `G.FUNCS.buy_from_shop`, cf. `functions/common_events.lua`). |
| `checksum` | entier | Voir ci-dessous. |

Les compteurs sont gardés **en mémoire** et remis à zéro au lancement du jeu (le mod n'est
chargé qu'une fois par process).

### Checksum (détection des lectures tronquées)

Le checksum est la **somme de tous les octets du payload excluant le champ `"checksum":N`
lui-même**. Construction exacte côté mod :

```
body    = json.encode(objet SANS checksum)     -- ex {"protocol":2,...,"counters":{...}}
checksum = somme des octets de body            -- objet complet, accolade finale incluse
payload = body sans '}' final .. ',"checksum":' .. checksum .. '}'
```

Le payload doit rester **ASCII** (les valeurs sont ASCII ; `json.lua` n'échappe que les
caractères de contrôle, et `chips` vient de `tostring(double)` donc toujours ASCII), donc
indice caractère == indice octet. Côté C#, le connecteur retire la sous-chaîne
`,"checksum"\s*:\s*\d+` du brut lu et somme tous les autres octets : il doit retrouver
`checksum`, sinon la lecture est ignorée (torn read).

### Politique d'écriture

- Depuis un **wrapper de `Game:update(dt)`**, à **~4 Hz max** (intervalle 0.25 s accumulé sur `dt`).
- **Seulement si le contenu a changé** : la signature (JSON de l'état avec `seq` fixé) est
  comparée à la dernière écrite ; si identique, rien n'est écrit et `seq` n'est pas incrémenté.
- Premier état écrit dès le chargement du mod (le connecteur exige que le fichier existe).

### Champs extraits (rappel de l'extraction)

- `in_run = (G.STAGE == G.STAGES.RUN)`
- `ante = G.GAME.round_resets.ante`
- `chips = tostring(G.GAME.chips)`
- `boss_blinds_beaten` : wrapper de `Blind:defeat(silent)` quand `self.boss`
- `runs_won` : wrapper de `Game:update_game_over(dt)`, incrémenté une fois par game over si `G.GAME.won`
- `hands_played` : à chaque frame, delta positif de `G.GAME.current_round.hands_played`
  (le champ retombe à 0 à chaque round, d'où le diff et non une lecture absolue)
- `jokers_bought` : wrapper de `G.FUNCS.buy_from_shop(e)` ; compte si `ret ~= false` et
  `e.config.ref_table.ability.set == 'Joker'`

## Tests

1. **Fichier présent dès le menu** : lancer Balatro via Steam avec le mod activé, puis :
   ```powershell
   Get-Content "$env:AppData\Roaming\Balatro\HintMachine\state.json"
   ```
   Le fichier existe et contient `"protocol":2`. Pendant une run, le suivre en boucle pour voir
   `seq` augmenter, `in_run: true`, `ante`/`chips`/`counters` cohérents (et `seq` stable quand
   rien ne change) :
   ```powershell
   while ($true) { Get-Content "$env:AppData\Roaming\Balatro\HintMachine\state.json"; Start-Sleep -Milliseconds 300; Clear-Host }
   ```
2. **Checksum valide** à chaque écrit :
   ```powershell
   $raw = Get-Content "$env:AppData\Roaming\Balatro\HintMachine\state.json" -Raw
   $body = $raw -replace ',"checksum":\d+', ''
   $expected = ([System.Text.Encoding]::ASCII.GetBytes($body) | Measure-Object -Sum).Sum
   $actual = [regex]::Match($raw, '"checksum":(\d+)').Groups[1].Value
   "attendu=$expected lu=$actual"   # les deux valeurs doivent être égales
   ```
3. **Compteurs en run** : battre un boss blind → `boss_blinds_beaten` +1 ; jouer une main →
   `hands_played` +1 ; acheter un joker au shop → `jokers_bought` +1 ; terminer une run
   gagnante → `runs_won` +1. Relancer Balatro → tous les compteurs repartent à 0.
4. **Robustesse** : supprimer `%AppData%\Roaming\Balatro\HintMachine\` en plein jeu → le mod
   recrée le dossier et le fichier à la prochaine écriture.
5. Côté HintMachine, connecteur **« Balatro »** : les quêtes (boss blinds battus, runs gagnés,
   mains jouées, jokers achetés, ante atteint, chips scorés) progressent et un hint apparaît
   quand une quête atteint son objectif.
6. Vérification unitaire du checksum côté C# : reconstruire le payload avec l'algorithme
   ci-dessus et comparer à la somme des octets hors champ `checksum` (cf. `TestHarness.cs` de HintMachine).

## Licence

Voir `LICENSE`.

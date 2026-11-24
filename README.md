# BalatroHintMachine

🇫🇷 French version: [README.fr.md](README.fr.md)

[Steamodded](https://github.com/Steamodded/smods) mod for **Balatro** (Steam version) that is a
**fully autonomous Archipelago hint client**.
The mod connects to the AP server by itself as a **dedicated slot tagged `HintGame`**
and sends hints as in-game quests progress.

## How it works

- The mod loads `lua-apclientpp/` (native DLL copied from
  [BalatroAP](https://github.com/BurndiL/BalatroAP)) and opens a websocket to the AP server.
- Hints from a `HintGame`-tagged client are **free** (no hint points; only hints requested via
  the `!hint` chat command cost points) and show up in the room chat / Hints tab. The server
  silently ignores hints that already exist.

## Installation

### 1. Install Steamodded (Lovely)

1. Download the latest Lovely injector:
   <https://github.com/ethangreen-dev/lovely-injector/releases/latest> → asset
   `lovely-x86_64-pc-windows-msvc.zip`.
2. Extract the zip: it contains `winmm.dll`.
3. Copy `winmm.dll` **next to `Balatro.exe`**, in the game's install folder
   (e.g. `C:\SteamLibrary\steamapps\common\Balatro\`): Steam → right-click **Balatro** →
   *Properties* → *Installed Files* → *Browse*.

The mod is **Windows only**.

### 2. Install the mod

Copy the mod into `%AppData%\Roaming\Balatro\Mods\` — three equivalent options:

- **Recommended:** download `BalatroHintMachine-vX.Y.Z.zip` from the repo's
  [Releases](../../releases) (the zip already contains the `BalatroHintMachine/` folder at its
  root, **with `lua-apclientpp/` and its DLL**), then:
  ```powershell
  Expand-Archive BalatroHintMachine-vX.Y.Z.zip "$env:AppData\Roaming\Balatro\Mods\"
  ```
- **Manually:** copy the contents of this repo into
  `%AppData%\Roaming\Balatro\Mods\BalatroHintMachine\` (the folder must contain `main.lua`,
  `ap_client.lua`, `state.lua`, `quests.lua`, `json.lua`, `lua-apclientpp/`, `README.md`):
  ```powershell
  Copy-Item -Recurse E:\Code\BalatroHintMachine\* "$env:AppData\Roaming\Balatro\Mods\BalatroHintMachine\"
  ```
- **Git:** `git clone <repo-url> "$env:AppData\Roaming\Balatro\Mods\BalatroHintMachine"`

Don't nest folders: you want `Mods\BalatroHintMachine\main.lua`, not
`Mods\BalatroHintMachine\BalatroHintMachine\main.lua`.

### 3. Enable the mod in-game

1. Launch Balatro.
2. Main menu → **Mods** → enable **BalatroHintMachine** → quit and relaunch the game
   (mods only load at launch).
3. Fill in the configuration (created automatically on first launch):
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

   | Field | Meaning |
   |---|---|
   | `server` | AP server `host:port` (e.g. `archipelago.gg:38281` or `localhost:38281`). |
   | `slot` | Name of the dedicated slot the mod connects to (see § multiworld). |
   | `password` | Room password (`""` if none). |
   | `game` | Game sent in the `Connect` packet. `""` = game/version validation skipped server-side (thanks to the `HintGame` tag), so the mod can connect to any slot. |
   | `hint_cooldown` | Global cooldown between two hints, in seconds (default **150**, i.e. ~1 hint / 2-3 min). |
   | `reconnect_interval` | Delay between two reconnection attempts, in seconds (default 10). |

4. Relaunch Balatro via Steam. In the Lovely console at launch, look for `[BalatroHintMachine]`:
   `lua-apclientpp loaded`, `connecting to <server> as slot "<slot>"`, then `socket connected`,
   `room info received`, `slot connected (team=…, player=…)`.

## Multiworld side (generation)

The mod's slot is a **spectator slot** added at generation time, e.g. `BalatroHints`:

```yaml
# players/BalatroHints.yaml
description: Balatro hints slot
name: BalatroHints
game: Archipelago
Archipelago: {}
```

- **One client per slot**: if [BalatroAP](https://github.com/BurndiL/BalatroAP) is connected
  to the Balatro slot, the hint mod connects to the spectator slot `BalatroHints`, **not** to the
  Balatro slot (a second `Connect` on the same slot would kick the first client).
- The hints sent are free (`HintGame` tag) and show up in the room chat / Hints tab.

## Quests and cooldown

Tracked triggers, in-process (`state.lua`, chained wrappers of `Blind:defeat`,
`Game:update_game_over`, `Game:update`, `G.FUNCS.buy_from_shop`):

| Quest | Tracked value | Thresholds (one hint per threshold crossed) | Outside a run? |
|---|---|---|---|
| `boss_blinds_beaten` | boss blinds beaten | 1, 2, 3, 4, 5, 6, 8, 10 | ignored |
| `runs_won` | runs won (end of run only) | 1, 2, 3 | evaluated everywhere (the counter only moves on game over) |
| `hands_played` | hands played | 10, 25, 50, 100, 200 | ignored |
| `jokers_bought` | jokers bought in the shop | 3, 6, 10, 15 | ignored |
| `ante_max` | max ante reached | 2, 3, 4, 5, 6, 8 | ignored |
| `chips_total` | total chips (sum of positive deltas of `G.GAME.chips`) | 1e6, 1e8, 1e10, 1e12, 1e15, 1e18, 1e21 | ignored |

On each tick (~1/s, wrapper of `Game:update`), if a threshold is crossed → `send_hint()`.
A **global cooldown** (`hint_cooldown`, default 150 s) applies between two hints: if the
cooldown is active, the threshold is not consumed and will be re-evaluated on the next tick.
No hint is sent if `missing_locations` is empty.

## Uninstall

- Delete `%AppData%\Roaming\Balatro\Mods\BalatroHintMachine\`.
- Delete `%AppData%\Roaming\Balatro\BalatroHintMachineSettings.json` if you want a clean slate.
- Delete `%AppData%\Roaming\Balatro\HintMachine\` (leftover from v1, no longer used).
- Delete `winmm.dll` from Balatro's install folder if you don't want any mods anymore.

## Generative AI

Part of this mod (code, tests, documentation) was developed with the help of a generative AI
model (Mistral). Everything was reviewed and tested manually.

## License

See `LICENSE`. `lua-apclientpp/` is distributed under the MIT license (see
`lua-apclientpp/lua-apclientpp-license.txt`, © black-sliver and contributors).

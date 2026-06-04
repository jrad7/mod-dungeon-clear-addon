# DungeonClear

A client-side World of Warcraft addon (patch **3.3.5a** / interface `30300`)
that drives and monitors the [`mod-dungeon-clear`][module] server module from an
in-game panel, instead of typing chat commands.

`mod-dungeon-clear` is an autonomous dungeon-clearing mode for **mod-playerbots**
tank bots: a tank bot walks the party from boss to boss, clearing trash, pathing
the dungeon, pausing for loot, and handling doors and stalls. This addon is the
front end for it. It is **optional**, everything it does is also reachable
through chat keywords (`dc on`, `dc skip`, ...) and the server's `.dc` command,
but it is the most convenient way to start a clear and watch its progress.

> **Server side required.** This addon only sends and receives addon messages.
> Nothing happens unless the `mod-dungeon-clear` module is installed on the
> server and a **mod-playerbots tank bot** is in your party. See the
> [module README][module] for server setup.

## Features

- **One-click control.** On / Off / Skip / Pause-Resume buttons drive the tank
  bot with no typing.
- **Live status readout.** Mode status (OFF / ON / PAUSED), the bot's current
  activity (Advancing, Clearing Trash, Boss Fight, Looting, Resting, Door
  Blocked, Route Blocked, Idle), the next boss target, and a warning line when
  the tank stalls.
- **Boss list.** Every boss in the dungeon with its status (Alive / Dead /
  Skipped / Missing) and a per-boss **Go** button that sends the tank straight
  to that boss. On isolated multi-wing maps (Dire Maul, Scarlet Monastery) the
  list is filtered to the bot's nearest wing. On connected multi-wing maps
  (Maraudon) every boss stays in the list, tagged with its region (Orange /
  Purple / Pristine Waters).
- **Tiny mode.** Collapse the window to a single-line, movable readout you can
  tuck into a corner of the screen and still click to control.
- **Silent.** All communication uses hidden addon messages. No party-chat spam;
  bot announcements are routed into your chat frame as tidy `[DC]` lines.
- **Self-healing.** The panel keeps polling status and re-requesting the boss
  list, so it fills in correctly through loading screens and the moment when the
  bot is not yet fully inside the instance.
- **Remembers its place.** Window position, tiny / folded state, and visibility
  persist between sessions via saved variables.

## Requirements

- WoW client **3.3.5a** (WotLK, interface `30300`).
- An AzerothCore server running [**`mod-dungeon-clear`**][module] with
  **mod-playerbots**.
- A playerbots **tank bot** in your party (a normal player bot, a random bot, or
  your own character running in self-bot mode).

## Installation

1. Download or clone this repository.
2. Copy the `DungeonClear` folder (containing `DungeonClear.toc` and
   `DungeonClear.lua`) into your client's add-on directory:

   ```
   World of Warcraft/Interface/AddOns/DungeonClear/
   ```

   The folder name must be `DungeonClear` so the client matches it to the
   `.toc`.
3. Launch the client and enable **DungeonClear** on the AddOns list at the
   character-selection screen (make sure "Load out of date AddOns" is checked if
   your client flags it).
4. Log in. You should see `DungeonClear Addon loaded. Type /dc to toggle window.`
   in your chat frame.

## Usage

Type **`/dc`** to toggle the window. You must be **in a party** (with a tank bot)
for the control buttons to do anything; the addon will tell you in chat if you
try to send a command while solo.

### Controls

| Control | Action |
|---|---|
| **On** | Turn dungeon clear on for the party's tank bot. |
| **Off** | Turn it off; non-tank bots revert to following you. |
| **Skip** | Skip the current boss / objective and move to the next. |
| **Pause / Resume** | Hold the tank in place without ending the clear, then resume. The button relabels itself and disables while DC is off. |
| **Go** (per boss row) | Send the tank to that specific boss (turning DC on first if needed). |
| **Tiny** | Collapse to the single-line readout. |
| **[-] / [+]** (next to "Dungeon Bosses") | Fold / unfold the boss list. |
| Close (X) | Hide the window (state is remembered). |

### Status panel

- **Mode Status**: `OFF` (grey), `ON` (green), or `PAUSED` (yellow).
- **Current State**: a human-readable description of what the tank is doing,
  color-coded (advancing = blue, trash = purple, boss = red, loot = orange,
  rest/pause = yellow, blocked = red).
- **Next Boss**: the boss the tank is currently heading for.
- **Warning**: appears only when the tank reports a stall, with the reason.

### Boss list

Each row shows the boss's ordinal position, name, and status:

| Status | Meaning |
|---|---|
| **Alive** | Boss is up. Has a **Go** button. |
| **Dead** | Already killed this run. No button. |
| **Skipped** | Skipped by the clear. Can still **Go** back to it. |
| **Missing** | Was seen alive but is no longer present (corpse despawned, grid unloaded, etc.). Can still **Go**. |

The list scrolls with the mouse wheel and refreshes itself on a steady cadence
so statuses stay current as the run progresses.

### Tiny mode

The **Tiny** button shrinks the window to a single line: a status dot, the
current state, and the target boss. While in tiny mode:

- **Left-click the dot** to start the clear (if off) or toggle pause/resume (if
  running).
- **Right-click anywhere on the bar** to expand back to the full window.
- **Left-drag** to reposition.

### Slash commands

| Command | Effect |
|---|---|
| `/dc` | Toggle the window (always reopens in full mode). |
| `/dc on` | Same as the **On** button. |
| `/dc off` | Same as the **Off** button. |
| `/dc skip` | Same as the **Skip** button. |
| `/dc pause` | Toggle pause/resume. |
| `/dc status` | Request a one-off status update. |
| `/dc bosses` | Request the boss list. |
| `/dc go <entry>` | Target the tank at the boss with that creature entry id. |

Any `/dc <sub> [param]` is forwarded verbatim to the server, so future
subcommands work without an addon update.

## How it works

The addon and the server module talk over a hidden addon-message channel using
the **`DC`** prefix on the **`PARTY`** distribution. Nothing appears in chat.

**Addon to server** (commands), tab-separated payloads:

```
CMD <tab> <sub> [<tab> <param>]
```

for example `CMD	on`, `CMD	skip`, `CMD	go	12397`. The server's
`DungeonClearAddonHook` intercepts these before normal chat processing and
dispatches them to the group's tank bot, exactly as if you had typed the `.dc`
command.

**Server to addon** (state), also tab-separated, parsed in `OnAddonMessage`:

| Message | Fields | Purpose |
|---|---|---|
| `STATUS` | `enabled`, `nextBossEntry`, `nextBossName`, `stallReason`, `skippedCount`, `state` | Drives the status panel and tiny readout. |
| `BOSS_START` | (none) | Begins a boss-list response; staged, not shown yet. |
| `BOSS` | `entry`, `index`, `name`, `status`, `x`, `y`, `z`, `wing` | One boss row. `wing` is a trailing, optional region label (empty on single-wing maps). |
| `BOSS_END` | (none) | Commits the staged list (sorted by encounter index). |
| `CHAT` | `message` | A bot announcement, printed as a `[DC]` chat line. |
| `ERROR` | `message` | An error (e.g. no tank bot in group); resets the UI to OFF. |

The boss list uses a staged "pending" buffer: a response is only committed on
`BOSS_END`, and only if it is non-empty. That keeps a good list **sticky**, a
transient empty reply (bot on a loading screen, a second tank bot not yet in the
instance, two tanks' responses interleaving) can never blank a list that already
loaded.

To stay current the addon polls on a timer while the window is open:

- `status` every ~2s while a clear is running.
- the boss list every 2s while it is still empty (fast fill on zone-in), then
  every 5s once populated (gentle status refresh), gated to 5-man instances.

It also auto-requests the boss list shortly after entering a party dungeon and
pushes a status update when combat starts or ends.

## Saved variables

State is stored in `DungeonClearDB`:

| Key | Meaning |
|---|---|
| `visible` | Whether the window is shown. |
| `point`, `relativePoint`, `xOfs`, `yOfs` | Window position. |
| `tinyMode` | Collapsed single-line mode. |
| `bossesFolded` | Boss list folded shut. |

## Troubleshooting

- **Buttons do nothing / "You must be in a party" message.** You need a party
  that contains a mod-playerbots tank bot. The addon only relays commands.
- **Boss list stuck on "Loading boss list...".** The bot is not yet fully inside
  the instance, or there is no tank bot in the group. The addon keeps retrying;
  it fills in once the server returns a list. If it never does, confirm the
  server has `mod-dungeon-clear` installed and a tank bot present.
- **"Tank bot is no longer in the group" and DC flips to OFF.** The tank bot left
  the party or logged out. Re-add a tank bot and press **On** again.
- **Nothing happens on `On`, but `.dc on` works.** The `dungeon clear` strategy
  is not applied to that bot. See the [module README][module] for the
  `AiPlayerbot.NonCombatStrategies = "+dungeon clear"` config that reaches
  self-bots and random bots.
- **You can't drive the tank if you are personally playing it.** Dungeon clear
  controls the tank *bot's* AI, so the tank has to be a bot. The exception is
  self-bot mode (`.playerbots bot self`). See the module README for details.

## License

AGPL-3.0-or-later, inherited from mod-playerbots / mod-dungeon-clear.

[module]: https://github.com/jrad7/mod-dungeon-clear
</content>

# DungeonClear

> ## ⚠️ The AddOns folder **must** be named `DungeonClear`
>
> Cloning or downloading this repo gives you a folder named
> `mod-dungeon-clear-addon`. The client will **not** load it under that name —
> the folder inside `Interface/AddOns/` has to be exactly `DungeonClear` (with
> `DungeonClear.toc` and `DungeonClear.lua` directly inside it). Rename it after
> copying. See [Installation](#installation) below.

A simple in-game panel for **World of Warcraft 3.3.5a** that lets you send a
party's bot tank through a dungeon and watch its progress, instead of typing
chat commands.

It is the front end for the [`mod-dungeon-clear`][module] server module, which
turns a **mod-playerbots** tank bot into an autonomous dungeon clearer: the tank
walks your party boss to boss, clears trash, paths around the dungeon, pauses
for loot, opens doors, and recovers from stalls. With this addon you just press
**On** and watch.

> **You need the server side too.** This addon does nothing on its own. The
> `mod-dungeon-clear` module must be installed on the server, and you need a
> mod-playerbots **tank bot** in your party. See the [module README][module] for
> server setup.

## What it does for you

- **One-click control.** On / Off / Skip / Pause buttons run the whole clear, no
  typing required.
- **See what the tank is doing.** A live status line tells you whether the tank
  is advancing, clearing trash, fighting a boss, looting, resting, or stuck on a
  door or blocked path — and which boss it's heading for next.
- **Jump to any boss.** The dungeon's bosses are listed with their status
  (Alive / Dead / Skipped / Missing). Press **Go** on any boss to send the tank
  straight to it.
- **Get out of the way.** Collapse the panel to a tiny one-line readout you can
  tuck in a corner and still click to control.
- **No chat spam.** Everything happens quietly; the tank's announcements show up
  as tidy `[DC]` lines in your chat frame.
- **Your own settings.** A **Settings** page lets you override the server's
  defaults (loot quality, boss engage ranges, party spread, and more) for your
  own runs — see below.
- **Remembers your setup.** Window position, size, and your settings stick
  between sessions.

## Requirements

- WoW client **3.3.5a** (Wrath of the Lich King).
- An AzerothCore server running [**`mod-dungeon-clear`**][module] with
  **mod-playerbots**.
- A playerbots **tank bot** in your party — a normal bot, a random bot, or your
  own character running in self-bot mode.

## Installation

1. Download or clone this repository.
2. Copy the `DungeonClear` folder (with `DungeonClear.toc` and `DungeonClear.lua`
   inside it) into your client's add-on directory:

   ```
   World of Warcraft/Interface/AddOns/DungeonClear/
   ```

   The folder must be named `DungeonClear`.
3. Launch the client and enable **DungeonClear** on the AddOns list at the
   character-select screen (tick "Load out of date AddOns" if the client asks).
4. Log in. You'll see `DungeonClear Addon loaded. Type /dc to toggle window.` in
   your chat frame.

## Using it

Type **`/dc`** to open or close the panel. You need to be **in a party with a
tank bot** for the buttons to do anything — the addon will tell you in chat if
you try while solo.

### Buttons

| Button | What it does |
|---|---|
| **On** | Start the dungeon clear for your party's tank bot. |
| **Off** | Stop it; other bots go back to following you. |
| **Skip** | Skip the current boss or objective and move on. |
| **Pause / Resume** | Hold the tank in place without ending the run, then let it carry on. |
| **Go** (on a boss row) | Send the tank to that boss (starts the clear if it isn't already on). |
| **Tiny** | Shrink the panel to a single line. |
| Close (X) | Hide the window. |

### Pull modes

A pull control on the panel chooses how the tank takes trash packs on the way to
each boss:

| Mode | Behaviour |
|---|---|
| **Dynamic** *(default)* | Decide per pack — Leeroy a lone pack, Advanced-pull a clustered or oversized one. |
| **Leeroy** *(pull off)* | Walk straight into each pack and fight it in place. Fast, but no safety margin. |
| **Advanced** *(pull on)* | Pull every pack back to a held camp before fighting it. Careful, but slow. |

**Leave it on Dynamic for almost every dungeon.** It's the default: it Leeroys the
easy packs at full speed and only pays the camp-setup/tag/drag-back cost on the
packs that need it — the big or tightly stacked ones that would wipe the party
fought in place. The status line shows which choice Dynamic made for the current
pack. Drop to pure **Leeroy** in easy content you out-gear (every pull is fast,
nothing is staged), or force **Advanced** in hard content and raids where every
pack should be taken one controlled group at a time.

You can set the pull mode **before** starting the clear — pick it and it takes
effect the moment you press **On**. While the clear is stopped the control is dimmed
to show the choice is pending rather than live. Pull mode is per-run and resets to
Dynamic when you stop.

### Reading the status

- **Mode**: `OFF`, `ON`, or `PAUSED`.
- **Current activity**: a plain-language description of what the tank is doing,
  color-coded so you can read it at a glance.
- **Next Boss**: where the tank is headed.
- **Warning**: shows up only if the tank gets stuck, with the reason.

### The boss list

Every boss in the dungeon, with its status:

| Status | Meaning |
|---|---|
| **Alive** | Still up — press **Go** to head there. |
| **Dead** | Killed this run. |
| **Skipped** | Skipped, but you can still **Go** back to it. |
| **Missing** | Was alive but isn't around anymore (corpse gone, etc.). Still has **Go**. |

On dungeons split into separate wings (Dire Maul, Scarlet Monastery) the list
shows just the wing your bot is in. On connected dungeons (Maraudon) every boss
stays listed, tagged with its area (Orange / Purple / Pristine Waters).

### Tiny mode

The **Tiny** button shrinks everything to one line — a status dot, a pull-mode
dot with its label, the current activity, and the target boss. While tiny:

- **Left-click the status dot** to start the clear, or pause/resume if running.
- **Left-click the pull dot** to cycle the pull mode (Off → On → Dynamic). Its
  colour and the label beside it (e.g. `Dyn: Leeroy`) track the live state.
- **Right-click the bar** to expand back to the full window.
- **Drag** to move it.

### Settings (your own per-run overrides)

The server ships sensible defaults for things like minimum loot quality, how far
the tank may lead the party, and how close it gets before pulling a boss. You can
override any of these **for your own dungeon runs** without changing the server
config:

1. Open **Game Menu → Interface → AddOns → DungeonClear → Settings** (the sub-page
   under DungeonClear).
2. Adjust the sliders / checkboxes. Each change applies immediately to your
   current run.
3. **Default** next to a setting reverts just that one to the server value;
   **Reset All to Default** clears everything you've changed.

Your overrides are **saved per character** and re-applied automatically whenever
you start a clear or enter a dungeon, so you set them once and forget them. They
only affect runs led by a tank bot in *your* party — they never change the server
default for anyone else. You need to be in a party with a tank bot for the page to
show live values (otherwise it shows your saved choices and applies them next time
a tank is available).

The list of available settings comes from the server, so if a future module
version adds a tunable it appears here automatically.

### Slash commands

If you'd rather type, every button has a command:

| Command | Same as |
|---|---|
| `/dc` | Open / close the window. |
| `/dc on` | **On** |
| `/dc off` | **Off** |
| `/dc skip` | **Skip** |
| `/dc pause` | **Pause / Resume** |
| `/dc status` | Refresh the status line. |
| `/dc bosses` | Refresh the boss list. |
| `/dc go <entry>` | Send the tank to a boss by its creature id. |

## Troubleshooting

- **Buttons do nothing / "You must be in a party."** You need a party with a
  mod-playerbots tank bot in it. The addon only relays your commands to that bot.
- **Boss list stuck on "Loading boss list...".** The tank isn't fully inside the
  instance yet, or there's no tank bot in the group. It fills in on its own once
  the server responds. If it never does, check that the server has
  `mod-dungeon-clear` installed and a tank bot present.
- **"Tank bot is no longer in the group" and it flips to OFF.** The tank bot left
  or logged out. Add one back and press **On** again.
- **`On` does nothing, but `.dc on` works in chat.** The `dungeon clear` strategy
  isn't applied to that bot. See the [module README][module] for the config that
  fixes this.
- **You can't drive the tank if you're playing it yourself.** Dungeon clear
  controls a tank *bot*, so the tank has to be a bot — or your own character in
  self-bot mode. See the module README.

## License

AGPL-3.0-or-later, inherited from mod-playerbots / mod-dungeon-clear.

[module]: https://github.com/jrad7/mod-dungeon-clear

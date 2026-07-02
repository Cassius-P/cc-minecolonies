# MineColonies Dashboard

A live control panel for your MineColonies colony, shown on in-game monitors and
driven by an Advanced Computer. See at a glance how your colony is doing, who
should be working where, and let it auto-fill your colonists' item requests from
an ME/RS storage system.

![built with Basalt](https://img.shields.io/badge/UI-Basalt%202-blue)

## What it shows

- **Colony status** — happiness, population, threats, construction, graves.
- **Workforce** — citizen, employed, idle, visitor and building counts.
- **Workers** — every job building and its workers. Each worker is tagged
  `ok`, or `replace w/ X` when a better idle colonist exists; empty slots show
  `+ assign X`. Tap `[DO]` for exact hire steps and coordinates.
- **Open requests** — what your colonists need, auto-filled from storage when a
  bridge is connected (see below). Colors show progress (Legend section decodes
  them).
- **Work orders** — what your builders have queued.

## What you need

- An **Advanced Computer** (gold) and at least one **Advanced Monitor**.
- An **Advanced Peripherals "Colony Integrator"**, placed inside your colony,
  connected to the computer (touching it, or over a wired-modem network).
- *Optional, for auto-fill:* an **ME Bridge** or **RS Bridge** plus a
  **warehouse/inventory** on the same network.

## Install

On the Advanced Computer, type:

```
wget https://raw.githubusercontent.com/Cassius-P/cc-minecolonies/main/install.lua install.lua
install.lua
reboot
```

After the reboot the dashboard starts on its own and draws to your monitors.
(Hold any key during the 2-second boot message to skip auto-start.)

**To update later** — press **Install / update now** on the computer's *Update*
tab, or type `update` at the shell:

```
update
```

Either way it pulls the latest from GitHub and reboots. Your settings and any
changes to `config.lua` are kept. The *Update* tab shows the installed version
and whether a newer one is available (checked hourly).

**To uninstall** — remove everything (files, settings, boot auto-launch):

```
uninstall
```

## Using it

Everything is touch-driven on the monitor, plus a few keys on the computer.

**Buttons along the bottom of each monitor:**

| Button | Does |
|--------|------|
| `THEME` | Switch color theme (applies to every monitor) |
| `SECTIONS` | Show/hide sections on this monitor |
| `EDIT` | Rearrange: each section shows `▲ ▼` (move up/down in its column) and `▶`/`◀` (send to the other column) |

The screen is **two columns**. A column's width is shared by however many
columns have sections (empty a column and the other fills the whole screen);
within a column, each section splits the height evenly — so size follows how
many sections are where, with nothing to resize by hand. In EDIT mode use a
section's `▲ ▼` to reorder it and `▶`/`◀` to move it between columns (that's how
you fill a second column, or collapse to one). Changes save per monitor and
survive updates.

> Note: Minecraft monitors only report taps — no click-drag and no scroll wheel
> — so moving is done with these buttons rather than drag-and-drop.

**Keys on the computer screen:**

`r` rescan · `t` theme · `1`-`9` change which layout a monitor uses · `q` quit.

**Multiple monitors:** connect as many as you like. The first gets a full
overview; extra monitors show a logistics view. Touch works on every monitor,
including ones connected through a wired modem.

## Auto-filling requests

Connect an ME or RS **bridge** and a **warehouse inventory**, and the dashboard
exports requested items to the warehouse and queues crafts for anything missing.
The Open Requests header shows the mode:

- `AUTO` — filling automatically
- `MANUAL` — no auto-fill (no bridge/storage found)
- `PAUSED …` — held back by a rule you set (e.g. colony under attack)
- `no bridge` — connect a bridge to enable it

Tune the rules in `config.lua` under `autofulfill` (pause when raided, minimum
happiness, whether to craft missing items, equipment tier to craft, items to
skip).

## Settings

Open `config.lua` on the computer (it's kept safe across updates). Common tweaks:

- `theme` — starting color theme.
- `refreshSeconds` — how often to re-scan.
- `screens` — per monitor: `enabled` (which sections show) and `columns` (the
  two ordered lists of sections). Extra monitors reuse the last screen's layout.
- `autofulfill` — the storage rules above.
- `peripherals` — usually leave blank; set a device's network name here only if
  you have several and want to pick a specific one. The computer screen lists
  every connected device's name to copy from.

## Troubleshooting

- **"No colony_integrator found"** — the integrator must be inside the colony and
  connected to the computer (adjacent, or on a wired-modem network with the modem
  enabled).
- **"No monitor found"** — attach an Advanced Monitor (directly or via modem).
- **Nothing auto-fills** — check the Open Requests mode; `no bridge` means the
  bridge or warehouse isn't detected. The computer screen's peripheral list shows
  what it can see.
- **A section looks cramped** — it shares its column's height with the other
  sections there; hide some with `SECTIONS`, or move sections to the other
  column in `EDIT` so each has more room. Long lists scroll (tap the ▲▼ in the
  section's title bar; the mouse wheel also works on the computer screen).

## Notes

- Built on the [Basalt 2](https://github.com/Pyroxenium/Basalt2) UI framework
  (bundled — no separate install) with a color scheme from
  [cc-mek-scada](https://github.com/MikaylaFischler/cc-mek-scada).
- Assigning colonists stays manual: the Colony Integrator is read-only, so `[DO]`
  gives you the steps rather than doing the hire for you.
- Republishing your own copy? Point `REPO` at the top of `install.lua` and
  `update.lua` to your GitHub fork.
- Developer docs (module layout, internals) live in the source under `src/`.

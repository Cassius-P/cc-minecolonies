# cc-minecolonies

A modular [CC:Tweaked](https://tweaked.cc/) dashboard for MineColonies via the
Advanced Peripherals `colony_integrator`. Built on the
[Basalt 2](https://github.com/Pyroxenium/Basalt2) UI framework, with an
architecture modeled on [cc-mek-scada](https://github.com/MikaylaFischler/cc-mek-scada)
(shared `common/`, split `colony/` `storage/` `ui/` layers) and a GitHub-based
install/update flow.

## Install (in-game)

The dashboard installs from this public GitHub repo. Set `REPO` at the top of
`install.lua`/`update.lua` to your fork if you republish it.

```
wget https://raw.githubusercontent.com/Cassius-P/cc-minecolonies/main/install.lua install.lua
install.lua
reboot
```

`install.lua` fetches `manifest.lua` and every file it lists, writes them to the
computer root, vendors Basalt, and installs `startup.lua` so the dashboard
auto-launches on boot (hold a key within 2s at boot to cancel).

**Update** (keeps your `config.lua` and saved settings):

```
update
```

`update.lua` re-downloads `install.lua` and runs it in update mode. Only
`config.lua` is preserved; everything else is overwritten to the pinned version.

## Architecture

```
install.lua / update.lua / manifest.lua   GitHub install + update flow
vendor/basalt.lua                          pinned Basalt 2 (full build)
src/
  startup.lua        auto-launch on boot (+ cancel key, crash guard)
  main.lua           entry: package.path + app.start(config)
  config.lua         default config (theme, screens, autofulfill, peripherals)
  common/            util, log, peripherals (modem-aware), settings
  colony/            skills, advisor (suggestions+roster), requests, api (scan)
  storage/           fulfill (CCxM auto-fulfill core)
  ui/                theme, draw (primitives), layout (engine+modals),
                     terminal, app; sections/ (status, workforce, workers,
                     orders, requests, legend)
legacy/              previous monolithic scripts (not installed)
tools/               colony_dump.lua, pastebin_up.lua (dev helpers)
```

Each module returns a table and is required by dotted path (`require("colony.api")`);
`main.lua` puts the install root on `package.path`.

## Features

- **Multi-monitor** (`config.screens`): one entry per monitor, each with its own
  layout + enabled sections. Screens bind to monitors in detection order, or pin
  a monitor by network name with `monitor="..."`. Basalt binds each frame to its
  monitor and routes `monitor_touch` to the right screen natively, so touch works
  on every monitor (adjacent or over a wired modem). A single monitor uses
  `screens[1]` (keep it self-sufficient); extra monitors clone the last screen.
- **Flexbox-like layout**: a tree of `row`/`col` containers and section leaves,
  each with `flex` / `min` / `max`. On a monitor too small for all mins, sections
  shrink but never vanish. **EDIT** button on the monitor: `- +` resize, `up/down`
  reorder; **SECTIONS** button toggles visibility. Both persist per monitor.
- **Workers** section = full roster: every job building + its workers, each
  tagged `ok` or `replace w/ X`, plus `+ assign X` / `+ (empty)` for open slots.
  `[DO]` opens the manual-hire card (`colony_integrator` is read-only, so
  assignment stays manual).
- **Themes**: all four cc-mek-scada palettes (`deepslate`, `smooth_stone`,
  `sandstone`, `basalt`). Global — the `THEME` button repaints every monitor.
  Theme + per-monitor sections/layout persist to `colony_dashboard.settings`.
- **Requests + CCxM auto-fulfill**: with an ME/RS bridge + warehouse inventory,
  colony requests auto-export and missing craftables queue. Gated by
  `config.autofulfill` (`pauseUnderAttack`, `minHappiness`, `craftMissing`,
  `equipment`, `equipmentLevel`, `skipItems`). Header shows the mode
  (`AUTO` / `MANUAL` / `PAUSED …` / `no bridge`); the Legend section decodes the
  row colors.
- **Computer terminal**: live colony vitals, workers-to-place, request/fulfill
  mode, monitor assignments, and a **peripheral network map** (name : type) to
  identify remotes. Keys: `r` rescan, `t` theme, `1`-`9` reassign a monitor's
  screen, `q` quit.

## Remote peripherals (wired modem)

Discovery is by type/network-name (`peripheral.find` / `getNames`), which
traverse a wired-modem network transparently — the colony integrator, ME/RS
bridge, warehouse inventory, and monitors can live anywhere on the network. To
pin a specific remote when several exist, set its network name in
`config.peripherals` (`colony`, `bridge`, `storage`, `monitors`); the terminal's
peripheral map lists the available names. The bridge exports to the warehouse by
network name, so auto-fulfill works with a remote inventory too. (Cross-computer
wireless `rednet` is out of scope — this is about reaching peripherals, not other
computers.)

## Configuration

Edit `config.lua` on the computer (preserved across updates). Key fields: `theme`,
`refreshSeconds`, `peripherals` overrides, `screens` (per-monitor layout + enabled
sections), `autofulfill`, `logToFile`.

## Notes

- Field mappings are verified against a live dump of `getCitizens()` /
  `getBuildings()`; `JOB_SKILLS` in `colony/skills.lua` is wiki-verified config
  (the API does not expose per-building worker capacity or exact skills).
- Basalt is vendored (`vendor/basalt.lua`) and pinned for reproducible installs.
- `tools/colony_dump.lua` dumps the live API to paste.rs; `tools/pastebin_up.lua`
  uploads any on-computer file.

# cc-minecolonies

CC:Tweaked scripts for MineColonies via Advanced Peripherals `colony_integrator`.

Shared UI system: SCADA-style cards with the **deepslate** palette from
[cc-mek-scada](https://github.com/MikaylaFischler/cc-mek-scada) (`graphics/themes.lua`),
applied with `setPaletteColour`. `colors.brown` is repurposed as the dark card body.

## Scripts

### `colony_dashboard.lua`  (main)

Configurable all-in-one dashboard. Supersedes `colony_advisor.lua` +
`ccxm_requests.lua` by merging both into one screen.

- **Flexbox layout** (`CONFIG.layout`): a tree of `row`/`col` containers and
  section leaves. Each node takes `flex` (main-axis weight), `min`, `max`
  (main-axis clamp in cells); the cross axis fills. Reorder children to move a
  section, change `flex`/`min`/`max` to resize.
- **Enable/disable** sections via `CONFIG.enabled` or the on-screen `SECTIONS`
  button; disabled sections drop out and their space is redistributed.
- **Themes**: all four cc-mek-scada palettes (`deepslate`, `smooth_stone`,
  `sandstone`, `basalt`), set in `CONFIG.theme` or cycled with the `THEME` button.
- **Sections**: status, workforce, suggestions, orders, requests, legend.
- **Requests section = CCxM auto-fulfill**: with an ME/RS bridge + inventory,
  colony requests auto-export to the warehouse and missing craftables queue.
  Gated by `CONFIG.autofulfill` constraints:
  `pauseUnderAttack`, `minHappiness`, `craftMissing`, `equipment`,
  `equipmentLevel`, `skipItems`. Header shows mode: `AUTO` / `MANUAL` /
  `PAUSED …` / `no bridge`.

Requires: `colony_integrator`, advanced (touch) monitor. Optional: ME/RS bridge
+ inventory for auto-fulfill.

### `colony_advisor.lua`  (legacy)

Citizen-job advisor dashboard.

- Scores idle citizens against each job's primary/secondary skills
- Suggests **Assign X -> Job** (open slot) or **Swap Y -> X** (full, stronger candidate)
- Sections: colony status (happiness/population/threat), workforce, work orders,
  open requests, scrollable suggestions
- Touch: `[DO]` opens an apply card with manual hire steps + coords,
  `[HANDLED]`, `[RESCAN]`, `[QUIT]`

> The `colony_integrator` API is read-only: assignment stays manual (hut GUI ->
> Hire/Fire). `tryApiAssign()` is the hook point if AP ever adds an assign method.

Requires: `colony_integrator`, advanced (touch) monitor.

### `ccxm_requests.lua`

"Ultimate CC x MineColonies" request fulfiller (v1.15), UI reworked to the same
card system. All original features kept:

- Auto-exports colony requests from an ME/RS bridge to a storage/warehouse,
  queues crafts, tracks crafting status
- Equipment level parsing (`craftEquipmentOfLevel`), skip-list, domum ornamentum
  handling, log rotation, terminal requirements checker
- Cards: builder / equipment / other requests (scrollable) + color-code legend
- Color code: red missing, yellow stuck/partial, blue crafting, green exported,
  light blue domum, gray skipped

Requires: `colony_integrator`, ME or RS bridge, adjacent inventory, 4x3+ advanced monitor.

## Install (in-game)

```
wget <paste.rs link> colony_advisor.lua
colony_advisor
```

Upload helper (any file -> paste.rs link): see `pastebin_up.lua`.

## Notes

- Field mappings verified against a live dump of `getCitizens()` / `getBuildings()`
  (MC 1.20, MineColonies + Advanced Peripherals)
- `JOB_SKILLS` / `JOB_MAX_SLOTS` in `colony_advisor.lua` are config: the API does
  not expose per-building worker capacity

# UI Redesign Prompt — cc-minecolonies (Admin View + Monitor Dashboard)

Use this as the complete brief to redesign the UI of this project. It specifies
the two surfaces, the exact data available, the UI framework, and every
CC:Tweaked / Basalt constraint. Nothing outside this file is required to design.

---

## 1. Goal

Redesign the visual design and UX of both UI surfaces of a MineColonies
management program that runs on a ComputerCraft: Tweaked **Advanced Computer**:

- **Admin View** — the UI on the computer's *own* screen (fixed 51×19 chars).
  Configuration + status + updates. Full keyboard + mouse.
- **Dashboard** — the UI drawn on one or more **Advanced Monitors** (variable
  size). Read-at-a-glance colony status. **Touch only.**

Keep all existing features and data; improve layout, clarity, information
density, color use, and interaction. Do not change the data layer or the
colony/game logic — only the presentation and interaction.

---

## 2. Platform constraints (CC:Tweaked) — HARD RULES

- **Language**: Lua 5.1/5.2 (Cobalt). `goto` is available. `os.epoch("utc")`
  exists; `os.time()` is in-game ticks. No real filesystem beyond CC `fs`.
- **Display model**: text grid of characters. **16 colors only** (a palette of
  16 indices). Each palette index is remappable per-terminal via
  `term.setPaletteColour(idx, hex)` / `monitor.setPaletteColour(...)`. Each cell
  has 1 char + 1 fg color + 1 bg color (`blit`). No pixels, no partial
  transparency, no arbitrary fonts. Font is fixed 6×9-ish; monitors can only
  change *text scale* (0.5–5), which changes how many chars fit.
- **Glyphs**: CraftOS extended char set (CP437-like). Useful: `\7` bullet `•`,
  arrows `\24`↑ `\25`↓ `\26`→ `\27`←, block `\127`, etc. No emoji, no unicode.
- **Advanced Computer terminal**: fixed **51×19** characters. Receives
  `mouse_click`, `mouse_up`, `mouse_drag`, `mouse_scroll`, `key`, `char`, `paste`.
- **Advanced Monitors**: size varies (W×H depends on block dimensions × text
  scale). **They ONLY emit `monitor_touch` (a single tap).** NO drag, NO scroll
  wheel, NO hover, NO right-click, NO keyboard. Any monitor interaction must be a
  single tap on a target region. Multiple monitors can be connected (directly or
  over a wired-modem network); each is addressed by its peripheral network name.
- **Concurrency**: single-threaded coroutines only. Long ops (`http`, `sleep`)
  yield to the event loop. No real threads.
- **The colony data source is READ-ONLY** (Advanced Peripherals
  `colony_integrator`): the program cannot assign/hire/move colonists. Any
  "action" the UI offers must be **instructions to the player** (e.g. "go to
  X, open the hut GUI, hire Y"), not an automated change.

---

## 3. UI framework — Basalt 2 (vendored)

Use **Basalt 2** (`require("basalt")`, vendored at `/basalt.lua`). Available
elements/features (this pinned build):

- Containers: `BaseFrame`, `Frame`, `Container`, `TabControl` (`:newTab(name)`
  returns a tab container).
- Widgets: `Button`, `Label`, `Input` (single-line text; `text` property,
  `placeholder`, `:onChange("text", fn)`), `TextBox` (multi-line; `editable`),
  `List`, `Table`, `Menu`, `Display` (raw canvas: `:getWindow()` returns a real
  CC `window` you can `blit`/`write`/`setCursorPos` into), `LineChart`/`BarChart`.
- Layout is **absolute**: every element takes `{x, y, width, height}`. **There is
  NO flexbox / auto-layout** — compute positions yourself.
- Element API: `el:setSize(w,h)`, `el:setPosition(x,y)`, `el.set("prop", v)`,
  `el.get("prop")`, `el:setText`, `el:setForeground`, `el:setBackground`.
  Events: `:onClick(fn)`, `:onScroll(fn)`, `:onChange(prop, fn)`, `:onKey`.
  A `Frame` has a `draggable` property (drags its top row).
- App: `basalt.getMainFrame()` (frame bound to the computer term),
  `basalt.createFrame()` + `frame.set("term", monitorPeripheral)` to bind a frame
  to a monitor, `basalt.run()` (one call), `basalt.schedule(fn)` (coroutine loop),
  `basalt.onEvent(name, fn)` (global event hook).

### Basalt gotchas (LEARNED THE HARD WAY — respect these)

1. **Monitors emit only `monitor_touch`** → Basalt drag-to-move and wheel-scroll
   CANNOT work on a monitor. On monitors, scrolling and moving must be **tap
   buttons** (e.g. ▲/▼ arrows). A frame bound to a monitor DOES convert
   `monitor_touch` into a click for hit-testing.
2. **Basalt tab-content buttons do not reliably receive clicks in-world.** Always
   provide a **keyboard shortcut** equivalent (via `basalt.onEvent("char", ...)`)
   for every important action in the admin view. Guard those global shortcuts
   while an `Input`/`TextBox` is focused (`basalt.getFocus()`), so typing a
   number doesn't trigger a shortcut.
3. **Re-rendering every tick causes visible lag** (esp. it disturbs `Input`
   typing). Only write a widget when its value actually changed (diff
   setText/setForeground against a cache). Never do heavy work (colony re-scan,
   file writes) inside an input `onChange`; debounce to the next tick.
4. **Dense, multi-color, per-cell content** (tables, colored rows, bars) is best
   drawn into a `Display`'s `getWindow()` with custom primitives, with a hit-box
   list for taps — Basalt's per-widget model is awkward for that. Native widgets
   (Label/Input/Button/TextBox/TabControl) are fine for the admin view forms.

---

## 4. The two surfaces

### 4a. Admin View (computer screen, 51×19, keyboard + mouse)

Purpose: configure + monitor + update. Current tabs (keep or restructure):
- **Status**: colony vitals (see data), theme + next-scan countdown, key hints.
- **Monitors**: list of connected monitors with size + which screen layout each
  shows; `1`-`9` reassign a monitor's layout.
- **Peripherals**: network map (`name : type`) to identify remotes.
- **Settings**: numeric fields (currently two suggestion "margins", 0–20).
- **Update**: installed version, "check / install", status.

Global keys today: `r` rescan, `t` cycle theme, `u` check update, `i` install,
`q` quit, `1`-`9` reassign a monitor. Keep keyboard-first; mouse is a bonus.

### 4b. Dashboard (monitors, touch-only, multi-monitor)

Two ordered **columns** of "sections"; column width = screen ÷ number of
non-empty columns; row height within a column = shared by its sections (some are
weighted). A 1-row footer holds controls. EDIT mode (toggled by a small on-screen
icon) shows per-section tap controls to reorder (▲/▼), move to the other column
(◀/▶) and resize height (−/+). Sections can be shown/hidden. Layout + theme
persist per monitor. Extra monitors clone the last configured layout.

Sections (all currently exist — preserve their information):
- **status** — happiness + population as vertical bars; threat, sites, graves.
- **workforce** — employment bar + counts (idle/visitors/buildings).
- **workers** — actionable worker suggestions pinned on top (tap a row to open a
  manual-hire card), a gap, then the full job roster as a 2-column grid
  (building headers + workers tagged ok / →replace / →reassign + open slots).
- **orders** — work orders grouped by type (Build/Upgrade/Repair/Remove), each
  with a claim dot, building name, coordinates, target level.
- **requests** — open colony requests with auto-fulfill status colors; equipment
  shows a level *range*; Domum Ornamentum items show their materials on an
  indented second line.
- **legend** — request color key.
- **jobskills** (hidden by default) — 3-column table: Job / Primary / Secondary
  skill, jobs present in the colony highlighted.

Long section content must scroll via **tap arrows** (monitors can't wheel-scroll).

---

## 5. Data available (EXACT)

### 5a. Raw colony API (Advanced Peripherals `colony_integrator`, read-only)

Methods: `isInColony()`, `getColonyName()`, `getColonyID()`, `getHappiness()`
(0–10 float), `amountOfCitizens()`, `maxOfCitizens()`, `isUnderAttack()`,
`isUnderRaid()`, `amountOfConstructionSites()`, `amountOfGraves()`,
`getCitizens()`, `getBuildings()`, `getWorkOrders()`, `getVisitors()`,
`getRequests()`.

- **Citizen**: `{ id, name, isChild ("adult"/"child"), work = {type=<jobKey>} or {},
  skills = { <SkillName> = level|{level=..} } }`. Skills: Adaptability, Athletics,
  Agility, Stamina, Strength, Focus, Creativity, Knowledge, Mana, Dexterity,
  Intelligence.
- **Building**: `{ type=<jobKey>, name, level, maxLevel, built(bool),
  location={x,y,z}, citizens={ {id,name}, ... } }`. NO per-building worker cap is
  exposed (must be configured).
- **Request**: `{ name, target(string, e.g. "Builder Amos"), count, desc(string),
  items = { { name(item id), displayName, fingerprint(string exact-item id),
  count, maxStackSize, tags, components = { ["domum_ornamentum:texture_data"] =
  { ["minecraft:block/oak_planks"]=<mat id>, ["minecraft:block/dark_oak_planks"]=
  <mat id> } } } } }`.
- **Work order**: `{ workOrderType|type, buildingName|structureName|name,
  targetLevel, isClaimed(bool), location?(guessed) }`.

### 5b. Processed data (what the UI actually renders) — the `data` table

```
data = {
  name, id,                        -- colony name + id
  happiness,                       -- 0..10 float
  pop, maxPop,                     -- current / max citizens
  attack, raid,                    -- booleans
  sites, graves,                   -- construction sites, graves
  total, employed, idle,           -- citizen counts
  buildings, visitors,             -- counts
  orders    = { <work order>, ... },
  suggestions = { <suggestion>, ... },   -- see below
  roster    = { <roster row>, ... },     -- see below
  requests  = { <request item>, ... },   -- see below
  reqMode   = "AUTO"|"MANUAL"|"PAUSED …"|"no bridge",
  bridgePresent, storagePresent,   -- booleans (ME/RS bridge + warehouse)
  jobTypes  = { <jobKey>, ... },   -- unique job types present in the colony
}
```

- **suggestion**: `{ kind = "assign"|"replace"|"reassign", job=<jobKey>,
  jobLabel="Builder 2", from=<jobKey?> (reassign only),
  building={location={x,y,z}}, candidate={name,id,score},
  target={name,id,score}? (replace / reassign-displace), gain=<number> }`.
- **roster row** (flattened, in job order with blank `gap` rows between jobs):
  `{kind="head", building=<jobKey>, label="Builder 2", filled, max}` |
  `{kind="worker", name, status="ok"|"replace"|"reassign", score?, repl?(name),
   to?(target job label), sug?}` |
  `{kind="slot", status="assign"|"empty", cand?(name), sug?}` |
  `{kind="gap"}`.
- **request item**: `{ name, target, count, provided, item_name(id),
  item_displayName, desc, isCraftable, equipment(bool), level, minLevel,
  maxLevel, equipPiece("Boots"…), displayLabel, materials(string, Domum only),
  fingerprint, displayColor(one of the legend colors) }`.

Scan cadence: the whole `data` refreshes every few seconds; a 1s tick updates a
countdown. Suggestion thresholds ("margins") are user-configurable.

---

## 6. Theme / color system

- Four palettes from cc-mek-scada: `deepslate`, `smooth_stone`, `sandstone`,
  `basalt`. Each defines hex values for the 16 color indices (applied via
  `setPaletteColour`) plus a **semantic map** `C`:
  `screen, card, cardTitle, titleText, text, dim, accent, accent2, good, warn,
  bad, note, btn, btnText, btnOk, btnBad`.
- Theme is GLOBAL (applies to computer + every monitor). Redesign should keep the
  semantic-color approach so all four palettes stay legible. Legend currently
  uses: red=missing, yellow=stuck/partial, blue=crafting, green=exported,
  lightBlue=domum, gray=skipped — a redesign may recolor but must stay distinct
  across all four palettes.

---

## 7. Persistence, install, update (context — don't break)

- Per-monitor layout + global theme + settings persist to a file via
  `textutils.serialize`. Config (`config.lua`) is user-editable and preserved
  across updates.
- The program self-updates from a public GitHub repo (SHA-pinned raw fetch).
  A redesign must not change file names/paths in the install manifest without
  updating it.

---

## 8. Deliverables & acceptance

Produce the redesigned `ui/` layer (Basalt-based) that:
1. Renders correctly on the fixed 51×19 terminal AND on monitors of varying size
   (degrade gracefully; never overflow horizontally; sections shrink but stay
   readable).
2. Uses ONLY the 16-color palette + semantic map; legible in all four themes.
3. Monitor interactions are **taps only** (no drag/scroll assumptions); every
   admin action also has a keyboard shortcut.
4. No per-tick full re-render (diff updates); no heavy work in input handlers.
5. Preserves every data point and feature in §4–5.
6. Keeps actions as player-instructions (data source is read-only).

Design proposals should include: a layout sketch (ASCII grid is fine) for the
admin view (51×19) and for a representative monitor size, the color roles used,
and the tap/keyboard interaction map.

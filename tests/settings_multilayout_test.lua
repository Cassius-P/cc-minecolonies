local t        = require("helper")
local settings = require("common.settings")
local engine   = require("ui.layout.engine")

local config = {
  screens = {
    { columns = { { "status" }, { "workers" } }, enabled = { status = true } },
    { columns = { { "orders" }, {} }, enabled = { orders = true } },
  },
}

-- A monitor screen with 5 layout slots (slot 1 populated, rest blank).
local function mkScreen()
  local layouts = { { columns = { { "status" }, {} }, enabled = { status = true }, weights = {}, cfgIdx = 1 } }
  for i = 2, engine.MAX_LAYOUTS do layouts[i] = engine.blankLayout() end
  local s = { name = "m", layouts = layouts, activeLayout = 1 }
  engine.activate(s)
  return s
end

t.case("legacy single-layout entry -> slot 1 backfill, rest empty")
local s = mkScreen()
settings.applyScreenEntry(s, { columns = { { "orders", "status" }, { "workers" } },
  enabled = { orders = true, status = false } }, config)
t.eq(s.activeLayout, 1, "active stays 1")
t.eq(#s.layouts, engine.MAX_LAYOUTS, "still 5 slots")
t.eq(s.layouts[1].columns[1][1], "orders", "slot 1 backfilled from legacy entry")
t.falsy(s.layouts[2].enabled.status, "slot 2 remains empty (all hidden)")
t.eq(s.columns[1][1], "orders", "live fields point at active slot 1")

t.case("new multi-layout entry -> all slots + activeLayout")
local s2 = mkScreen()
settings.applyScreenEntry(s2, {
  activeLayout = 3,
  layouts = {
    [1] = { columns = { { "status" }, {} }, enabled = { status = true } },
    [3] = { columns = { { "orders" }, {} }, enabled = { orders = true } },
  },
}, config)
t.eq(s2.activeLayout, 3, "restored active layout")
t.eq(s2.columns[1][1], "orders", "live fields point at slot 3")
t.eq(s2.layouts[1].columns[1][1], "status", "slot 1 also applied")

t.case("activeLayout clamped to range")
local s3 = mkScreen()
settings.applyScreenEntry(s3, { activeLayout = 99, layouts = {} }, config)
t.eq(s3.activeLayout, engine.MAX_LAYOUTS, "clamped high")

t.case("pocket screen (no layouts) uses single-layout path")
local p = { name = "pocket", columns = { {}, {} }, enabled = {} }
settings.applyScreenEntry(p, { columns = { { "legend" }, {} }, enabled = { legend = true } }, config)
t.eq(p.columns[1][1], "legend", "mutated screen directly")
t.truthy(p.enabled.legend, "enabled applied")

t.case("engine.activate + blankLayout")
local b = engine.blankLayout()
t.falsy(b.enabled.status, "blank hides status")
t.eq(b.cfgIdx, 1, "blank cfgIdx")

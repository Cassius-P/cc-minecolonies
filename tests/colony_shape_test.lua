-- Tests for colony/shape.lua buildData (pure snapshot -> data shaping).
local t     = require("helper")
local shape = require("colony.shape")

local function baseConfig(over)
  local c = {
    suggestions = { replaceMargin = 3, reassignMargin = 4 },
    autofulfill = { enabled = true, pauseUnderAttack = true, minHappiness = 0,
      craftMissing = true, equipment = true, equipmentLevel = "Iron", skipItems = {} },
  }
  if over then for k, v in pairs(over) do c[k] = v end end
  return c
end

t.case("counts + stats + jobTypes from a snapshot")
do
  local snap = {
    stats = { name = "Home", id = 7, happiness = 8, pop = 3, maxPop = 10,
      attack = false, raid = false, sites = 1, graves = 0 },
    citizens = {
      { id = 1, name = "Al", work = { type = "builder" }, skills = { Adaptability = { level = 5 } } },
      { id = 2, name = "Bo" },  -- idle
    },
    buildings = {
      { type = "builder", level = 1, location = { x = 0, y = 0, z = 0 }, citizens = { { id = 1, name = "Al" } } },
      { type = "farmer",  level = 1, location = { x = 1, y = 0, z = 0 }, citizens = {} },
      { type = "tavern",  level = 1, location = { x = 2, y = 0, z = 0 }, citizens = {} }, -- not a JOB_SKILLS job
    },
    orders = {}, visitors = {}, requests = {},
  }
  local d = shape.buildData(snap, baseConfig(), { bridge = false, storage = false })
  t.eq(d.name, "Home")
  t.eq(d.id, 7)
  t.eq(d.total, 2)
  t.eq(d.employed, 1)
  t.eq(d.idle, 1)
  t.eq(d.buildings, 3)
  -- jobTypes: only builder + farmer (tavern excluded), sorted.
  t.eq(#d.jobTypes, 2)
  t.eq(d.jobTypes[1], "builder")
  t.eq(d.jobTypes[2], "farmer")
  t.truthy(d.suggestions, "suggestions present")
  t.truthy(d.roster, "roster present")
end

t.case("auto-fulfill mode gating (pure)")
do
  local snap = { stats = { happiness = 5 }, citizens = {}, buildings = {},
    orders = {}, visitors = {}, requests = {} }

  local noBridge = shape.buildData(snap, baseConfig(), { bridge = false, storage = true })
  t.eq(noBridge.reqMode, "no bridge")
  t.falsy(noBridge.autofulfill.canAuto)

  local auto = shape.buildData(snap, baseConfig(), { bridge = true, storage = true })
  t.eq(auto.reqMode, "AUTO")
  t.truthy(auto.autofulfill.canAuto)

  local raided = shape.buildData(
    { stats = { attack = true }, citizens = {}, buildings = {}, orders = {}, visitors = {}, requests = {} },
    baseConfig(), { bridge = true, storage = true })
  t.eq(raided.reqMode, "PAUSED raid")
  t.falsy(raided.autofulfill.canAuto)

  local disabled = shape.buildData(snap,
    baseConfig({ autofulfill = { enabled = false, pauseUnderAttack = true, minHappiness = 0 } }),
    { bridge = true, storage = true })
  t.eq(disabled.reqMode, "MANUAL", "af disabled but bridge present")
end

t.case("requests categorized + flattened (order: builder, equipment, other)")
do
  local snap = {
    stats = {}, citizens = {}, buildings = {}, orders = {}, visitors = {},
    requests = {
      { name = "Sword", target = "Blacksmith", count = 1, desc = "a Sword item",
        items = { { name = "minecraft:iron_sword", displayName = "Iron Sword" } } },
      { name = "Planks", target = "Builder's Hut", count = 64, desc = "planks",
        items = { { name = "minecraft:oak_planks", displayName = "Oak Planks" } } },
      { name = "Torch", target = "Cook", count = 5, desc = "torch",
        items = { { name = "minecraft:torch", displayName = "Torch" } } },
    },
  }
  local d = shape.buildData(snap, baseConfig(), { bridge = false, storage = false })
  t.eq(#d.reqGroups.eq, 1)
  t.eq(#d.reqGroups.bd, 1)
  t.eq(#d.reqGroups.ot, 1)
  t.eq(#d.requests, 3, "flattened")
  t.eq(d.requests[1].item_name, "minecraft:oak_planks", "builder first")
  t.eq(d.requests[2].item_name, "minecraft:iron_sword", "equipment second")
  t.eq(d.requests[3].item_name, "minecraft:torch", "other third")
end

t.case("work-order builderName resolved from hut position")
do
  local snap = {
    stats = {}, citizens = {}, visitors = {}, requests = {},
    buildings = {
      { type = "builder", level = 1, location = { x = 5, y = 64, z = 5 },
        citizens = { { id = 9, name = "Bob the Builder" } } },
    },
    orders = {
      { builder = { location = { x = 5, y = 64, z = 5 } } },  -- position -> hut -> citizen
      { builder = { name = "Direct Name" } },                 -- explicit name wins
    },
  }
  local d = shape.buildData(snap, baseConfig(), { bridge = false, storage = false })
  t.eq(d.orders[1].builderName, "Bob the Builder")
  t.eq(d.orders[2].builderName, "Direct Name")
end

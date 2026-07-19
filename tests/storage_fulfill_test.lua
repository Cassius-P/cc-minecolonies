-- Characterization tests for storage/fulfill.lua equipNames (pure tier ranges)
-- and the handle() executor driven through the bridge port over a fake bridge.
local t          = require("helper")
local fulfill    = require("storage.fulfill")
local bridgePort = require("common.ports.bridge")
local equipNames = fulfill.equipNames

t.case("tool range clamped by equipmentLevel cap (Iron -> rank 4)")
do
  local out = equipNames({ equipPiece = "Sword", equipment = true, item_name = "x" },
    { equipmentLevel = "Iron" })
  t.eq(#out, 4, "wooden/golden/stone/iron")
  t.eq(out[1], "minecraft:wooden_sword")
  t.eq(out[4], "minecraft:iron_sword")
end

t.case("armor min/max range intersected with cap (Iron and Diamond -> 5)")
do
  local out = equipNames(
    { equipPiece = "Boots", equipment = true, item_name = "x",
      minLevel = "Iron", maxLevel = "Netherite" },
    { equipmentLevel = "Iron and Diamond" })
  t.eq(#out, 2, "iron + diamond (netherite capped out)")
  t.eq(out[1], "minecraft:iron_boots")
  t.eq(out[2], "minecraft:diamond_boots")
end

t.case("SPECIAL pieces resolve to a single fixed id")
do
  t.eq(equipNames({ equipPiece = "Bow" }, {})[1], "minecraft:bow")
  t.eq(equipNames({ equipPiece = "Shears" }, {})[1], "minecraft:shears")
  t.eq(equipNames({ equipPiece = "Shield" }, {})[1], "minecraft:shield")
end

t.case("no/unknown equipPiece falls back to item_name")
do
  t.eq(equipNames({ item_name = "minecraft:torch" }, {})[1], "minecraft:torch", "no piece")
  t.eq(equipNames({ equipPiece = "Wand", item_name = "wand:x" }, {})[1], "wand:x", "unknown piece")
end

t.case("empty in-range set falls back to item_name")
do
  -- min rank 6 (Netherite) but cap Iron (4) -> nothing in range.
  local out = equipNames(
    { equipPiece = "Sword", equipment = true, item_name = "fallback",
      minLevel = "Netherite" },
    { equipmentLevel = "Iron" })
  t.eq(#out, 1)
  t.eq(out[1], "fallback")
end

t.case("handle applies the right status token per outcome (via bridge port)")
do
  local nolog = { safeCall = function(fn) return (pcall(fn)) end, write = function() end }
  local stock = {
    fp_stone = { amount = 10, isCraftable = true,  fingerprint = "fp_stone", export = 4 },
    fp_iron  = { amount = 3,  isCraftable = true,  fingerprint = "fp_iron",  export = 3 },
    fp_void  = { amount = 0,  isCraftable = false, fingerprint = "fp_void" },
  }
  local raw = {
    getItem = function(f)
      local s = stock[f.fingerprint or f.name]
      if not s then return nil end
      return { amount = s.amount, isCraftable = s.isCraftable, fingerprint = s.fingerprint }
    end,
    exportItemToPeripheral = function(f) local s = stock[f.fingerprint]; return s and s.export or 0 end,
    isItemCrafting = function() return false end,
    craftItem = function() return true end,
  }
  local ctx = {
    bridge = bridgePort.new(raw, nolog), storage = "barrel", log = nolog,
    config = { autofulfill = { enabled = true, craftMissing = true, equipment = true,
      equipmentLevel = "Iron", skipItems = { "minecraft:skipme" } } },
  }
  local list = {
    { item_name = "minecraft:skipme", count = 1 },
    { item_name = "minecraft:stone",  count = 4, fingerprint = "fp_stone" },
    { item_name = "minecraft:iron",   count = 10, fingerprint = "fp_iron" },
    { item_name = "minecraft:void",   count = 1, fingerprint = "fp_void" },
  }
  fulfill.handle(list, ctx)
  t.eq(list[1].displayColor, "skipped")
  t.eq(list[2].displayColor, "filled",  "fully exported")
  t.eq(list[3].displayColor, "crafting", "partial then craft queued")
  t.eq(list[4].displayColor, "missing", "not in system / uncraftable")
end

t.case("equipment prefers vanilla from the accept list and exports by fingerprint")
do
  local nolog = { safeCall = function(fn) return (pcall(fn)) end, write = function() end }
  local exported
  local stock = {  -- keyed by fingerprint (resolve looks up by fp now)
    fp_hazmat = { amount = 5, isCraftable = true, fingerprint = "fp_hazmat" },
    fp_iron   = { amount = 5, isCraftable = true, fingerprint = "fp_iron" },
  }
  local raw = {
    getItem = function(f)
      local s = stock[f.fingerprint or f.name]
      if not s then return nil end
      return { amount = s.amount, isCraftable = s.isCraftable, fingerprint = s.fingerprint }
    end,
    exportItemToPeripheral = function(f) exported = f.fingerprint; return 1 end,
    isItemCrafting = function() return false end,
    craftItem = function() return true end,
  }
  local ctx = {
    bridge = bridgePort.new(raw, nolog), storage = "barrel", log = nolog,
    config = { autofulfill = { enabled = true, craftMissing = true, equipment = true } },
  }
  -- items[] lists the modded item first; orderAccept must still pick vanilla.
  local item = { count = 1, equipment = true, equipPiece = "Leggings", acceptItems = {
    { name = "mekanism:hazmat_pants",   fingerprint = "fp_hazmat" },
    { name = "minecraft:iron_leggings", fingerprint = "fp_iron" },
  } }
  fulfill.handle({ item }, ctx)
  t.eq(exported, "fp_iron", "vanilla iron_leggings exported, not hazmat")
  t.eq(item.displayColor, "filled")
end

t.case("enchanted warehouse stack does not satisfy a pristine request; craft a valid one")
do
  local nolog = { safeCall = function(fn) return (pcall(fn)) end, write = function() end }
  local crafted
  -- ME has no pristine iron (fp lookup misses); pristine leather is craftable.
  local stock = { fp_leather = { amount = 0, isCraftable = true, fingerprint = "fp_leather" } }
  local raw = {
    getItem = function(f)
      local s = stock[f.fingerprint]
      if not s then return nil end
      return { amount = s.amount, isCraftable = s.isCraftable, fingerprint = s.fingerprint }
    end,
    exportItemToPeripheral = function() return 0 end,
    isItemCrafting = function() return false end,
    craftItem = function(f) crafted = f.fingerprint; return true end,
  }
  local ctx = {
    bridge = bridgePort.new(raw, nolog), storage = "barrel", log = nolog,
    -- an enchanted "Blessed Iron Leggings" sits in the warehouse (has nbt)
    warehouse = { { name = "minecraft:iron_leggings", count = 1, nbt = "blessed" } },
    config = { autofulfill = { enabled = true, craftMissing = true, equipment = true } },
  }
  local item = { count = 1, equipment = true, equipPiece = "Leggings", acceptItems = {
    { name = "minecraft:leather_leggings", fingerprint = "fp_leather" },
    { name = "minecraft:iron_leggings",    fingerprint = "fp_iron" },
  } }
  fulfill.handle({ item }, ctx)
  t.eq(crafted, "fp_leather", "crafts a pristine acceptable leggings, not blocked by the enchanted one")
  t.eq(item.displayColor, "crafting")
end

t.case("equipment already in warehouse -> filled, no re-craft (loop guard)")
do
  local nolog = { safeCall = function(fn) return (pcall(fn)) end, write = function() end }
  local crafted = false
  local raw = {
    getItem = function() return nil end,           -- nothing in ME
    exportItemToPeripheral = function() return 0 end,
    isItemCrafting = function() return false end,
    craftItem = function() crafted = true; return true end,
  }
  local ctx = {
    bridge = bridgePort.new(raw, nolog), storage = "barrel", log = nolog,
    warehouse = { { name = "minecraft:iron_shovel", count = 1 } },  -- already exported, awaiting courier
    config = { autofulfill = { enabled = true, craftMissing = true, equipment = true,
      equipmentLevel = "Iron" } },
  }
  local item = { item_name = "minecraft:iron_shovel", count = 1, equipment = true,
    equipPiece = "Shovel", minLevel = "Iron", maxLevel = "Iron" }
  fulfill.handle({ item }, ctx)
  t.eq(item.displayColor, "filled", "warehouse stock satisfies it")
  t.falsy(crafted, "no craft issued while tool sits in warehouse")
end

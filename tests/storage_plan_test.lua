-- Tests for storage/plan.lua pure fulfill decisions.
local t    = require("helper")
local plan = require("storage.plan")

t.case("equipNames matches fulfill.equipNames (moved here)")
do
  local out = plan.equipNames({ equipPiece = "Sword", equipment = true, item_name = "x" },
    { equipmentLevel = "Iron" })
  t.eq(#out, 4)
  t.eq(out[4], "minecraft:iron_sword")
end

t.case("skipSet / shouldSkip")
do
  local set = plan.skipSet({ "minecraft:enchanted_book", "minecraft:torch" })
  t.truthy(plan.shouldSkip({ item_name = "minecraft:torch" }, set))
  t.falsy(plan.shouldSkip({ item_name = "minecraft:stone" }, set))
  t.falsy(plan.shouldSkip({ item_name = "x" }, plan.skipSet(nil)), "nil list -> empty set")
end

t.case("selectCandidates picks first stocked + first craftable")
do
  local cands = {
    { amount = 0, craftable = false, filter = { name = "a" } },
    { amount = 5, craftable = true,  filter = { name = "b" } },
    { amount = 9, craftable = true,  filter = { name = "c" } },
  }
  local stocked, craft = plan.selectCandidates(cands)
  t.eq(stocked.name, "b", "first with amount>0")
  t.eq(craft.name, "b", "first craftable")

  local none = plan.selectCandidates({ { amount = 0, craftable = false, filter = {} } })
  t.eq(none, nil, "nothing stocked")
end

t.case("exportToken")
do
  local tok, done = plan.exportToken(10, 10)
  t.eq(tok, "filled"); t.truthy(done)
  local tok2, done2 = plan.exportToken(3, 10)
  t.eq(tok2, "partial"); t.falsy(done2)
end

t.case("craftResultToken")
do
  t.eq(plan.craftResultToken(true), "crafting")
  t.eq(plan.craftResultToken(false), "partial")
end

t.case("orderAccept puts vanilla first, keeps order, dedups, carries fingerprint")
do
  local out = plan.orderAccept({
    { name = "mekanism:hazmat_pants", fingerprint = "fpH" },
    { name = "minecraft:leather_leggings", fingerprint = "fpL" },
    { name = "the_bumblezone:honey_bee_leggings_1", fingerprint = "fpB" },
    { name = "minecraft:iron_leggings", fingerprint = "fpI" },
    { name = "minecraft:leather_leggings", fingerprint = "fpL2" },  -- name dup
  })
  t.eq(out[1].name, "minecraft:leather_leggings", "vanilla first, request order")
  t.eq(out[1].fingerprint, "fpL", "fingerprint carried")
  t.eq(out[2].name, "minecraft:iron_leggings")
  t.eq(out[3].name, "mekanism:hazmat_pants", "modded after vanilla, request order")
  t.eq(out[4].name, "the_bumblezone:honey_bee_leggings_1")
  t.eq(#out, 4, "duplicate name dropped")
  t.eq(#plan.orderAccept(nil), 0, "nil safe")
end

t.case("warehouseHave pristineOnly skips enchanted/NBT stacks")
do
  local list = {
    [1] = { name = "minecraft:iron_leggings", count = 1, nbt = "abc" },  -- enchanted
    [2] = { name = "minecraft:iron_leggings", count = 1 },               -- pristine
  }
  t.eq(plan.warehouseHave(list, { "minecraft:iron_leggings" }), 2, "counts all by default")
  t.eq(plan.warehouseHave(list, { "minecraft:iron_leggings" }, true), 1, "pristine only")
end

t.case("warehouseHave sums matching names across a warehouse list")
do
  local list = {
    [1] = { name = "minecraft:iron_shovel", count = 2 },
    [3] = { name = "minecraft:diamond_shovel", count = 1 },
    [4] = { name = "minecraft:stone", count = 64 },
  }
  t.eq(plan.warehouseHave(list, { "minecraft:iron_shovel", "minecraft:diamond_shovel" }), 3)
  t.eq(plan.warehouseHave(list, { "minecraft:iron_axe" }), 0, "no match")
  t.eq(plan.warehouseHave(nil, { "x" }), 0, "nil list")
  t.eq(plan.warehouseHave(list, nil), 0, "nil names")
end

t.case("withCount clones filter and adds count")
do
  local f = plan.withCount({ fingerprint = "fp" }, 7)
  t.eq(f.fingerprint, "fp")
  t.eq(f.count, 7)
end

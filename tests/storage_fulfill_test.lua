-- Characterization tests for storage/fulfill.lua equipNames (pure tier ranges).
local t       = require("helper")
local fulfill = require("storage.fulfill")
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

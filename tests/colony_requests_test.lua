-- Characterization tests for colony/requests.lua (request classification).
-- Needs the `colors` stub (categorize sets displayColor = colors.white).
local t        = require("helper")
local requests = require("colony.requests")

t.case("isEquipment keyword detection")
t.truthy(requests.isEquipment("Requires a Pickaxe of some level"))
t.truthy(requests.isEquipment("needs Boots"))
t.falsy(requests.isEquipment("just some oak planks"))

t.case("categorize splits equipment / builder / other")
do
  local raw = {
    { name = "Iron Sword", target = "Blacksmith", count = 1,
      desc = "Sword with minimal level: Wood and with maximal level: Iron and with an enchant",
      items = { { name = "minecraft:iron_sword", displayName = "Iron Sword", fingerprint = "fp1" } } },
    { name = "Planks", target = "Builder's Hut", count = 64,
      desc = "some oak planks",
      items = { { name = "minecraft:oak_planks", displayName = "Oak Planks" } } },
    { name = "Torch", target = "Cook", count = 5,
      desc = "torches for light",
      items = { { name = "minecraft:torch", displayName = "Torch" } } },
  }
  local eq, bd, ot = requests.categorize(raw)
  t.eq(#eq, 1, "one equipment")
  t.eq(#bd, 1, "one builder (target has Builder)")
  t.eq(#ot, 1, "one other")

  t.eq(eq[1].equipment, true)
  t.eq(eq[1].equipPiece, "Sword")
  t.eq(eq[1].minLevel, "Wood")
  t.eq(eq[1].maxLevel, "Iron")
  t.eq(eq[1].displayLabel, "Sword (Wood -> Iron)")
  t.eq(eq[1].fingerprint, "fp1")
  t.eq(eq[1].provided, 0, "default provided")
  t.eq(eq[1].displayColor, "default", "default status token")

  t.eq(bd[1].item_name, "minecraft:oak_planks")
  t.eq(ot[1].item_name, "minecraft:torch")
end

t.case("domum block: type shown in the materials line")
do
  local raw = {
    { name = "1-4 Framed Sea Lantern", target = "Builder's Hut", count = 4,
      desc = "1-4 Framed Sea Lantern",
      items = { {
        name = "domum_ornamentum:fancy_light", displayName = "[Framed Sea Lantern]",
        fingerprint = "fp_fl",
        components = { ["domum_ornamentum:texture_data"] = {
          ["minecraft:block/oak_planks"] = "minecraft:gold_block",
          ["minecraft:block/glowstone"]  = "minecraft:sea_lantern",
        } },
      } } },
  }
  local _, bd = requests.categorize(raw)
  t.eq(#bd, 1, "domum request -> builder")
  t.eq(bd[1].displayLabel, "Framed Sea Lantern", "label keeps MC display name")
  t.eq(bd[1].materials, "Fancy Light: Gold Block + Sea Lantern", "block type prefixes the materials")
end

t.case("domum block: type shown even with no texture materials")
do
  local raw = {
    { name = "Fancy Light", target = "Builder's Hut", count = 1, desc = "Fancy Light",
      items = { { name = "domum_ornamentum:fancy_light", displayName = "[Fancy Light]" } } },
  }
  local _, bd = requests.categorize(raw)
  t.eq(bd[1].materials, "Fancy Light", "no materials -> materials line is just the block type")
end

t.case("categorize tolerates empty / missing items")
do
  local eq, bd, ot = requests.categorize({ { name = "junk", items = {} } })
  t.eq(#eq + #bd + #ot, 0, "request with no items skipped")
  local e2 = requests.categorize(nil)
  t.eq(#e2, 0, "nil raw list -> empty")
end

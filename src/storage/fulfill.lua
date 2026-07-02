----------------------------------------------------------------------------
-- storage/fulfill.lua -- CCxM auto-fulfill core.
--
-- Exports colony requests from an ME/RS bridge to the warehouse and queues
-- crafts for what is missing. For equipment requested as a level RANGE
-- (e.g. Boots Leather -> Chain), it tries every material in the range and
-- picks one that is in stock, else one that is craftable -- instead of a single
-- random pick. Peripherals are passed in (found by network name), so it works
-- over a wired-modem network. Sets item.displayColor for the legend.
----------------------------------------------------------------------------

local M = {}

local quantityField = nil  -- "amount" (ME) or "count" (RS), detected once

-- Equipment material tiers (low -> high) and a rough level rank for range filtering.
local ARMOR_PART = { Helmet = "helmet", Chestplate = "chestplate", Leggings = "leggings", Boots = "boots" }
local TOOL_PART  = { Sword = "sword", Pickaxe = "pickaxe", Axe = "axe", Shovel = "shovel", Hoe = "hoe" }
local SPECIAL    = { Bow = "minecraft:bow", Shears = "minecraft:shears", Shield = "minecraft:shield" }
local ARMOR_MATS = { "leather", "golden", "chainmail", "iron", "diamond", "netherite" }
local TOOL_MATS  = { "wooden", "golden", "stone", "iron", "diamond", "netherite" }
local RANK = { Wood = 1, Leather = 1, Gold = 2, Chain = 2, Stone = 3, Iron = 4, Diamond = 5, Netherite = 6 }
local MAT_RANK = { leather = 1, wooden = 1, golden = 2, chainmail = 2, stone = 3, iron = 4, diamond = 5, netherite = 6 }
local CAP_RANK = { ["Iron"] = 4, ["Diamond"] = 5, ["Iron and Diamond"] = 5 }

-- Candidate item ids for an equipment request, within [min,max] and the config cap.
local function equipCandidates(item, af)
  local piece = item.equipPiece
  if not piece then return { item.item_name } end
  if SPECIAL[piece] then return { SPECIAL[piece] } end
  local part = ARMOR_PART[piece]
  local mats = part and ARMOR_MATS
  if not part then part = TOOL_PART[piece]; mats = part and TOOL_MATS end
  if not part then return { item.item_name } end

  local lo = (item.minLevel and RANK[item.minLevel]) or 1
  local hi = (item.maxLevel and RANK[item.maxLevel]) or 99
  hi = math.min(hi, CAP_RANK[af.equipmentLevel] or 99)

  local out = {}
  for _, m in ipairs(mats) do
    local r = MAT_RANK[m] or 99
    if r >= lo and r <= hi then out[#out + 1] = "minecraft:" .. m .. "_" .. part end
  end
  if #out == 0 then out[1] = item.item_name end  -- fall back to the requested item
  return out
end

local function detectQuantityField(bridge, filter)
  local ok, data = pcall(function() return bridge.getItem(filter) end)
  if ok and data then
    if type(data.amount) == "number" then return "amount" end
    if type(data.count) == "number" then return "count" end
  end
  return nil
end

-- Query stored amount + craftability for an item filter ({name=..} or
-- {fingerprint=..} for an exact Domum match).
local function stockOf(bridge, filter)
  local d
  local ok = pcall(function() d = bridge.getItem(filter) end)
  if not ok or type(d) ~= "table" then return nil end
  return (d[quantityField] or 0), d.isCraftable
end

local function domum(name) return type(name) == "string" and string.sub(name, 1, 17) == "domum_ornamentum:" end

-- Export up to `count` matching `filter` to storage; returns amount provided.
local function doExport(bridge, storage, filter, count)
  local f = { count = count }
  for k, v in pairs(filter) do f[k] = v end
  local provided = 0
  local ok = pcall(function() provided = bridge.exportItemToPeripheral(f, storage) end)
  if not ok then
    pcall(function() provided = bridge.exportItem(f, storage) end)
  end
  return provided or 0
end

-- handle(list, ctx): ctx = { bridge, storage, config, log }
function M.handle(list, ctx)
  local bridge, storage = ctx.bridge, ctx.storage
  local af = ctx.config.autofulfill
  local log = ctx.log
  local skip = {}
  for _, n in ipairs(af.skipItems or {}) do skip[n] = true end

  for _, item in ipairs(list) do
    if skip[item.item_name] then
      item.displayColor = colors.gray
      goto continue
    end

    -- Candidate filters to satisfy this request. Domum requests use the exact
    -- item fingerprint (Advanced Peripherals item id) so only the block with the
    -- matching frame/center materials is exported. Equipment uses a name per
    -- material in the level range. Everything else matches by name.
    local filters = {}
    if item.fingerprint then
      filters[1] = { fingerprint = item.fingerprint }
    elseif item.equipment then
      for _, id in ipairs(equipCandidates(item, af)) do filters[#filters + 1] = { name = id } end
    else
      filters[1] = { name = item.item_name }
    end
    if not quantityField then quantityField = detectQuantityField(bridge, filters[1]) end

    -- Pass 1: pick the first candidate that is in stock and export it.
    local stocked, craftName
    for _, fl in ipairs(filters) do
      local st, cr = stockOf(bridge, fl)
      if st then
        if st > 0 and not stocked then stocked = fl end
        if cr and fl.name and not craftName then craftName = fl.name end
      end
    end

    if stocked then
      item.provided = doExport(bridge, storage, stocked, item.count)
      if item.provided >= item.count then
        item.displayColor = domum(item.item_name) and colors.lightBlue or colors.green
        goto continue
      else
        item.displayColor = colors.yellow
      end
    end

    -- Pass 2: craft a craftable candidate for the shortfall (by name only;
    -- Domum blocks are crafted in-world, not by the ME/RS system).
    if not af.craftMissing then
      if not stocked then item.displayColor = colors.red end
      goto continue
    end
    if item.equipment and not af.equipment then goto continue end

    if craftName and (item.provided or 0) < item.count then
      local crafting = false
      log.safeCall(function() crafting = bridge.isItemCrafting({ name = craftName }) end)
      if crafting then
        item.item_name = craftName; item.displayColor = colors.blue
        goto continue
      end
      local ok = log.safeCall(function()
        return bridge.craftItem({ name = craftName, count = item.count - (item.provided or 0) })
      end)
      item.item_name = craftName
      item.displayColor = ok and colors.blue or colors.yellow
    elseif not stocked then
      log.write((item.displayLabel or item.item_displayName or item.item_name) .. " not in system or craftable.")
      item.displayColor = domum(item.item_name) and colors.lightBlue or colors.red
    end

    ::continue::
  end
end

return M

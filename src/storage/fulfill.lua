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

local function detectQuantityField(bridge, itemName)
  local ok, data = pcall(function() return bridge.getItem({ name = itemName }) end)
  if ok and data then
    if type(data.amount) == "number" then return "amount" end
    if type(data.count) == "number" then return "count" end
  end
  return nil
end

-- Query stored amount + craftability for one item id.
local function stockOf(bridge, name)
  local d
  local ok = pcall(function() d = bridge.getItem({ name = name }) end)
  if not ok or type(d) ~= "table" then return nil end
  return (d[quantityField] or 0), d.isCraftable
end

local function domum(name) return string.sub(name, 1, 17) == "domum_ornamentum:" end

-- Export up to `count` of `name` to storage; returns amount provided.
local function doExport(bridge, storage, name, count)
  local provided = 0
  local ok = pcall(function()
    provided = bridge.exportItemToPeripheral({ name = name, count = count }, storage)
  end)
  if not ok then
    pcall(function() provided = bridge.exportItem({ name = name, count = count }, storage) end)
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

    -- Candidate item ids to satisfy this request.
    local candidates = item.equipment and equipCandidates(item, af) or { item.item_name }
    if not quantityField then quantityField = detectQuantityField(bridge, candidates[1]) end

    -- Pass 1: pick the first candidate that is in stock and export it.
    local stocked, craftId
    for _, id in ipairs(candidates) do
      local st, cr = stockOf(bridge, id)
      if st == nil then
        -- unknown; treat as not present
      else
        if st > 0 and not stocked then stocked = id end
        if cr and not craftId then craftId = id end
      end
    end

    if stocked then
      item.item_name = stocked
      item.provided = doExport(bridge, storage, stocked, item.count)
      if item.provided >= item.count then
        item.displayColor = domum(stocked) and colors.lightBlue or colors.green
      else
        item.displayColor = colors.yellow
      end
      if item.provided >= item.count then goto continue end
    end

    -- Pass 2: craft a craftable candidate for the shortfall.
    if not af.craftMissing then
      if not stocked then item.displayColor = colors.red end
      goto continue
    end
    if item.equipment and not af.equipment then goto continue end

    if craftId and (item.provided or 0) < item.count then
      local crafting = false
      log.safeCall(function() crafting = bridge.isItemCrafting({ name = craftId }) end)
      if crafting then
        item.item_name = craftId; item.displayColor = colors.blue
        goto continue
      end
      local ok = log.safeCall(function()
        return bridge.craftItem({ name = craftId, count = item.count - (item.provided or 0) })
      end)
      item.item_name = craftId
      item.displayColor = ok and colors.blue or colors.yellow
    elseif not stocked then
      log.write((item.displayLabel or item.item_displayName or item.item_name) .. " not in system or craftable.")
      item.displayColor = domum(item.item_name) and colors.lightBlue or colors.red
    end

    ::continue::
  end
end

return M

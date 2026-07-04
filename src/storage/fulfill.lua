----------------------------------------------------------------------------
-- storage/fulfill.lua -- CCxM auto-fulfill core.
--
-- Exports colony requests from an ME/RS bridge to the warehouse and queues
-- crafts for what is missing. Every item is operated on by its Advanced
-- Peripherals fingerprint (exact item id), never a bare name string:
--   * Domum / plain items -> the request's own fingerprint (exact NBT/materials).
--   * Equipment level ranges -> each in-range material name is looked up to get
--     its fingerprint, then export/craft use that fingerprint.
-- Sets item.displayColor for the legend.
----------------------------------------------------------------------------

local M = {}

local quantityField = nil  -- "amount" (ME) or "count" (RS), detected once

-- Equipment material tiers (low -> high) + level rank for range filtering.
local ARMOR_PART = { Helmet = "helmet", Chestplate = "chestplate", Leggings = "leggings", Boots = "boots" }
local TOOL_PART  = { Sword = "sword", Pickaxe = "pickaxe", Axe = "axe", Shovel = "shovel", Hoe = "hoe" }
local SPECIAL    = { Bow = "minecraft:bow", Shears = "minecraft:shears", Shield = "minecraft:shield" }
local ARMOR_MATS = { "leather", "golden", "chainmail", "iron", "diamond", "netherite" }
local TOOL_MATS  = { "wooden", "golden", "stone", "iron", "diamond", "netherite" }
local RANK = { Wood = 1, Leather = 1, Gold = 2, Chain = 2, Stone = 3, Iron = 4, Diamond = 5, Netherite = 6 }
local MAT_RANK = { leather = 1, wooden = 1, golden = 2, chainmail = 2, stone = 3, iron = 4, diamond = 5, netherite = 6 }
local CAP_RANK = { ["Iron"] = 4, ["Diamond"] = 5, ["Iron and Diamond"] = 5 }

-- In-range candidate item ids (names) for an equipment request.
local function equipNames(item, af)
  local piece = item.equipPiece
  if not piece then return { item.item_name } end
  if SPECIAL[piece] then return { SPECIAL[piece] } end
  local part = ARMOR_PART[piece]
  local mats = part and ARMOR_MATS
  if not part then part = TOOL_PART[piece]; mats = part and TOOL_MATS end
  if not part then return { item.item_name } end
  local lo = (item.minLevel and RANK[item.minLevel]) or 1
  local hi = math.min((item.maxLevel and RANK[item.maxLevel]) or 99, CAP_RANK[af.equipmentLevel] or 99)
  local out = {}
  for _, m in ipairs(mats) do
    local r = MAT_RANK[m] or 99
    if r >= lo and r <= hi then out[#out + 1] = "minecraft:" .. m .. "_" .. part end
  end
  if #out == 0 then out[1] = item.item_name end
  return out
end

local function detectQuantityField(bridge, filter)
  local ok, d = pcall(function() return bridge.getItem(filter) end)
  if ok and d then
    if type(d.amount) == "number" then return "amount" end
    if type(d.count) == "number" then return "count" end
  end
  return nil
end

-- Look up an item; return { filter (by fingerprint when available), amount, craftable }.
local function lookup(bridge, byFilter)
  local d
  local ok = pcall(function() d = bridge.getItem(byFilter) end)
  if not ok or type(d) ~= "table" then return nil end
  return {
    filter = d.fingerprint and { fingerprint = d.fingerprint } or byFilter,
    amount = d[quantityField] or 0,
    craftable = d.isCraftable,
  }
end

-- Resolve a request to fingerprint-based candidates.
local function resolve(bridge, item, af)
  local out = {}
  if item.equipment then
    -- Resolve equipment by material-name range, NOT the request's fingerprint:
    -- the request-side item fingerprint hashes differently from the stored
    -- stack, so a fingerprint lookup misses items that are in stock/craftable.
    -- The by-name getItem returns the correct storage-side fingerprint to export.
    for _, name in ipairs(equipNames(item, af)) do
      local c = lookup(bridge, { name = name }); if c then out[#out + 1] = c end
    end
  else
    local base = item.fingerprint and { fingerprint = item.fingerprint } or { name = item.item_name }
    local c = lookup(bridge, base); if c then out[#out + 1] = c end
  end
  return out
end


local function withCount(filter, count)
  local f = { count = count }
  for k, v in pairs(filter) do f[k] = v end
  return f
end

-- Export up to `count` matching `filter`; returns amount provided.
local function doExport(bridge, storage, filter, count)
  local f = withCount(filter, count)
  local provided = 0
  local ok = pcall(function() provided = bridge.exportItemToPeripheral(f, storage) end)
  if not ok then pcall(function() provided = bridge.exportItem(f, storage) end) end
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

    if not quantityField then
      local probe = item.fingerprint and { fingerprint = item.fingerprint }
        or { name = (item.equipment and equipNames(item, af)[1]) or item.item_name }
      quantityField = detectQuantityField(bridge, probe)
    end

    local cands = resolve(bridge, item, af)
    local stocked, craftFilter
    for _, c in ipairs(cands) do
      if c.amount > 0 and not stocked then stocked = c.filter end
      if c.craftable and not craftFilter then craftFilter = c.filter end
    end

    -- Pass 1: export an in-stock candidate (exact, by fingerprint).
    if stocked then
      item.provided = doExport(bridge, storage, stocked, item.count)
      if item.provided >= item.count then
        item.displayColor = colors.green   -- fully exported (Domum too; it's flagged by its purple materials line)
        goto continue
      else
        item.displayColor = colors.yellow
      end
    end

    -- Pass 2: craft a craftable candidate (by fingerprint) for the shortfall.
    if not af.craftMissing then
      if not stocked then item.displayColor = colors.red end
      goto continue
    end
    if item.equipment and not af.equipment then goto continue end

    if craftFilter and (item.provided or 0) < item.count then
      local crafting = false
      log.safeCall(function() crafting = bridge.isItemCrafting(craftFilter) end)
      if crafting then
        item.displayColor = colors.blue
        goto continue
      end
      local ok = log.safeCall(function()
        return bridge.craftItem(withCount(craftFilter, item.count - (item.provided or 0)))
      end)
      item.displayColor = ok and colors.blue or colors.yellow
    elseif not stocked then
      log.write((item.displayLabel or item.item_displayName or item.item_name) .. " not in system or craftable.")
      item.displayColor = colors.red
    end

    ::continue::
  end
end

return M

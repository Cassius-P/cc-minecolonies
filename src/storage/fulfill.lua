----------------------------------------------------------------------------
-- storage/fulfill.lua -- CCxM auto-fulfill EXECUTOR (effectful).
--
-- Exports colony requests from an ME/RS bridge to the warehouse and queues
-- crafts for what is missing. Every item is operated on by its Advanced
-- Peripherals fingerprint (exact item id), never a bare name string:
--   * Domum / plain items -> the request's own fingerprint (exact NBT/materials).
--   * Equipment level ranges -> each in-range material name is looked up to get
--     its fingerprint, then export/craft use that fingerprint.
-- The pure decisions (tier ranges, candidate selection, status tokens) live in
-- storage/plan.lua; this file drives the bridge and applies the tokens.
----------------------------------------------------------------------------

local plan = require("storage.plan")

local M = {}

local quantityField = nil  -- "amount" (ME) or "count" (RS), detected once

-- Exposed for unit tests (pure, delegates to plan).
M.equipNames = plan.equipNames

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

-- Resolve a request to fingerprint-based candidates (I/O: per-candidate lookup).
local function resolve(bridge, item, af)
  local out = {}
  if item.equipment then
    -- Resolve equipment by material-name range, NOT the request's fingerprint:
    -- the request-side item fingerprint hashes differently from the stored
    -- stack, so a fingerprint lookup misses items that are in stock/craftable.
    -- The by-name getItem returns the correct storage-side fingerprint to export.
    for _, name in ipairs(plan.equipNames(item, af)) do
      local c = lookup(bridge, { name = name }); if c then out[#out + 1] = c end
    end
  else
    local base = item.fingerprint and { fingerprint = item.fingerprint } or { name = item.item_name }
    local c = lookup(bridge, base); if c then out[#out + 1] = c end
  end
  return out
end

-- Export up to `count` matching `filter`; returns amount provided.
local function doExport(bridge, storage, filter, count)
  local f = plan.withCount(filter, count)
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
  local skip = plan.skipSet(af.skipItems)

  for _, item in ipairs(list) do
    if plan.shouldSkip(item, skip) then
      item.displayColor = "skipped"
      goto continue
    end

    if not quantityField then
      local probe = item.fingerprint and { fingerprint = item.fingerprint }
        or { name = (item.equipment and plan.equipNames(item, af)[1]) or item.item_name }
      quantityField = detectQuantityField(bridge, probe)
    end

    local cands = resolve(bridge, item, af)
    local stocked, craftFilter = plan.selectCandidates(cands)

    -- Pass 1: export an in-stock candidate (exact, by fingerprint).
    if stocked then
      item.provided = doExport(bridge, storage, stocked, item.count)
      local token, done = plan.exportToken(item.provided, item.count)
      item.displayColor = token   -- "filled" (Domum too; flagged by its purple materials line) or "partial"
      if done then goto continue end
    end

    -- Pass 2: craft a craftable candidate (by fingerprint) for the shortfall.
    if not af.craftMissing then
      if not stocked then item.displayColor = "missing" end
      goto continue
    end
    if item.equipment and not af.equipment then goto continue end

    if craftFilter and (item.provided or 0) < item.count then
      local crafting = false
      log.safeCall(function() crafting = bridge.isItemCrafting(craftFilter) end)
      if crafting then
        item.displayColor = "crafting"
        goto continue
      end
      local ok = log.safeCall(function()
        return bridge.craftItem(plan.withCount(craftFilter, item.count - (item.provided or 0)))
      end)
      item.displayColor = plan.craftResultToken(ok)
    elseif not stocked then
      log.write((item.displayLabel or item.item_displayName or item.item_name) .. " not in system or craftable.")
      item.displayColor = "missing"
    end

    ::continue::
  end
end

return M

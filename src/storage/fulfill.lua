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
-- storage/plan.lua; all bridge I/O goes through a BridgePort (ctx.bridge), so
-- this file just sequences the export/craft passes and applies the tokens.
----------------------------------------------------------------------------

local plan = require("storage.plan")

local M = {}

-- Exposed for unit tests (pure, delegates to plan).
M.equipNames = plan.equipNames

-- Resolve a request to fingerprint-based candidates via the bridge port.
local function resolve(bridge, item, af)
  local out = {}
  if item.equipment then
    -- Resolve equipment by material-name range, NOT the request's fingerprint:
    -- the request-side item fingerprint hashes differently from the stored
    -- stack, so a fingerprint lookup misses items that are in stock/craftable.
    -- The by-name getItem returns the correct storage-side fingerprint to export.
    for _, name in ipairs(plan.equipNames(item, af)) do
      local c = bridge.getItem({ name = name }); if c then out[#out + 1] = c end
    end
  else
    local base = item.fingerprint and { fingerprint = item.fingerprint } or { name = item.item_name }
    local c = bridge.getItem(base); if c then out[#out + 1] = c end
  end
  return out
end

-- handle(list, ctx): ctx = { bridge (BridgePort), storage, config, log }
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

    local cands = resolve(bridge, item, af)
    local stocked, craftFilter = plan.selectCandidates(cands)

    -- Pass 1: export an in-stock candidate (exact, by fingerprint).
    if stocked then
      item.provided = bridge.exportItem(plan.withCount(stocked, item.count), storage)
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
      if bridge.isCrafting(craftFilter) then
        item.displayColor = "crafting"
        goto continue
      end
      local ok = bridge.craftItem(plan.withCount(craftFilter, item.count - (item.provided or 0)))
      item.displayColor = plan.craftResultToken(ok)
    elseif not stocked then
      log.write((item.displayLabel or item.item_displayName or item.item_name) .. " not in system or craftable.")
      item.displayColor = "missing"
    end

    ::continue::
  end
end

return M

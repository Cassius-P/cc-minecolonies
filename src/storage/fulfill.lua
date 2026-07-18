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

-- Equipment candidate item ids in priority order: the colony's own accept list
-- (vanilla-first), else the synthesized tier range when no accept list is present.
local function equipCandidateNames(item, af)
  if item.acceptNames and #item.acceptNames > 0 then return plan.orderAccept(item.acceptNames) end
  return plan.equipNames(item, af)
end

-- Resolve a request to fingerprint-based candidates via the bridge port.
-- Equipment is resolved by NAME (not the request fingerprint, which hashes
-- differently from the stored stack); the by-name getItem returns the correct
-- storage-side fingerprint to export. Stops once a stocked AND a craftable
-- candidate are found (accept lists can be ~30 items -> avoid that many calls).
local function resolve(bridge, item, names)
  local out = {}
  if not item.equipment then
    local base = item.fingerprint and { fingerprint = item.fingerprint } or { name = item.item_name }
    local c = bridge.getItem(base); if c then out[#out + 1] = c end
    return out
  end
  local haveStocked, haveCraft = false, false
  for _, name in ipairs(names) do
    local c = bridge.getItem({ name = name })
    if c then
      out[#out + 1] = c
      if c.amount > 0 then haveStocked = true end
      if c.craftable then haveCraft = true end
      if haveStocked and haveCraft then break end
    end
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

    -- Equipment we already exported can sit in the warehouse for several scans
    -- before a courier collects it (unlike stack deliverables). Count it so we
    -- don't re-export/re-craft the same tool every scan during delivery lag.
    local names = item.equipment and equipCandidateNames(item, af) or nil
    local have = names and plan.warehouseHave(ctx.warehouse, names) or 0
    if have >= item.count then
      item.provided = item.count
      item.displayColor = "filled"
      goto continue
    end
    local need = item.count - have

    local cands = resolve(bridge, item, names)
    local stocked, craftFilter = plan.selectCandidates(cands)

    -- Pass 1: export an in-stock candidate (exact, by fingerprint).
    if stocked then
      item.provided = bridge.exportItem(plan.withCount(stocked, need), storage)
      local token, done = plan.exportToken(have + item.provided, item.count)
      item.displayColor = token   -- "filled" (Domum too; flagged by its purple materials line) or "partial"
      if done then goto continue end
    end

    -- Pass 2: craft a craftable candidate (by fingerprint) for the shortfall.
    if not af.craftMissing then
      if not stocked then item.displayColor = "missing" end
      goto continue
    end
    if item.equipment and not af.equipment then goto continue end

    local shortfall = item.count - have - (item.provided or 0)
    if craftFilter and shortfall > 0 then
      if bridge.isCrafting(craftFilter) then
        item.displayColor = "crafting"
        goto continue
      end
      local ok = bridge.craftItem(plan.withCount(craftFilter, shortfall))
      item.displayColor = plan.craftResultToken(ok)
    elseif not stocked then
      log.write((item.displayLabel or item.item_displayName or item.item_name) .. " not in system or craftable.")
      item.displayColor = "missing"
    end

    ::continue::
  end
end

return M

----------------------------------------------------------------------------
-- storage/fulfill.lua -- CCxM auto-fulfill EXECUTOR (effectful).
--
-- Exports colony requests from an ME/RS bridge to the warehouse and queues
-- crafts for what is missing. Every item is operated on by its Advanced
-- Peripherals fingerprint (exact item id), never a bare name string:
--   * Domum / plain items -> the request's own fingerprint (exact NBT/materials).
--   * Equipment -> the colony's accepted-items list (vanilla-first), each looked
--     up by its exact fingerprint so an enchanted/damaged same-id stack (which the
--     colony rejects) is never exported; pristine warehouse stock counts as filled.
-- The pure decisions (tier ranges, candidate selection, status tokens) live in
-- storage/plan.lua; all bridge I/O goes through a BridgePort (ctx.bridge), so
-- this file just sequences the export/craft passes and applies the tokens.
----------------------------------------------------------------------------

local plan = require("storage.plan")

local M = {}

-- Exposed for unit tests (pure, delegates to plan).
M.equipNames = plan.equipNames

-- Equipment candidates ({name, fingerprint}) in priority order: the colony's own
-- accept list (vanilla-first), else the synthesized tier range (names only) when
-- no accept list is present.
local function equipCandidates(item, af)
  if item.acceptItems and #item.acceptItems > 0 then return plan.orderAccept(item.acceptItems) end
  local out = {}
  for _, n in ipairs(plan.equipNames(item, af)) do out[#out + 1] = { name = n } end
  return out
end

-- Resolve a request to fingerprint-based candidates via the bridge port.
-- Equipment is resolved by the accept item's exact FINGERPRINT (falling back to
-- name only when none is known): a bare-name lookup grabs enchanted/damaged
-- variants that share the id (e.g. a "Blessed Iron Leggings"), which the colony
-- rejects. Stops once a stocked AND a craftable candidate are found (accept lists
-- can be ~40 items -> avoid that many bridge calls).
local function resolve(bridge, item, cands)
  local out = {}
  if not item.equipment then
    local base = item.fingerprint and { fingerprint = item.fingerprint } or { name = item.item_name }
    local c = bridge.getItem(base); if c then out[#out + 1] = c end
    return out
  end
  local haveStocked, haveCraft = false, false
  for _, cand in ipairs(cands) do
    local filter = cand.fingerprint and { fingerprint = cand.fingerprint } or { name = cand.name }
    local c = bridge.getItem(filter)
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
    local cands = item.equipment and equipCandidates(item, af) or nil
    local have = 0
    if cands then
      local names = {}
      for _, c in ipairs(cands) do names[#names + 1] = c.name end
      have = plan.warehouseHave(ctx.warehouse, names, true)  -- pristine only: skip enchanted/damaged
    end
    if have >= item.count then
      item.provided = item.count
      item.displayColor = "filled"
      goto continue
    end
    local need = item.count - have

    local resolved = resolve(bridge, item, cands)
    local stocked, craftFilter = plan.selectCandidates(resolved)

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

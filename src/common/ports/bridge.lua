----------------------------------------------------------------------------
-- common/ports/bridge.lua -- adapter over the ME/RS bridge peripheral.
--
-- The ONLY place bridge methods are called. Detects the stack-size field
-- ("amount" on ME, "count" on RS) ONCE from the first successful getItem and
-- normalizes it forever -- so there is no module-level singleton to leak across
-- colonies (the old storage/fulfill `quantityField`). Every call is guarded.
--
--   new(rawBridge, log) -> port
--   port.getItem(filter)     -> { filter, amount, craftable } | nil
--   port.exportItem(f, dst)  -> providedCount   (tries peripheral then plain)
--   port.isCrafting(filter)  -> bool
--   port.craftItem(filter)   -> bool  (did the craft CALL succeed, per pcall --
--                                      matches the original safeCall behaviour)
----------------------------------------------------------------------------

local M = {}

function M.new(raw, log)
  -- safeCall: run fn under pcall, log failures; returns the pcall ok flag.
  local safeCall = (log and log.safeCall) or function(fn) return (pcall(fn)) end

  local quantityField = nil  -- "amount" (ME) or "count" (RS), detected once
  local port = {}

  -- Look up an item; normalize the stock amount and prefer the storage-side
  -- fingerprint for exact later export/craft.
  function port.getItem(filter)
    local d
    local ok = pcall(function() d = raw.getItem(filter) end)
    if not ok or type(d) ~= "table" then return nil end
    if not quantityField then
      if type(d.amount) == "number" then quantityField = "amount"
      elseif type(d.count) == "number" then quantityField = "count" end
    end
    return {
      filter = d.fingerprint and { fingerprint = d.fingerprint } or filter,
      amount = (quantityField and d[quantityField]) or 0,
      craftable = d.isCraftable,
    }
  end

  -- Export up to the filter's count into `dst`; returns amount provided.
  function port.exportItem(filter, dst)
    local provided = 0
    local ok = pcall(function() provided = raw.exportItemToPeripheral(filter, dst) end)
    if not ok then pcall(function() provided = raw.exportItem(filter, dst) end) end
    return provided or 0
  end

  function port.isCrafting(filter)
    local r = false
    safeCall(function() r = raw.isItemCrafting(filter) end)
    return r
  end

  function port.craftItem(filter)
    return safeCall(function() return raw.craftItem(filter) end)
  end

  return port
end

return M

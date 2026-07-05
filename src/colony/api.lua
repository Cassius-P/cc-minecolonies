----------------------------------------------------------------------------
-- colony/api.lua -- one scan of the colony_integrator: the I/O boundary.
--
-- Fetches a raw snapshot (every integrator call wrapped in pcall via the g()
-- helper, since the peripheral can throw or return nil), discovers the ME/RS
-- bridge + warehouse, hands the snapshot to the PURE shaper (colony/shape), then
-- runs the effectful CCxM auto-fulfill when the shaper says it may. The pure
-- data-shaping lives in colony/shape.lua so it can be unit-tested without a
-- live colony.
----------------------------------------------------------------------------

local fulfill = require("storage.fulfill")
local perif   = require("common.peripherals")
local shape   = require("colony.shape")

local M = {}

-- gather(ctx): ctx = { colony, config, log }
function M.gather(ctx)
  local colony, config, log = ctx.colony, ctx.config, ctx.log
  local function g(fn, d) local ok, v = pcall(fn); if ok and v ~= nil then return v else return d end end

  local citizens = g(function() return colony.getCitizens() end, {})

  local snapshot = {
    citizens  = citizens,
    buildings = g(function() return colony.getBuildings() end, {}),
    orders    = g(function() return colony.getWorkOrders() end, {}),
    visitors  = g(function() return colony.getVisitors() end, {}),
    requests  = g(function() return colony.getRequests() end, {}),
    stats = {
      name = g(colony.getColonyName, "?"), id = g(colony.getColonyID, "?"),
      happiness = g(colony.getHappiness, 0),
      pop = g(colony.amountOfCitizens, #citizens), maxPop = g(colony.maxOfCitizens, 0),
      attack = g(colony.isUnderAttack, false), raid = g(colony.isUnderRaid, false),
      sites = g(colony.amountOfConstructionSites, 0), graves = g(colony.amountOfGraves, 0),
    },
  }

  local bridge  = perif.findBridge(config)
  local storage = perif.findStorage(config)
  local caps = { bridge = bridge ~= nil, storage = storage ~= nil }

  local d = shape.buildData(snapshot, config, caps, log)

  -- CCxM auto-fulfill: effectful. Mutates each request item's displayColor in
  -- place (shared with d.requests) via the ME/RS bridge. Order: eq, bd, ot.
  if d.autofulfill.canAuto then
    local fctx = { bridge = bridge, storage = storage, config = config, log = log }
    fulfill.handle(d.reqGroups.eq, fctx)
    fulfill.handle(d.reqGroups.bd, fctx)
    fulfill.handle(d.reqGroups.ot, fctx)
  end

  return d
end

return M

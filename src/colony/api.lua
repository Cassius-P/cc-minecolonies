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

local fulfill    = require("storage.fulfill")
local perif      = require("common.peripherals")
local shape      = require("colony.shape")
local colonyPort = require("common.ports.colony")
local bridgePort = require("common.ports.bridge")

local M = {}

-- gather(ctx): ctx = { colony, config, log }
function M.gather(ctx)
  local config, log = ctx.config, ctx.log

  -- I/O: one pcall-guarded snapshot through the colony adapter.
  local snapshot = colonyPort.new(ctx.colony).snapshot()

  local bridge  = perif.findBridge(config)
  local storage = perif.findStorage(config)
  local caps = { bridge = bridge ~= nil, storage = storage ~= nil }

  local d = shape.buildData(snapshot, config, caps, log)

  -- CCxM auto-fulfill: effectful. Mutates each request item's displayColor in
  -- place (shared with d.requests) via the ME/RS bridge port. Order: eq, bd, ot.
  if d.autofulfill.canAuto then
    local whList
    if storage then pcall(function() whList = peripheral.call(storage, "list") end) end
    local fctx = { bridge = bridgePort.new(bridge, log), storage = storage, warehouse = whList, config = config, log = log }
    fulfill.handle(d.reqGroups.eq, fctx)
    fulfill.handle(d.reqGroups.bd, fctx)
    fulfill.handle(d.reqGroups.ot, fctx)
  end

  return d
end

return M

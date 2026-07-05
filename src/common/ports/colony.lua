----------------------------------------------------------------------------
-- common/ports/colony.lua -- adapter over the colony_integrator peripheral.
--
-- The ONLY place colony_integrator methods are called for a scan. Every call is
-- pcall-guarded (the peripheral can throw or return nil across MineColonies
-- versions) and defaulted, so callers get a clean snapshot table and never see a
-- raw peripheral error.
--
--   new(integrator) -> port
--   port.snapshot() -> { stats, citizens, buildings, orders, visitors, requests }
--   port.citizens() -> citizen list          (cheap single read; modal poll)
--   port.raw()      -> the wrapped peripheral (escape hatch, e.g. the dump)
----------------------------------------------------------------------------

local M = {}

local function g(fn, d) local ok, v = pcall(fn); if ok and v ~= nil then return v else return d end end

function M.new(integrator)
  local c = integrator
  local port = {}

  function port.citizens() return g(function() return c.getCitizens() end, {}) end

  function port.snapshot()
    local citizens = port.citizens()
    return {
      citizens  = citizens,
      buildings = g(function() return c.getBuildings() end, {}),
      orders    = g(function() return c.getWorkOrders() end, {}),
      visitors  = g(function() return c.getVisitors() end, {}),
      requests  = g(function() return c.getRequests() end, {}),
      stats = {
        name = g(c.getColonyName, "?"), id = g(c.getColonyID, "?"),
        happiness = g(c.getHappiness, 0),
        pop = g(c.amountOfCitizens, #citizens), maxPop = g(c.maxOfCitizens, 0),
        attack = g(c.isUnderAttack, false), raid = g(c.isUnderRaid, false),
        sites = g(c.amountOfConstructionSites, 0), graves = g(c.amountOfGraves, 0),
      },
    }
  end

  function port.raw() return c end

  return port
end

return M

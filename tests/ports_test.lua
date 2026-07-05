-- Tests for the peripheral adapters using FAKE raw peripherals (no CC needed).
local t          = require("helper")
local colonyPort = require("common.ports.colony")
local bridgePort = require("common.ports.bridge")

local nolog = { safeCall = function(fn) return (pcall(fn)) end, write = function() end }

--------------------------------------------------------------------------
-- ColonyPort
--------------------------------------------------------------------------
t.case("colony snapshot shape + pcall defaults")
do
  local fake = {
    getCitizens = function() return { { id = 1 }, { id = 2 } } end,
    getBuildings = function() return { { type = "builder" } } end,
    getWorkOrders = function() return {} end,
    getVisitors = function() return {} end,
    getRequests = function() return {} end,
    getColonyName = function() return "Base" end,
    getColonyID = function() return 42 end,
    getHappiness = function() return 9 end,
    amountOfCitizens = function() return 2 end,
    maxOfCitizens = function() return 20 end,
    isUnderAttack = function() return false end,
    isUnderRaid = function() return false end,
    amountOfConstructionSites = function() return 0 end,
    -- getGraves intentionally throws to exercise the pcall default:
    amountOfGraves = function() error("boom") end,
  }
  local snap = colonyPort.new(fake).snapshot()
  t.eq(#snap.citizens, 2)
  t.eq(snap.stats.name, "Base")
  t.eq(snap.stats.id, 42)
  t.eq(snap.stats.maxPop, 20)
  t.eq(snap.stats.graves, 0, "throwing getter -> default")
end

t.case("colony port survives a fully broken integrator")
do
  local broken = setmetatable({}, { __index = function() return function() error("no") end end })
  local snap = colonyPort.new(broken).snapshot()
  t.eq(#snap.citizens, 0, "defaults to empty")
  t.eq(snap.stats.name, "?")
end

--------------------------------------------------------------------------
-- BridgePort
--------------------------------------------------------------------------
t.case("bridge getItem normalizes ME 'amount' + keeps storage fingerprint")
do
  local raw = { getItem = function() return { amount = 5, isCraftable = true, fingerprint = "fp1" } end }
  local bp = bridgePort.new(raw, nolog)
  local it = bp.getItem({ name = "x" })
  t.eq(it.amount, 5)
  t.truthy(it.craftable)
  t.eq(it.filter.fingerprint, "fp1", "prefers storage-side fingerprint")
end

t.case("bridge getItem normalizes RS 'count' + passes filter through")
do
  local raw = { getItem = function() return { count = 3, isCraftable = false } end }
  local bp = bridgePort.new(raw, nolog)
  local it = bp.getItem({ name = "y" })
  t.eq(it.amount, 3)
  t.eq(it.filter.name, "y", "no fingerprint -> original filter")
end

t.case("bridge getItem nil / throw -> nil")
do
  local bp = bridgePort.new({ getItem = function() error("x") end }, nolog)
  t.eq(bp.getItem({}), nil)
end

t.case("bridge exportItem falls back to exportItem when peripheral variant missing")
do
  local calls = {}
  local raw = {
    exportItemToPeripheral = function() error("unsupported") end,
    exportItem = function(_f, _d) calls.plain = true; return 7 end,
  }
  local bp = bridgePort.new(raw, nolog)
  t.eq(bp.exportItem({ count = 10 }, "barrel"), 7)
  t.truthy(calls.plain, "used fallback")
end

t.case("bridge craftItem returns pcall-ok flag, not craftItem's value")
do
  -- craftItem returns false but does NOT throw -> ok flag is true -> 'crafting'.
  local bp = bridgePort.new({ craftItem = function() return false end }, nolog)
  t.truthy(bp.craftItem({}), "no throw -> true")
  local bad = bridgePort.new({ craftItem = function() error("nope") end }, nolog)
  t.falsy(bad.craftItem({}), "throw -> false")
end

t.case("bridge isCrafting returns the query result / false on throw")
do
  t.truthy(bridgePort.new({ isItemCrafting = function() return true end }, nolog).isCrafting({}))
  t.falsy(bridgePort.new({ isItemCrafting = function() error("x") end }, nolog).isCrafting({}))
end

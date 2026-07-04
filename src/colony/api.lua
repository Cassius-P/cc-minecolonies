----------------------------------------------------------------------------
-- colony/api.lua -- one scan of the colony_integrator into a normalized `data`
-- table, running suggestions/roster + optional CCxM auto-fulfill.
----------------------------------------------------------------------------

local util     = require("common.util")
local skills   = require("colony.skills")
local advisor  = require("colony.advisor")
local requests = require("colony.requests")
local fulfill  = require("storage.fulfill")
local perif    = require("common.peripherals")

local M = {}

-- gather(ctx): ctx = { colony, config, log }
function M.gather(ctx)
  local colony, config, log = ctx.colony, ctx.config, ctx.log
  local function g(fn, d) local ok, v = pcall(fn); if ok and v ~= nil then return v else return d end end

  local citizens  = g(function() return colony.getCitizens() end, {})
  local buildings = g(function() return colony.getBuildings() end, {})
  local orders    = g(function() return colony.getWorkOrders() end, {})
  local visitors  = g(function() return colony.getVisitors() end, {})

  local employed, idle = 0, 0
  for _, c in ipairs(citizens) do
    if skills.isUnemployed(c) then idle = idle + 1 else employed = employed + 1 end
  end

  local d = {
    name = g(colony.getColonyName, "?"), id = g(colony.getColonyID, "?"),
    happiness = g(colony.getHappiness, 0),
    pop = g(colony.amountOfCitizens, #citizens), maxPop = g(colony.maxOfCitizens, 0),
    attack = g(colony.isUnderAttack, false), raid = g(colony.isUnderRaid, false),
    sites = g(colony.amountOfConstructionSites, 0), graves = g(colony.amountOfGraves, 0),
    total = #citizens, employed = employed, idle = idle, buildings = #buildings,
    visitors = type(visitors) == "table" and #visitors or 0,
    orders = type(orders) == "table" and orders or {},
    suggestions = advisor.computeSuggestions(citizens, buildings, visitors, {
      replace  = config.suggestions and config.suggestions.replaceMargin or 1,
      reassign = config.suggestions and config.suggestions.reassignMargin or 1,
    }),
  }
  d.roster = advisor.computeRoster(citizens, buildings, d.suggestions)

  -- Unique job types present in the colony (for the Job Skills section).
  local jobset = {}
  for _, b in ipairs(buildings) do
    local jk = b.type or util.jobKey(b.name)
    if jk and skills.JOB_SKILLS[jk] and b.built ~= false then jobset[jk] = true end
  end
  local jobTypes = {}
  for jk in pairs(jobset) do jobTypes[#jobTypes + 1] = jk end
  table.sort(jobTypes)
  d.jobTypes = jobTypes

  -- Requests + optional auto-fulfill (CCxM).
  local bridge  = perif.findBridge(config)
  local storage = perif.findStorage(config)
  d.bridgePresent  = bridge ~= nil
  d.storagePresent = storage ~= nil

  local eq, bd, ot = {}, {}, {}
  pcall(function()
    eq, bd, ot = requests.categorize(g(function() return colony.getRequests() end, {}), log)
  end)

  local af = config.autofulfill
  local mode, canAuto = "MANUAL", false
  if af.enabled and bridge and storage then
    canAuto = true
    if af.pauseUnderAttack and (d.attack or d.raid) then canAuto, mode = false, "PAUSED raid" end
    if canAuto and af.minHappiness > 0 and d.happiness < af.minHappiness then canAuto, mode = false, "PAUSED low happy" end
    if canAuto then
      local fctx = { bridge = bridge, storage = storage, config = config, log = log }
      fulfill.handle(eq, fctx); fulfill.handle(bd, fctx); fulfill.handle(ot, fctx)
      mode = "AUTO"
    end
  elseif not (bridge and storage) then
    mode = "no bridge"
  end

  local all = {}
  for _, l in ipairs({ bd, eq, ot }) do for _, it in ipairs(l) do all[#all + 1] = it end end
  d.requests = all
  d.reqMode = mode
  return d
end

return M

----------------------------------------------------------------------------
-- colony/shape.lua -- PURE shaping of one colony snapshot into the normalized
-- `data` table the UI renders. No peripheral / bridge / http calls: given a
-- plain snapshot it is fully deterministic and unit-testable.
--
-- buildData(snapshot, config, caps, log) where
--   snapshot = { stats={name,id,happiness,pop,maxPop,attack,raid,sites,graves},
--                citizens, buildings, orders, visitors, requests }
--   caps     = { bridge=bool, storage=bool }   -- discovered by the I/O layer
--   log      = optional logger (only used to warn on item-less requests)
--
-- Returns `data` with suggestions/roster, jobTypes, work-order builderName
-- resolution, the categorized request groups (reqGroups) + a flattened
-- `requests` list (SAME item tables, so a later fulfill pass colouring the
-- groups shows through), and the pure auto-fulfill decision (autofulfill/reqMode).
-- The effectful fulfill execution stays in colony/api.lua.
----------------------------------------------------------------------------

local util     = require("common.util")
local skills   = require("colony.skills")
local advisor  = require("colony.advisor")
local requests = require("colony.requests")
local index    = require("colony.roster_index")

local M = {}

function M.buildData(snapshot, config, caps, log)
  local citizens  = snapshot.citizens  or {}
  local buildings = snapshot.buildings or {}
  local orders    = snapshot.orders
  local visitors  = snapshot.visitors
  local stats     = snapshot.stats or {}
  caps = caps or {}

  local employed, idle = 0, 0
  for _, c in ipairs(citizens) do
    if skills.isUnemployed(c) then idle = idle + 1 else employed = employed + 1 end
  end

  -- One shared roster index per scan, threaded through both advisor passes
  -- (safe: suggestions mutate only slot free counts, which the roster ignores).
  local ix = index.prepare(citizens, buildings)

  local d = {
    name = stats.name or "?", id = stats.id or "?",
    happiness = stats.happiness or 0,
    pop = stats.pop or #citizens, maxPop = stats.maxPop or 0,
    attack = stats.attack or false, raid = stats.raid or false,
    sites = stats.sites or 0, graves = stats.graves or 0,
    total = #citizens, employed = employed, idle = idle, buildings = #buildings,
    visitors = type(visitors) == "table" and #visitors or 0,
    orders = type(orders) == "table" and orders or {},
    suggestions = advisor.computeSuggestions(citizens, buildings, visitors, {
      replace  = config.suggestions and config.suggestions.replaceMargin or 1,
      reassign = config.suggestions and config.suggestions.reassignMargin or 1,
    }, ix),
  }
  d.roster = advisor.computeRoster(citizens, buildings, d.suggestions, ix)

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

  -- Resolve each work order's builder to a NAME. The integrator gives `builder`
  -- as the builder-hut position (or, on some versions, a table with a name);
  -- map the position to the hut's assigned citizen. Sets o.builderName.
  local bByLoc = {}
  for _, b in ipairs(buildings) do
    if type(b.location) == "table" then bByLoc[util.locStr(b.location)] = b end
  end
  for _, o in ipairs(d.orders) do
    local bl = o.builder
    if type(bl) == "table" then
      if type(bl.name) == "string" and bl.name ~= "" then
        o.builderName = bl.name
      else
        local loc = bl.location or bl
        local hut = type(loc) == "table" and bByLoc[util.locStr(loc)]
        if hut and type(hut.citizens) == "table" and hut.citizens[1] then
          o.builderName = hut.citizens[1].name
        end
      end
    end
  end

  d.bridgePresent  = caps.bridge and true or false
  d.storagePresent = caps.storage and true or false

  -- Categorize requests (equipment / builder / other).
  local eq, bd, ot = {}, {}, {}
  pcall(function()
    eq, bd, ot = requests.categorize(snapshot.requests or {}, log)
  end)
  d.reqGroups = { eq = eq, bd = bd, ot = ot }

  -- Auto-fulfill gating decision (pure given caps + config + stats). The actual
  -- fulfill execution happens in colony/api.lua when canAuto is true.
  local af = config.autofulfill
  local mode, canAuto = "MANUAL", false
  if af.enabled and caps.bridge and caps.storage then
    canAuto = true
    if af.pauseUnderAttack and (d.attack or d.raid) then canAuto, mode = false, "PAUSED raid" end
    if canAuto and af.minHappiness > 0 and d.happiness < af.minHappiness then canAuto, mode = false, "PAUSED low happy" end
    if canAuto then mode = "AUTO" end
  elseif not (caps.bridge and caps.storage) then
    mode = "no bridge"
  end
  d.autofulfill = { canAuto = canAuto, mode = mode }
  d.reqMode = mode

  -- Flatten to one list (order: builder, equipment, other). Same item tables as
  -- reqGroups, so a fulfill pass colouring the groups is visible here too.
  local all = {}
  for _, l in ipairs({ bd, eq, ot }) do for _, it in ipairs(l) do all[#all + 1] = it end end
  d.requests = all

  return d
end

return M

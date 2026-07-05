----------------------------------------------------------------------------
-- colony/roster_index.lua -- prepare the shared, derived index used by BOTH the
-- suggestion passes (colony/suggest/*) and computeRoster. The caller that runs
-- them back-to-back (colony/shape, every scan) prepares it once and passes it
-- to both advisor entry points; each also self-prepares when called standalone.
--
-- prepare(citizens, buildings) -> index with:
--   byId        id -> citizen
--   idle        unemployed citizens
--   employed    { {c, jc, cur=score-at-current-job}, ... }
--   openSlots   job-building recs {jk,pr,se,loc,workers,free} with a free slot
--   fullB       job-building recs {jk,pr,se,loc,workers} that are full
--   recsByJob   jk -> { open={recs}, full={recs} }  (SAME rec tables as above,
--               so a pass decrementing rec.free is visible to later passes)
--   numbered    locStr -> { jk, num, count }  (stable Builder 1 / Builder 2 ...)
--   buildings   the raw building list (for tavern lookup etc.)
--   labelFor(loc, jk) -> "Builder 2" when several, else "Builder"
--   weakestOf(rec) -> weakestWorker, itsScore  (shared by replace/reassign/recruit)
----------------------------------------------------------------------------

local util   = require("common.util")
local skills = require("colony.skills")

local jobKey, locStr, cap = util.jobKey, util.locStr, util.capitalize
local JOB_SKILLS, maxSlotsFor = skills.JOB_SKILLS, skills.maxSlotsFor
local scoreFor = skills.scoreFor

local M = {}

-- Number buildings of the same job type: locStr -> { jk, num, count }.
-- Stable order by location so numbering is consistent across scans.
local function numberBuildings(buildings)
  local groups = {}
  for _, b in ipairs(buildings) do
    local jk = b.type or jobKey(b.name)
    if jk and JOB_SKILLS[jk] and b.built ~= false then
      groups[jk] = groups[jk] or {}
      groups[jk][#groups[jk] + 1] = b
    end
  end
  local map = {}
  for jk, list in pairs(groups) do
    table.sort(list, function(a, b) return locStr(a.location) < locStr(b.location) end)
    for i, b in ipairs(list) do map[locStr(b.location)] = { jk = jk, num = i, count = #list } end
  end
  return map
end

-- "Builder 2" when there are several, else just "Builder".
local function labelFor(map, loc, jk)
  local info = map[locStr(loc)]
  if info and info.count > 1 then return cap(jk) .. " " .. info.num end
  return cap(jk)
end

function M.prepare(citizens, buildings)
  local byId = {}
  for _, c in ipairs(citizens) do byId[c.id] = c end

  local idle = {}
  for _, c in ipairs(citizens) do if skills.isUnemployed(c) then idle[#idle + 1] = c end end

  -- Employed citizens with a known job, and their score at that job.
  local employed = {}
  for _, c in ipairs(citizens) do
    if not skills.isUnemployed(c) then
      local jc = type(c.work) == "table" and c.work.type
      local sk = jc and JOB_SKILLS[jc]
      if sk then employed[#employed + 1] = { c = c, jc = jc, cur = scoreFor(c, sk[1], sk[2]) } end
    end
  end

  -- Classify job buildings into those with an open slot vs. full.
  local openSlots, fullB = {}, {}
  for _, b in ipairs(buildings) do
    local jk = b.type or jobKey(b.name)
    local sk = jk and JOB_SKILLS[jk]
    if sk and b.built ~= false then
      local workers = (type(b.citizens) == "table") and b.citizens or {}
      local rec = { jk = jk, pr = sk[1], se = sk[2], loc = b.location, workers = workers }
      local free = maxSlotsFor(jk, b.level) - #workers
      if free > 0 then rec.free = free; openSlots[#openSlots + 1] = rec else fullB[#fullB + 1] = rec end
    end
  end

  -- Index recs by job type (SAME rec tables, so free-decrements carry across passes).
  local recsByJob = {}
  for _, rec in ipairs(openSlots) do
    recsByJob[rec.jk] = recsByJob[rec.jk] or { open = {}, full = {} }
    table.insert(recsByJob[rec.jk].open, rec)
  end
  for _, rec in ipairs(fullB) do
    recsByJob[rec.jk] = recsByJob[rec.jk] or { open = {}, full = {} }
    table.insert(recsByJob[rec.jk].full, rec)
  end

  local numbered = numberBuildings(buildings)

  local ix = {
    byId = byId, idle = idle, employed = employed,
    openSlots = openSlots, fullB = fullB, recsByJob = recsByJob,
    numbered = numbered, buildings = buildings,
  }

  function ix.labelFor(loc, jk) return labelFor(numbered, loc, jk) end

  function ix.weakestOf(rec)
    local weak, ws = nil, math.huge
    for _, w in ipairs(rec.workers) do
      local full = byId[w.id]
      local s = full and scoreFor(full, rec.pr, rec.se) or 0
      if s < ws then weak, ws = w, s end
    end
    return weak, ws
  end

  return ix
end

return M

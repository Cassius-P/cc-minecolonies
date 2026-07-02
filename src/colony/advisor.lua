----------------------------------------------------------------------------
-- colony/advisor.lua -- citizen->job matching.
--
-- computeSuggestions: greedy allocation so each idle citizen appears in at
-- most ONE suggestion; open slots take their best-scoring idle candidate
-- first, then remaining idle citizens may replace an under-skilled worker in a
-- full hut (only if the skill gain clears REPLACE_MARGIN).
-- computeRoster: flatten every job building + its workers + empty slots into
-- display rows tagged ok / replace / assign / empty.
----------------------------------------------------------------------------

local util   = require("common.util")
local skills = require("colony.skills")

local jobKey, locStr = util.jobKey, util.locStr
local JOB_SKILLS, maxSlotsFor = skills.JOB_SKILLS, skills.maxSlotsFor
local scoreFor = skills.scoreFor

local M = {}

function M.computeSuggestions(citizens, buildings)
  local byId, idle = {}, {}
  for _, c in ipairs(citizens) do byId[c.id] = c end
  for _, c in ipairs(citizens) do if skills.isUnemployed(c) then idle[#idle + 1] = c end end

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

  local used, out = {}, {}

  -- ASSIGN: rank every (idle citizen, open slot) pair; take best first.
  local prs = {}
  for _, slot in ipairs(openSlots) do
    for _, c in ipairs(idle) do
      prs[#prs + 1] = { c = c, slot = slot, score = scoreFor(c, slot.pr, slot.se) }
    end
  end
  table.sort(prs, function(a, b) return a.score > b.score end)
  for _, p in ipairs(prs) do
    if not used[p.c.id] and p.slot.free > 0 then
      used[p.c.id] = true
      p.slot.free = p.slot.free - 1
      out[#out + 1] = { kind = "assign", job = p.slot.jk, building = { location = p.slot.loc },
        candidate = { name = p.c.name, id = p.c.id, score = p.score }, gain = p.score }
    end
  end

  -- REPLACE: for each full hut, weakest worker vs. best still-unused idle citizen.
  local repl = {}
  for _, fb in ipairs(fullB) do
    local weak, ws = nil, math.huge
    for _, w in ipairs(fb.workers) do
      local full = byId[w.id]
      local s = full and scoreFor(full, fb.pr, fb.se) or 0
      if s < ws then weak, ws = w, s end
    end
    local cand, cs = nil, -1
    for _, c in ipairs(idle) do
      if not used[c.id] then
        local s = scoreFor(c, fb.pr, fb.se)
        if s > cs then cand, cs = c, s end
      end
    end
    if weak and cand and (cs - ws) >= skills.REPLACE_MARGIN then
      repl[#repl + 1] = { fb = fb, weak = weak, ws = ws, cand = cand, cs = cs, gain = cs - ws }
    end
  end
  table.sort(repl, function(a, b) return a.gain > b.gain end)
  for _, r in ipairs(repl) do
    if not used[r.cand.id] then
      used[r.cand.id] = true
      out[#out + 1] = { kind = "replace", job = r.fb.jk, building = { location = r.fb.loc },
        candidate = { name = r.cand.name, id = r.cand.id, score = r.cs },
        target = { name = r.weak.name, id = r.weak.id, score = r.ws }, gain = r.gain }
    end
  end

  -- Fill empty slots first (assign), then replacements, each by descending gain.
  table.sort(out, function(a, b)
    if a.kind ~= b.kind then return a.kind == "assign" end
    return a.gain > b.gain
  end)
  while #out > skills.MAX_SUGGESTIONS do table.remove(out) end
  return out
end

function M.computeRoster(citizens, buildings, sugs)
  local byId = {}
  for _, c in ipairs(citizens) do byId[c.id] = c end
  local assignAt, replaceAt = {}, {}
  for _, s in ipairs(sugs) do
    local k = locStr(s.building.location)
    if s.kind == "assign" then assignAt[k] = s else replaceAt[k] = s end
  end

  local flat = {}
  for _, b in ipairs(buildings) do
    local jk = b.type or jobKey(b.name)
    local sk = jk and JOB_SKILLS[jk]
    if sk and b.built ~= false then
      local pr, se = sk[1], sk[2]
      local k = locStr(b.location)
      local workers = (type(b.citizens) == "table") and b.citizens or {}
      local maxS = maxSlotsFor(jk, b.level)
      flat[#flat + 1] = { kind = "head", building = jk, filled = #workers, max = maxS }
      for _, w in ipairs(workers) do
        local full = byId[w.id]
        local sc = full and scoreFor(full, pr, se) or 0
        local rep = replaceAt[k]
        if rep and rep.target and rep.target.id == w.id then
          flat[#flat + 1] = { kind = "worker", name = w.name, status = "replace",
            repl = rep.candidate.name, sug = rep }
        else
          flat[#flat + 1] = { kind = "worker", name = w.name, status = "ok", score = sc }
        end
      end
      for i = 1, (maxS - #workers) do
        local asg = assignAt[k]
        if asg and i == 1 then
          flat[#flat + 1] = { kind = "slot", status = "assign", cand = asg.candidate.name, sug = asg }
        else
          flat[#flat + 1] = { kind = "slot", status = "empty" }
        end
      end
    end
  end
  return flat
end

return M

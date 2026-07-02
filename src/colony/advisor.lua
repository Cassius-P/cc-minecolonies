----------------------------------------------------------------------------
-- colony/advisor.lua -- citizen->job matching.
--
-- computeSuggestions produces three kinds of suggestion (each citizen appears
-- at most once):
--   * assign   - an idle citizen fills an open slot.
--   * replace  - an idle citizen replaces an under-skilled worker in a full hut.
--   * reassign - an EMPLOYED citizen would be a much better fit at another job
--                (open slot, or displacing a weaker worker there).
-- computeRoster flattens every building + workers into display rows.
--
-- margins = { replace = n, reassign = n } gate replace/reassign (skill-gap
-- thresholds); they fall back to the skills defaults when omitted.
----------------------------------------------------------------------------

local util   = require("common.util")
local skills = require("colony.skills")

local jobKey, locStr = util.jobKey, util.locStr
local JOB_SKILLS, maxSlotsFor = skills.JOB_SKILLS, skills.maxSlotsFor
local scoreFor = skills.scoreFor

local M = {}

function M.computeSuggestions(citizens, buildings, margins)
  local REPL = (margins and margins.replace) or skills.REPLACE_MARGIN
  local REASS = (margins and margins.reassign) or skills.REASSIGN_MARGIN

  local byId, idle = {}, {}
  for _, c in ipairs(citizens) do byId[c.id] = c end
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
    if weak and cand and (cs - ws) >= REPL then
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

  -- REASSIGN: an employed citizen who fits another job much better. Considers
  -- both remaining open slots and full huts (displacing the weakest worker).
  local moves = {}
  for _, slot in ipairs(openSlots) do
    if slot.free > 0 then
      for _, e in ipairs(employed) do
        if not used[e.c.id] and e.jc ~= slot.jk then
          local sNew = scoreFor(e.c, slot.pr, slot.se)
          local imp = sNew - e.cur
          if imp >= REASS then
            moves[#moves + 1] = { slot = slot, e = e, sNew = sNew, benefit = imp, open = true }
          end
        end
      end
    end
  end
  for _, fb in ipairs(fullB) do
    local weak, ws = nil, math.huge
    for _, w in ipairs(fb.workers) do
      local full = byId[w.id]
      local s = full and scoreFor(full, fb.pr, fb.se) or 0
      if s < ws then weak, ws = w, s end
    end
    for _, e in ipairs(employed) do
      if not used[e.c.id] and weak and weak.id ~= e.c.id and e.jc ~= fb.jk then
        local sNew = scoreFor(e.c, fb.pr, fb.se)
        local imp = sNew - e.cur
        if imp > 0 and (sNew - ws) >= math.max(REPL, REASS) then
          moves[#moves + 1] = { slot = fb, e = e, sNew = sNew, weak = weak, ws = ws,
            benefit = sNew - ws, open = false }
        end
      end
    end
  end
  table.sort(moves, function(a, b) return a.benefit > b.benefit end)
  for _, m in ipairs(moves) do
    if not used[m.e.c.id] then
      used[m.e.c.id] = true
      if m.open and m.slot.free then m.slot.free = m.slot.free - 1 end
      out[#out + 1] = { kind = "reassign", job = m.slot.jk, from = m.e.jc,
        building = { location = m.slot.loc },
        candidate = { name = m.e.c.name, id = m.e.c.id, score = m.sNew },
        target = m.weak and { name = m.weak.name, id = m.weak.id, score = m.ws } or nil,
        gain = m.benefit }
    end
  end

  -- Order: assign, then replace, then reassign; each by descending gain.
  local rank = { assign = 1, replace = 2, reassign = 3 }
  table.sort(out, function(a, b)
    if rank[a.kind] ~= rank[b.kind] then return rank[a.kind] < rank[b.kind] end
    return a.gain > b.gain
  end)
  while #out > skills.MAX_SUGGESTIONS do table.remove(out) end
  return out
end

function M.computeRoster(citizens, buildings, sugs)
  local byId = {}
  for _, c in ipairs(citizens) do byId[c.id] = c end
  local assignAt, replaceAt, reassignAt = {}, {}, {}
  for _, s in ipairs(sugs) do
    if s.kind == "assign" then
      assignAt[locStr(s.building.location)] = s
    elseif s.kind == "replace" then
      replaceAt[locStr(s.building.location)] = s
    elseif s.kind == "reassign" then
      reassignAt[s.candidate.id] = s   -- keyed by the citizen who should move
    end
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
        local rea = reassignAt[w.id]
        local rep = replaceAt[k]
        if rea then
          flat[#flat + 1] = { kind = "worker", name = w.name, status = "reassign",
            to = rea.job, sug = rea }
        elseif rep and rep.target and rep.target.id == w.id then
          flat[#flat + 1] = { kind = "worker", name = w.name, status = "replace",
            repl = rep.candidate.name, sug = rep }
        else
          local full = byId[w.id]
          flat[#flat + 1] = { kind = "worker", name = w.name, status = "ok",
            score = full and scoreFor(full, pr, se) or 0 }
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

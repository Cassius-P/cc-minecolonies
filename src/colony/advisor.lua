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
local cap = util.capitalize
local JOB_SKILLS, maxSlotsFor = skills.JOB_SKILLS, skills.maxSlotsFor
local scoreFor, skillLevel = skills.scoreFor, skills.skillLevel

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

function M.computeSuggestions(citizens, buildings, visitors, margins)
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
        pri = p.slot.pr, sec = p.slot.se,
        candidate = { name = p.c.name, id = p.c.id, score = p.score, location = p.c.location,
          pri = skillLevel(p.c, p.slot.pr), sec = skillLevel(p.c, p.slot.se) }, gain = p.score }
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
      local tgt = byId[r.weak.id]
      out[#out + 1] = { kind = "replace", job = r.fb.jk, building = { location = r.fb.loc },
        pri = r.fb.pr, sec = r.fb.se,
        candidate = { name = r.cand.name, id = r.cand.id, score = r.cs, location = r.cand.location,
          pri = skillLevel(r.cand, r.fb.pr), sec = skillLevel(r.cand, r.fb.se) },
        target = { name = r.weak.name, id = r.weak.id, score = r.ws,
          pri = tgt and skillLevel(tgt, r.fb.pr) or 0, sec = tgt and skillLevel(tgt, r.fb.se) or 0 },
        gain = r.gain }
    end
  end

  -- REASSIGN: move an employed citizen toward their SINGLE best-fit job (the
  -- job type present in the colony where they score highest). Only moving
  -- toward a citizen's best fit guarantees each applied move raises their score,
  -- so suggestions converge instead of oscillating (e.g. builder->guard->builder).
  local recsByJob = {}   -- jk -> { open = {recs w/ free}, full = {recs} }
  for _, rec in ipairs(openSlots) do
    recsByJob[rec.jk] = recsByJob[rec.jk] or { open = {}, full = {} }
    table.insert(recsByJob[rec.jk].open, rec)
  end
  for _, rec in ipairs(fullB) do
    recsByJob[rec.jk] = recsByJob[rec.jk] or { open = {}, full = {} }
    table.insert(recsByJob[rec.jk].full, rec)
  end

  local function weakestOf(rec)
    local weak, ws = nil, math.huge
    for _, w in ipairs(rec.workers) do
      local full = byId[w.id]
      local s = full and scoreFor(full, rec.pr, rec.se) or 0
      if s < ws then weak, ws = w, s end
    end
    return weak, ws
  end

  -- Best-fit job per employed citizen.
  local cands = {}
  for _, e in ipairs(employed) do
    local bestJk, bestScore = nil, -1
    for jk in pairs(recsByJob) do
      local sk = JOB_SKILLS[jk]
      local s = scoreFor(e.c, sk[1], sk[2])
      if s > bestScore then bestScore, bestJk = s, jk end
    end
    if bestJk and bestJk ~= e.jc and (bestScore - e.cur) >= REASS then
      cands[#cands + 1] = { e = e, jk = bestJk, score = bestScore, gain = bestScore - e.cur }
    end
  end
  table.sort(cands, function(a, b) return a.gain > b.gain end)

  for _, m in ipairs(cands) do
    if not used[m.e.c.id] then
      local rj = recsByJob[m.jk]
      local target
      for _, rec in ipairs(rj.open) do if rec.free > 0 then target = rec; break end end
      if target then
        used[m.e.c.id] = true
        target.free = target.free - 1
        local sk = JOB_SKILLS[m.jk]
        out[#out + 1] = { kind = "reassign", job = m.jk, from = m.e.jc,
          building = { location = target.loc }, pri = sk[1], sec = sk[2],
          candidate = { name = m.e.c.name, id = m.e.c.id, score = m.score, location = m.e.c.location,
            pri = skillLevel(m.e.c, sk[1]), sec = skillLevel(m.e.c, sk[2]) }, gain = m.gain }
      else
        -- No open slot: displace the weakest worker of the best full hut, if the
        -- gap clears the margin (and that worker isn't the same citizen).
        local bestRec, bWeak, bWs = nil, nil, math.huge
        for _, rec in ipairs(rj.full) do
          local w, ws = weakestOf(rec)
          if w and w.id ~= m.e.c.id and ws < bWs then bestRec, bWeak, bWs = rec, w, ws end
        end
        if bestRec and (m.score - bWs) >= math.max(REPL, REASS) then
          used[m.e.c.id] = true
          local tgt = byId[bWeak.id]
          out[#out + 1] = { kind = "reassign", job = m.jk, from = m.e.jc,
            building = { location = bestRec.loc }, pri = bestRec.pr, sec = bestRec.se,
            candidate = { name = m.e.c.name, id = m.e.c.id, score = m.score, location = m.e.c.location,
              pri = skillLevel(m.e.c, bestRec.pr), sec = skillLevel(m.e.c, bestRec.se) },
            target = { name = bWeak.name, id = bWeak.id, score = bWs,
              pri = tgt and skillLevel(tgt, bestRec.pr) or 0, sec = tgt and skillLevel(tgt, bestRec.se) or 0 },
            gain = m.score - bWs }
        end
      end
    end
  end

  -- RECRUIT: Tavern visitors as a SEPARATE candidate pool. Only worth it when a
  -- visitor fills an open slot or beats a weak worker AND beats the best free
  -- idle citizen who could otherwise take the job -- else recruiting (which
  -- costs items) buys nothing. Uses leftover open-slot capacity after the
  -- citizen passes above.
  if type(visitors) == "table" and #visitors > 0 then
    -- The integrator does not track visitor entity position (returns 0,0,0), so
    -- "locate" points at the Tavern where visitors gather / are recruited.
    local tavernLoc
    for _, b in ipairs(buildings) do
      if (b.type or jobKey(b.name)) == "tavern" then tavernLoc = b.location; break end
    end

    -- Best remaining idle-citizen score per job type (idle not already used).
    local bestIdleFor = {}
    for jk in pairs(recsByJob) do
      local sk, best = JOB_SKILLS[jk], -1
      for _, c in ipairs(idle) do
        if not used[c.id] then
          local s = scoreFor(c, sk[1], sk[2])
          if s > best then best = s end
        end
      end
      bestIdleFor[jk] = best
    end

    for _, v in ipairs(visitors) do
      -- Visitor's single best-fit job among the colony's job types.
      local bestJk, bestScore = nil, -1
      for jk in pairs(recsByJob) do
        local sk = JOB_SKILLS[jk]
        local s = scoreFor(v, sk[1], sk[2])
        if s > bestScore then bestScore, bestJk = s, jk end
      end
      if bestJk and bestScore > 0 and bestScore > (bestIdleFor[bestJk] or -1) then
        local rj = recsByJob[bestJk]
        local sk = JOB_SKILLS[bestJk]
        local rc = v.recruitCost
        local cost = (type(rc) == "table")
          and { count = rc.count or 1, displayName = rc.displayName or rc.name or "?" } or nil
        local vpri, vsec = skillLevel(v, sk[1]), skillLevel(v, sk[2])
        local target
        for _, rec in ipairs(rj.open) do if rec.free > 0 then target = rec; break end end
        if target then
          target.free = target.free - 1
          out[#out + 1] = { kind = "recruit", job = bestJk, building = { location = target.loc },
            pri = sk[1], sec = sk[2],
            candidate = { name = v.name, id = v.id, score = bestScore, location = v.location,
              pri = vpri, sec = vsec }, cost = cost, tavernLoc = tavernLoc,
            gain = bestScore - math.max(0, bestIdleFor[bestJk] or 0) }
        else
          -- No open slot: displace the weakest worker of the best full hut if the
          -- gap clears the replace margin.
          local bestRec, bWeak, bWs = nil, nil, math.huge
          for _, rec in ipairs(rj.full) do
            local w, ws = weakestOf(rec)
            if w and ws < bWs then bestRec, bWeak, bWs = rec, w, ws end
          end
          if bestRec and (bestScore - bWs) >= REPL then
            local tgt = byId[bWeak.id]
            out[#out + 1] = { kind = "recruit", job = bestJk, building = { location = bestRec.loc },
              pri = sk[1], sec = sk[2],
              candidate = { name = v.name, id = v.id, score = bestScore, location = v.location,
                pri = vpri, sec = vsec },
              target = { name = bWeak.name, id = bWeak.id, score = bWs,
                pri = tgt and skillLevel(tgt, sk[1]) or 0, sec = tgt and skillLevel(tgt, sk[2]) or 0 },
              cost = cost, tavernLoc = tavernLoc, gain = bestScore - bWs }
          end
        end
      end
    end
  end

  -- Order: assign, replace, reassign, then recruit (recruit costs items, so it
  -- ranks last); each group by descending gain.
  local rank = { assign = 1, replace = 2, reassign = 3, recruit = 4 }
  table.sort(out, function(a, b)
    if rank[a.kind] ~= rank[b.kind] then return rank[a.kind] < rank[b.kind] end
    return a.gain > b.gain
  end)
  while #out > skills.MAX_SUGGESTIONS do table.remove(out) end

  -- Attach a numbered building label to each suggestion (Builder 2, etc.).
  local map = numberBuildings(buildings)
  for _, s in ipairs(out) do s.jobLabel = labelFor(map, s.building.location, s.job) end
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

  -- Job buildings, sorted by job type then number (Builder 1, Builder 2, ...).
  local map = numberBuildings(buildings)
  local ordered = {}
  for _, b in ipairs(buildings) do
    local jk = b.type or jobKey(b.name)
    if jk and JOB_SKILLS[jk] and b.built ~= false then ordered[#ordered + 1] = b end
  end
  table.sort(ordered, function(a, b)
    local ia, ib = map[locStr(a.location)], map[locStr(b.location)]
    if ia.jk ~= ib.jk then return ia.jk < ib.jk end
    return ia.num < ib.num
  end)

  local flat = {}
  for _, b in ipairs(ordered) do
    local jk = b.type or jobKey(b.name)
    local sk = jk and JOB_SKILLS[jk]
    if sk and b.built ~= false then
      local pr, se = sk[1], sk[2]
      local k = locStr(b.location)
      local workers = (type(b.citizens) == "table") and b.citizens or {}
      local maxS = maxSlotsFor(jk, b.level)
      flat[#flat + 1] = { kind = "head", building = jk, label = labelFor(map, b.location, jk),
        filled = #workers, max = maxS }
      for _, w in ipairs(workers) do
        local rea = reassignAt[w.id]
        local rep = replaceAt[k]
        if rea then
          flat[#flat + 1] = { kind = "worker", name = w.name, status = "reassign",
            to = rea.jobLabel or rea.job, sug = rea }
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

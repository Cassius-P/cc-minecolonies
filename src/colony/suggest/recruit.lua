----------------------------------------------------------------------------
-- colony/suggest/recruit.lua -- RECRUIT pass: Tavern visitors as a SEPARATE
-- candidate pool. Only worth it when a visitor fills an open slot or beats a
-- weak worker AND beats the best free idle citizen who could otherwise take the
-- job -- else recruiting (which costs items) buys nothing. Uses leftover
-- open-slot capacity after the citizen passes.
----------------------------------------------------------------------------

local util   = require("common.util")
local skills = require("colony.skills")
local scoreFor, skillLevel = skills.scoreFor, skills.skillLevel
local JOB_SKILLS = skills.JOB_SKILLS
local jobKey = util.jobKey

local M = {}

function M.run(ix, acc, margins, visitors)
  if type(visitors) ~= "table" or #visitors == 0 then return end
  local REPL = (margins and margins.replace) or skills.REPLACE_MARGIN

  -- The integrator does not track visitor entity position (returns 0,0,0), so
  -- "locate" points at the Tavern where visitors gather / are recruited.
  local tavernLoc
  for _, b in ipairs(ix.buildings) do
    if (b.type or jobKey(b.name)) == "tavern" then tavernLoc = b.location; break end
  end

  -- Best remaining idle-citizen score per job type (idle not already used).
  local bestIdleFor = {}
  for jk in pairs(ix.recsByJob) do
    local sk, best = JOB_SKILLS[jk], -1
    for _, c in ipairs(ix.idle) do
      if not acc.used[c.id] then
        local s = scoreFor(c, sk[1], sk[2])
        if s > best then best = s end
      end
    end
    bestIdleFor[jk] = best
  end

  for _, v in ipairs(visitors) do
    -- Visitor's single best-fit job among the colony's job types.
    local bestJk, bestScore = nil, -1
    for jk in pairs(ix.recsByJob) do
      local sk = JOB_SKILLS[jk]
      local s = scoreFor(v, sk[1], sk[2])
      if s > bestScore then bestScore, bestJk = s, jk end
    end
    if bestJk and bestScore > 0 and bestScore > (bestIdleFor[bestJk] or -1) then
      local rj = ix.recsByJob[bestJk]
      local sk = JOB_SKILLS[bestJk]
      local rc = v.recruitCost
      local cost = (type(rc) == "table")
        and { count = rc.count or 1, displayName = rc.displayName or rc.name or "?" } or nil
      local vpri, vsec = skillLevel(v, sk[1]), skillLevel(v, sk[2])
      local target
      for _, rec in ipairs(rj.open) do if rec.free > 0 then target = rec; break end end
      if target then
        target.free = target.free - 1
        acc.out[#acc.out + 1] = { kind = "recruit", job = bestJk, building = { location = target.loc },
          pri = sk[1], sec = sk[2],
          candidate = { name = v.name, id = v.id, score = bestScore, location = v.location,
            pri = vpri, sec = vsec }, cost = cost, tavernLoc = tavernLoc,
          gain = bestScore - math.max(0, bestIdleFor[bestJk] or 0) }
      else
        -- No open slot: displace the weakest worker of the best full hut if the
        -- gap clears the replace margin.
        local bestRec, bWeak, bWs = nil, nil, math.huge
        for _, rec in ipairs(rj.full) do
          local w, ws = ix.weakestOf(rec)
          if w and ws < bWs then bestRec, bWeak, bWs = rec, w, ws end
        end
        if bestRec and (bestScore - bWs) >= REPL then
          local tgt = ix.byId[bWeak.id]
          acc.out[#acc.out + 1] = { kind = "recruit", job = bestJk, building = { location = bestRec.loc },
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

return M

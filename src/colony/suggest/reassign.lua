----------------------------------------------------------------------------
-- colony/suggest/reassign.lua -- REASSIGN pass: move an employed citizen toward
-- their SINGLE best-fit job (the colony job type where they score highest).
-- Only moving toward best fit guarantees each applied move raises their score,
-- so suggestions converge instead of oscillating (builder->guard->builder).
-- Prefers an open slot; else displaces the weakest worker of the best full hut
-- when the gap clears max(replace, reassign) margin.
----------------------------------------------------------------------------

local skills = require("colony.skills")
local scoreFor, skillLevel = skills.scoreFor, skills.skillLevel
local JOB_SKILLS = skills.JOB_SKILLS

local M = {}

function M.run(ix, acc, margins)
  local REPL  = (margins and margins.replace) or skills.REPLACE_MARGIN
  local REASS = (margins and margins.reassign) or skills.REASSIGN_MARGIN

  -- Best-fit job per employed citizen (that clears the reassign margin).
  local cands = {}
  for _, e in ipairs(ix.employed) do
    local bestJk, bestScore = nil, -1
    for jk in pairs(ix.recsByJob) do
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
    if not acc.used[m.e.c.id] then
      local rj = ix.recsByJob[m.jk]
      local target
      for _, rec in ipairs(rj.open) do if rec.free > 0 then target = rec; break end end
      if target then
        acc.used[m.e.c.id] = true
        target.free = target.free - 1
        local sk = JOB_SKILLS[m.jk]
        acc.out[#acc.out + 1] = { kind = "reassign", job = m.jk, from = m.e.jc,
          building = { location = target.loc }, pri = sk[1], sec = sk[2],
          candidate = { name = m.e.c.name, id = m.e.c.id, score = m.score, location = m.e.c.location,
            pri = skillLevel(m.e.c, sk[1]), sec = skillLevel(m.e.c, sk[2]) }, gain = m.gain }
      else
        -- No open slot: displace the weakest worker of the best full hut, if the
        -- gap clears the margin (and that worker isn't the same citizen).
        local bestRec, bWeak, bWs = nil, nil, math.huge
        for _, rec in ipairs(rj.full) do
          local w, ws = ix.weakestOf(rec)
          if w and w.id ~= m.e.c.id and ws < bWs then bestRec, bWeak, bWs = rec, w, ws end
        end
        if bestRec and (m.score - bWs) >= math.max(REPL, REASS) then
          acc.used[m.e.c.id] = true
          local tgt = ix.byId[bWeak.id]
          acc.out[#acc.out + 1] = { kind = "reassign", job = m.jk, from = m.e.jc,
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
end

return M

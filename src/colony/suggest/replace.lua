----------------------------------------------------------------------------
-- colony/suggest/replace.lua -- REPLACE pass: for each full hut, the weakest
-- worker vs. the best still-unused idle citizen; suggest the swap when the
-- skill gap clears the replace margin. Ordered by gain.
----------------------------------------------------------------------------

local skills = require("colony.skills")
local scoreFor, skillLevel = skills.scoreFor, skills.skillLevel

local M = {}

function M.run(ix, acc, margins)
  local REPL = (margins and margins.replace) or skills.REPLACE_MARGIN

  local repl = {}
  for _, fb in ipairs(ix.fullB) do
    local weak, ws = ix.weakestOf(fb)
    local cand, cs = nil, -1
    for _, c in ipairs(ix.idle) do
      if not acc.used[c.id] then
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
    if not acc.used[r.cand.id] then
      acc.used[r.cand.id] = true
      local tgt = ix.byId[r.weak.id]
      acc.out[#acc.out + 1] = { kind = "replace", job = r.fb.jk, building = { location = r.fb.loc },
        pri = r.fb.pr, sec = r.fb.se,
        candidate = { name = r.cand.name, id = r.cand.id, score = r.cs, location = r.cand.location,
          pri = skillLevel(r.cand, r.fb.pr), sec = skillLevel(r.cand, r.fb.se) },
        target = { name = r.weak.name, id = r.weak.id, score = r.ws,
          pri = tgt and skillLevel(tgt, r.fb.pr) or 0, sec = tgt and skillLevel(tgt, r.fb.se) or 0 },
        gain = r.gain }
    end
  end
end

return M

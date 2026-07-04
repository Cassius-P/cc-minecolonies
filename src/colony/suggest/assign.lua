----------------------------------------------------------------------------
-- colony/suggest/assign.lua -- ASSIGN pass: rank every (idle citizen, open
-- slot) pair by score and greedily take the best; each citizen used at most
-- once. Mutates acc.out / acc.used and decrements slot.free (visible to the
-- reassign/recruit passes that share the same rec tables via the index).
----------------------------------------------------------------------------

local skills = require("colony.skills")
local scoreFor, skillLevel = skills.scoreFor, skills.skillLevel

local M = {}

function M.run(ix, acc)
  local prs = {}
  for _, slot in ipairs(ix.openSlots) do
    for _, c in ipairs(ix.idle) do
      prs[#prs + 1] = { c = c, slot = slot, score = scoreFor(c, slot.pr, slot.se) }
    end
  end
  table.sort(prs, function(a, b) return a.score > b.score end)
  for _, p in ipairs(prs) do
    if not acc.used[p.c.id] and p.slot.free > 0 then
      acc.used[p.c.id] = true
      p.slot.free = p.slot.free - 1
      acc.out[#acc.out + 1] = { kind = "assign", job = p.slot.jk, building = { location = p.slot.loc },
        pri = p.slot.pr, sec = p.slot.se,
        candidate = { name = p.c.name, id = p.c.id, score = p.score, location = p.c.location,
          pri = skillLevel(p.c, p.slot.pr), sec = skillLevel(p.c, p.slot.se) }, gain = p.score }
    end
  end
end

return M

----------------------------------------------------------------------------
-- colony/advisor.lua -- citizen->job matching (thin composer).
--
-- computeSuggestions runs four passes over a shared prepared index
-- (colony/roster_index), each emitting one kind (each citizen appears at most
-- once via the shared acc.used set):
--   * assign   - an idle citizen fills an open slot.
--   * replace  - an idle citizen replaces an under-skilled worker in a full hut.
--   * reassign - an EMPLOYED citizen would be a much better fit at another job.
--   * recruit  - a Tavern visitor beats every candidate for a job.
-- computeRoster flattens every building + workers into display rows.
--
-- Both functions accept an optional pre-prepared index (colony/roster_index) so
-- a caller running them back-to-back (colony/shape does, every scan) prepares it
-- ONCE and shares it. Sharing is safe: the suggestion passes mutate only slot
-- `free` counts, which computeRoster never reads (it uses byId / numbered /
-- labelFor). Do NOT reuse one index across two computeSuggestions calls.
--
-- margins = { replace = n, reassign = n } gate replace/reassign/recruit (skill-
-- gap thresholds); they fall back to the skills defaults when omitted.
----------------------------------------------------------------------------

local util     = require("common.util")
local skills   = require("colony.skills")
local index    = require("colony.roster_index")
local assign   = require("colony.suggest.assign")
local replace  = require("colony.suggest.replace")
local reassign = require("colony.suggest.reassign")
local recruit  = require("colony.suggest.recruit")

local jobKey, locStr = util.jobKey, util.locStr
local JOB_SKILLS, maxSlotsFor = skills.JOB_SKILLS, skills.maxSlotsFor
local scoreFor = skills.scoreFor

local M = {}

function M.computeSuggestions(citizens, buildings, visitors, margins, ix)
  ix = ix or index.prepare(citizens, buildings)
  local acc = { used = {}, out = {} }

  assign.run(ix, acc, margins)
  replace.run(ix, acc, margins)
  reassign.run(ix, acc, margins)
  recruit.run(ix, acc, margins, visitors)

  -- Order: assign, replace, reassign, then recruit (recruit costs items, so it
  -- ranks last); each group by descending gain.
  local rank = { assign = 1, replace = 2, reassign = 3, recruit = 4 }
  table.sort(acc.out, function(a, b)
    if rank[a.kind] ~= rank[b.kind] then return rank[a.kind] < rank[b.kind] end
    return a.gain > b.gain
  end)
  while #acc.out > skills.MAX_SUGGESTIONS do table.remove(acc.out) end

  -- Attach a numbered building label to each suggestion (Builder 2, etc.).
  for _, s in ipairs(acc.out) do s.jobLabel = ix.labelFor(s.building.location, s.job) end
  return acc.out
end

function M.computeRoster(citizens, buildings, sugs, ix)
  ix = ix or index.prepare(citizens, buildings)
  local byId, map = ix.byId, ix.numbered

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
      flat[#flat + 1] = { kind = "head", building = jk, label = ix.labelFor(b.location, jk),
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

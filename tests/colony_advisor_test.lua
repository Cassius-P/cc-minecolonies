-- Characterization tests for colony/advisor.lua (suggestion engine + roster).
-- These pin CURRENT behavior; a pure-logic refactor must keep them green.
local t       = require("helper")
local advisor = require("colony.advisor")

local function sk(map) return { skills = map } end

--------------------------------------------------------------------------
-- ASSIGN: idle citizen -> open matching slot
--------------------------------------------------------------------------
t.case("assign: idle citizen fills open builder slot")
do
  local citizens = {
    { id = 1, name = "Al", skills = { Adaptability = { level = 20 }, Athletics = { level = 10 } } },
  }
  local buildings = {
    { type = "builder", level = 1, location = { x = 0, y = 0, z = 0 }, citizens = {} },
  }
  local out = advisor.computeSuggestions(citizens, buildings, {}, { replace = 3, reassign = 4 })
  t.eq(#out, 1, "one suggestion")
  t.eq(out[1].kind, "assign")
  t.eq(out[1].job, "builder")
  t.eq(out[1].candidate.id, 1)
end

--------------------------------------------------------------------------
-- USED-ONCE invariant: a citizen best at two slots is assigned only once
--------------------------------------------------------------------------
t.case("each citizen appears in at most one suggestion")
do
  local citizens = {
    { id = 1, name = "Al", skills = { Adaptability = { level = 20 }, Athletics = { level = 20 }, Stamina = { level = 20 } } },
    { id = 2, name = "Bo", skills = { Stamina = { level = 15 }, Athletics = { level = 5 } } },
  }
  local buildings = {
    { type = "builder", level = 1, location = { x = 0, y = 0, z = 0 }, citizens = {} },
    { type = "farmer",  level = 1, location = { x = 1, y = 0, z = 0 }, citizens = {} },
  }
  local out = advisor.computeSuggestions(citizens, buildings, {}, { replace = 3, reassign = 4 })
  t.eq(#out, 2, "two assigns")
  t.eq(t.count(out, function(s) return s.candidate.id == 1 end), 1, "Al used once")
  t.eq(t.count(out, function(s) return s.candidate.id == 2 end), 1, "Bo used once")
  local seen = {}
  for _, s in ipairs(out) do
    t.falsy(seen[s.candidate.id], "no duplicate candidate id")
    seen[s.candidate.id] = true
  end
end

--------------------------------------------------------------------------
-- REPLACE margin gating: small gap suppressed, small margin admits it
--------------------------------------------------------------------------
t.case("replace fires only when skill gap >= margin")
do
  -- Full builder hut (max 1) with a slightly-weak worker; idle candidate barely better.
  local citizens = {
    { id = 1, name = "Al", skills = { Adaptability = { level = 20 }, Athletics = { level = 10 } } }, -- idle, score 25
    { id = 2, name = "Wk", work = { type = "builder" },
      skills = { Adaptability = { level = 19 }, Athletics = { level = 9 } } },                       -- employed, score 23.5
  }
  local buildings = {
    { type = "builder", level = 1, location = { x = 0, y = 0, z = 0 },
      citizens = { { id = 2, name = "Wk" } } },   -- full: 1/1
  }
  local hi = advisor.computeSuggestions(citizens, buildings, {}, { replace = 3, reassign = 4 })
  t.eq(#hi, 0, "gap 1.5 < margin 3 -> no suggestion")

  local lo = advisor.computeSuggestions(citizens, buildings, {}, { replace = 1, reassign = 4 })
  t.eq(#lo, 1, "gap 1.5 >= margin 1 -> replace")
  t.eq(lo[1].kind, "replace")
  t.eq(lo[1].candidate.id, 1)
  t.eq(lo[1].target.id, 2, "displaces the weak worker")
end

--------------------------------------------------------------------------
-- Ordering invariant: assign < replace < reassign < recruit, then gain desc
--------------------------------------------------------------------------
t.case("suggestions are rank-ordered")
do
  local citizens = {
    { id = 1, name = "Al", skills = { Adaptability = { level = 20 }, Athletics = { level = 20 }, Stamina = { level = 20 } } },
    { id = 2, name = "Bo", skills = { Stamina = { level = 15 }, Athletics = { level = 5 } } },
  }
  local buildings = {
    { type = "builder", level = 1, location = { x = 0, y = 0, z = 0 }, citizens = {} },
    { type = "farmer",  level = 1, location = { x = 1, y = 0, z = 0 }, citizens = {} },
  }
  local out = advisor.computeSuggestions(citizens, buildings, {}, { replace = 3, reassign = 4 })
  local rank = { assign = 1, replace = 2, reassign = 3, recruit = 4 }
  local prev = 0
  for _, s in ipairs(out) do
    t.truthy(rank[s.kind] >= prev, "rank non-decreasing")
    prev = rank[s.kind]
  end
end

--------------------------------------------------------------------------
-- computeRoster row shapes
--------------------------------------------------------------------------
t.case("computeRoster emits head + worker + slot rows")
do
  local citizens = {
    { id = 2, name = "Wk", work = { type = "builder" },
      skills = { Adaptability = { level = 5 }, Athletics = { level = 5 } } },
  }
  -- Builder hut level 1 (max 1) fully staffed -> head + worker.
  local full = advisor.computeRoster(citizens,
    { { type = "builder", level = 1, location = { x = 0, y = 0, z = 0 },
        citizens = { { id = 2, name = "Wk" } } } }, {})
  t.eq(full[1].kind, "head")
  t.eq(full[1].filled, 1)
  t.eq(full[1].max, 1)
  t.eq(full[2].kind, "worker")
  t.eq(full[2].name, "Wk")

  -- Empty builder hut -> head + empty slot.
  local empty = advisor.computeRoster({},
    { { type = "builder", level = 1, location = { x = 0, y = 0, z = 0 }, citizens = {} } }, {})
  t.eq(empty[1].kind, "head")
  t.eq(empty[2].kind, "slot")
  t.eq(empty[2].status, "empty")
end

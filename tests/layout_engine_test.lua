-- Tests for ui/layout/engine.lua (pure two-column geometry).
local t      = require("helper")
local engine = require("ui.layout.engine")

t.case("isShown: default-shown vs default-hidden")
do
  local s = { enabled = {} }
  t.truthy(engine.isShown(s, "status"), "normal section shown by default")
  t.falsy(engine.isShown(s, "jobskills"), "default-hidden off unless enabled")
  s.enabled.jobskills = true
  t.truthy(engine.isShown(s, "jobskills"), "enabled -> shown")
  s.enabled.status = false
  t.falsy(engine.isShown(s, "status"), "explicitly disabled -> hidden")
end

t.case("weightOf: default + overrides")
do
  t.eq(engine.weightOf({ weights = {} }, "x"), 6, "default weight")
  t.eq(engine.weightOf({ weights = { x = 10 } }, "x"), 10)
  t.eq(engine.weightOf({ weights = { x = 0 } }, "x"), 6, "non-positive -> default")
end

t.case("normalizeColumns dedups, drops invalid, appends missing")
do
  local s = { columns = { { "status", "status", "bogus" }, { "workers" } } }
  engine.normalizeColumns(s)
  t.eq(s.columns[1][1], "status")
  t.eq(s.columns[2][1], "workers")
  -- every valid section present exactly once across both columns
  local seen, total = {}, 0
  for ci = 1, 2 do for _, id in ipairs(s.columns[ci]) do
    t.falsy(seen[id], "no dup " .. id); seen[id] = true; total = total + 1
  end end
  t.eq(total, #engine.SECTION_ORDER, "all sections placed")
  t.falsy(seen["bogus"], "invalid id dropped")
end

t.case("computeRects: two columns split width, weights split height")
do
  local s = { W = 50, H = 20, enabled = {}, weights = {},
    columns = { { "status", "workforce" }, { "workers" } } }
  local r = engine.computeRects(s)
  t.eq(r.status.x, 1);  t.eq(r.status.y, 1);  t.eq(r.status.w, 24); t.eq(r.status.h, 9)
  t.eq(r.workforce.x, 1); t.eq(r.workforce.y, 10); t.eq(r.workforce.w, 24); t.eq(r.workforce.h, 10)
  t.eq(r.workers.x, 26); t.eq(r.workers.y, 1); t.eq(r.workers.w, 25); t.eq(r.workers.h, 19)
end

t.case("computeRects: empty column collapses, other takes full width")
do
  local s = { W = 50, H = 20, enabled = {}, weights = {}, columns = { { "status" }, {} } }
  local r = engine.computeRects(s)
  t.eq(r.status.x, 1); t.eq(r.status.w, 50); t.eq(r.status.h, 19)
end

t.case("computeRects: nothing visible -> empty")
do
  local r = engine.computeRects({ W = 50, H = 20, enabled = {}, weights = {}, columns = { {}, {} } })
  t.eq(next(r), nil, "no rects")
end

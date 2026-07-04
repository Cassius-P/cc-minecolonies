----------------------------------------------------------------------------
-- tests/helper.lua -- tiny dependency-free assert/expect helper.
--
-- Required (not dofile'd) by every *_test.lua, so the SAME singleton `t` and
-- its pass/fail counters are shared across all test files. Path setup + CC
-- global stubs live in run.lua, which requires this once up front.
----------------------------------------------------------------------------

local t = { passed = 0, failed = 0, name = "?", curfile = "?" }

local function dump(v)
  if type(v) == "table" then return "<table>" end
  return tostring(v)
end

local function fail(msg)
  t.failed = t.failed + 1
  print(string.format("  FAIL [%s > %s] %s", t.curfile, t.name, msg or ""))
end

local function ok() t.passed = t.passed + 1 end

function t.file(n) t.curfile = n end
function t.case(n) t.name = n end

function t.eq(a, b, m)  if a == b then ok() else fail((m or "") .. " expected " .. dump(b) .. " got " .. dump(a)) end end
function t.ne(a, b, m)  if a ~= b then ok() else fail((m or "") .. " both " .. dump(a)) end end
function t.truthy(a, m) if a then ok() else fail((m or "") .. " expected truthy, got " .. dump(a)) end end
function t.falsy(a, m)  if not a then ok() else fail((m or "") .. " expected falsy, got " .. dump(a)) end end
function t.near(a, b, eps, m)
  if type(a) == "number" and type(b) == "number" and math.abs(a - b) <= (eps or 1e-9) then ok()
  else fail((m or "") .. " " .. dump(a) .. " ~= " .. dump(b)) end
end

-- count list entries matching pred(v) -> bool.
function t.count(list, pred)
  local n = 0
  for _, v in ipairs(list) do if pred(v) then n = n + 1 end end
  return n
end

function t.report()
  print(string.format("\n%d passed, %d failed", t.passed, t.failed))
end

return t

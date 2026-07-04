----------------------------------------------------------------------------
-- tests/run.lua -- discover + run every tests/*_test.lua under plain Lua.
--
-- Run with:  luajit tests/run.lua   (Lua 5.1 fidelity; matches CC:Tweaked)
--            lua tests/run.lua       (5.5 here; also works for pure modules)
--
-- Maps src/ as the require root so `require("colony.advisor")` resolves exactly
-- as it does in-game (where modules install at the fs root: /colony/advisor.lua).
-- These tests are LOCAL-ONLY: never listed in manifest.lua, never shipped.
----------------------------------------------------------------------------

local here = (arg and arg[0] or "tests/run.lua"):match("^(.*)[/\\]") or "."

package.path = here .. "/?.lua;"
            .. here .. "/../src/?.lua;"
            .. here .. "/../src/?/init.lua;"
            .. package.path

require("stubs")
local t = require("helper")

-- Discover *_test.lua next to this file (sorted for stable order).
local files = {}
local p = io.popen('ls "' .. here .. '"/*_test.lua 2>/dev/null')
if p then
  for line in p:lines() do files[#files + 1] = line end
  p:close()
end
table.sort(files)

if #files == 0 then
  print("No *_test.lua found in " .. here)
  os.exit(1)
end

for _, f in ipairs(files) do
  t.file((f:match("([^/\\]+)%.lua$")) or f)
  dofile(f)
end

t.report()
os.exit(t.failed == 0 and 0 or 1)

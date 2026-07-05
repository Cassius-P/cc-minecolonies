----------------------------------------------------------------------------
-- common/util.lua -- generic helpers with no colony/UI dependencies.
----------------------------------------------------------------------------

local M = {}

-- Normalise a building name/id to a bare job key ("minecolonies:builder2" -> "builder").
function M.jobKey(s)
  if type(s) ~= "string" then return nil end
  s = s:lower()
  local seg = s:match("([%w_]+)$") or s
  return (seg:gsub("[^%a]", ""))
end

function M.locStr(loc)
  if type(loc) == "table" then
    return string.format("%s, %s, %s", tostring(loc.x), tostring(loc.y), tostring(loc.z))
  end
  return "unknown"
end

function M.capitalize(s)
  if type(s) ~= "string" or s == "" then return s end
  return s:sub(1, 1):upper() .. s:sub(2)
end

function M.trimLead(str) return str and str:match("^%s*(.*)$") or "" end
function M.lastWord(str) return string.match(str or "", "%S+$") end

function M.deepCopy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = M.deepCopy(v) end
  return c
end

-- Run fn under pcall; return its value, or `d` when it throws or yields nil.
-- The standard guard for peripheral calls that can error across mod versions.
function M.safeGet(fn, d)
  local ok, v = pcall(fn)
  if ok and v ~= nil then return v else return d end
end

return M

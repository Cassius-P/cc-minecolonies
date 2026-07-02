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

function M.trimLead(str) return str and str:match("^%s*(.*)$") or "" end
function M.lastWord(str) return string.match(str or "", "%S+$") end

function M.deepCopy(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = M.deepCopy(v) end
  return c
end

return M

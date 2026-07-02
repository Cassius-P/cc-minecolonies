----------------------------------------------------------------------------
-- common/log.lua -- minimal file logging + pcall wrapper.
--
-- init(config) wires the module to CONFIG.logToFile; write() is a no-op until
-- logging is enabled. safeCall() runs a function under pcall and logs failures.
----------------------------------------------------------------------------

local M = {}

local enabled = false
local FILE = "colony_dashboard_log.txt"

function M.init(config)
  enabled = config and config.logToFile == true
end

function M.write(msg, level)
  if not enabled then return end
  pcall(function()
    local f = fs.open(FILE, "a")
    if f then
      f.writeLine(string.format("[%s] %s", level or "INFO", tostring(msg)))
      f.close()
    end
  end)
end

-- Run fn(...) under pcall; log any error. Returns the pcall ok flag.
function M.safeCall(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then M.write(err or "error", "ERROR") end
  return ok
end

return M

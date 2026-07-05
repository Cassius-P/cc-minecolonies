----------------------------------------------------------------------------
-- common/ports/paste.lua -- adapter over the paste.rs HTTP endpoint.
--
-- The only place the data dump touches `http`. post(body) uploads and returns
-- the resulting link (trailing whitespace stripped); errors if the POST fails.
----------------------------------------------------------------------------

local M = {}

function M.post(body)
  local res = http.post("https://paste.rs", body)
  if not res then error("paste.rs post failed (http)", 0) end
  local link = res.readAll(); res.close()
  return (link:gsub("%s+$", ""))
end

return M

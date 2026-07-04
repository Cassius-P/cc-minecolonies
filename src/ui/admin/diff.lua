----------------------------------------------------------------------------
-- ui/admin/diff.lua -- change-only widget writer for the admin view.
--
-- diff.new() returns a setter `set(el, text, fg)` that only calls
-- setText/setForeground when the value actually changed. This stops the admin
-- view from re-rendering every tick (which made inputs lag).
----------------------------------------------------------------------------

local M = {}

function M.new()
  local last = setmetatable({}, { __mode = "k" })
  return function(el, text, fg)
    local c = last[el]
    if not c then c = {}; last[el] = c end
    if text ~= nil and c.t ~= text then el:setText(text); c.t = text end
    if fg ~= nil and c.f ~= fg then el:setForeground(fg); c.f = fg end
  end
end

return M

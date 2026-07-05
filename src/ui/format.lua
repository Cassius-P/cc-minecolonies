----------------------------------------------------------------------------
-- ui/format.lua -- shared text helpers for the monitor sections.
--
-- Dedups the `trunc` that was copy-pasted (in two slightly different variants)
-- across workers/orders/requests/jobskills. Uses the guarded form so a negative
-- width yields "" rather than string.sub's from-the-end wrap.
----------------------------------------------------------------------------

local M = {}

-- Truncate s to at most n characters (n <= 0 -> empty string).
function M.trunc(s, n) return #s > n and s:sub(1, math.max(0, n)) or s end

return M

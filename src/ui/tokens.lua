----------------------------------------------------------------------------
-- ui/tokens.lua -- map fulfill STATUS TOKENS to display colours.
--
-- The domain (colony/requests categorize + storage/fulfill) is colour-free: it
-- tags each request's `displayColor` with a semantic token string. Presentation
-- resolves the token to a concrete colour here, so both the request rows and the
-- legend stay in sync from one table.
--
--   default  = not yet processed / no bridge   (white)
--   filled   = fully exported                   (green)
--   partial  = stuck / partially provided       (yellow)
--   crafting = queued for crafting              (blue)
--   missing  = not in system / uncraftable      (red)
--   skipped  = on the skip list                 (gray)
----------------------------------------------------------------------------

local M = {}

M.COLOR = {
  default  = colors.white,
  filled   = colors.green,
  partial  = colors.yellow,
  crafting = colors.blue,
  missing  = colors.red,
  skipped  = colors.gray,
}

function M.color(token) return M.COLOR[token] or M.COLOR.default end

return M

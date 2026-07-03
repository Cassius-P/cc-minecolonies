----------------------------------------------------------------------------
-- ui/sections/legend.lua -- request colour-code key.
----------------------------------------------------------------------------

local draw  = require("ui.draw")
local theme = require("ui.theme")
local C = theme.C

local M = {}
M.title = "Legend"

function M.draw(x, y, w, h, screen, d)
  local cx, cy = draw.card(x, y, w, h, "LEGEND")
  local entries = {
    { colors.red, "missing / uncraftable" }, { colors.yellow, "stuck / partial" },
    { colors.blue, "crafting" }, { colors.green, "fully exported" },
    { colors.gray, "skipped" },
  }
  for i, e in ipairs(entries) do
    if cy + i - 1 > y + h - 2 then break end
    draw.put(cx, cy + i - 1, "\7 ", e[1], C.card)
    draw.put(cx + 2, cy + i - 1, e[2], C.dim, C.card)
  end
end

return M

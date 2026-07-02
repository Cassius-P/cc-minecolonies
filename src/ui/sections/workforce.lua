----------------------------------------------------------------------------
-- ui/sections/workforce.lua -- headline citizen counts.
----------------------------------------------------------------------------

local draw  = require("ui.draw")
local theme = require("ui.theme")
local C = theme.C

local M = {}
M.title = "Workforce"

function M.draw(x, y, w, h, screen, d)
  local cx, cy, cw = draw.card(x, y, w, h, "WORKFORCE")
  local function stat(r, label, val, col)
    draw.put(cx, cy + r, label, C.dim, C.card)
    local s = tostring(val)
    draw.put(cx + cw - #s, cy + r, s, col or C.text, C.card)
  end
  stat(0, "Citizens", d.total, C.text)
  stat(1, "Employed", d.employed, C.good)
  stat(2, "Idle", d.idle, d.idle > 0 and C.warn or C.dim)
  stat(3, "Visitors", d.visitors, C.accent2)
  stat(4, "Buildings", d.buildings, C.text)
end

return M

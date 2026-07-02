----------------------------------------------------------------------------
-- ui/sections/workforce.lua -- citizen counts with an employment bar.
----------------------------------------------------------------------------

local draw  = require("ui.draw")
local theme = require("ui.theme")
local C = theme.C

local M = {}
M.title = "Workforce"

function M.draw(x, y, w, h, screen, d)
  local cx, cy, cw, ch = draw.card(x, y, w, h, "WORKFORCE")
  local r = cy

  -- Employment bar (employed / total citizens)
  draw.put(cx, r, "Staffed", C.dim, C.card); r = r + 1
  local frac = d.total > 0 and d.employed / d.total or 0
  draw.hbar(cx, r, cw, frac, C.good, string.format(" %d / %d employed", d.employed, d.total)); r = r + 2

  -- Colour-coded stat rows
  local function stat(label, val, col)
    if r > cy + ch - 1 then return end
    draw.put(cx, r, label, C.dim, C.card)
    local s = tostring(val)
    draw.put(cx + cw - #s, r, s, col or C.text, C.card)
    r = r + 1
  end
  stat("Idle", d.idle, d.idle > 0 and C.warn or C.good)
  stat("Visitors", d.visitors, C.accent2)
  stat("Buildings", d.buildings, C.text)
end

return M

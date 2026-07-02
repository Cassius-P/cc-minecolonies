----------------------------------------------------------------------------
-- ui/sections/requests.lua -- open requests + CCxM auto-fulfill status.
--
-- Row = "<provided>/<count> <item>" coloured by fulfill status (see legend);
-- title shows the auto-fulfill mode (AUTO / MANUAL / PAUSED.. / no bridge).
----------------------------------------------------------------------------

local draw  = require("ui.draw")
local theme = require("ui.theme")
local C = theme.C

local M = {}
M.title = "Open Requests"

function M.draw(x, y, w, h, screen, d)
  local list = d.requests
  local modeCol = (d.reqMode == "AUTO") and C.good
      or (d.reqMode:find("PAUSED") and C.warn) or C.dim
  local cx, cy, cw, ch = draw.card(x, y, w, h, string.format("OPEN REQUESTS (%d) %s", #list, d.reqMode))
  draw.put(x + 1 + #string.format("OPEN REQUESTS (%d) ", #list), y, d.reqMode, modeCol, C.cardTitle)
  screen.scroll = draw.scrollArrows("requests", x, y, w, #list, ch, screen.scroll)
  if #list == 0 then draw.put(cx, cy, "No open requests.", C.good, C.card); return end
  local off = screen.scroll.requests or 0
  for i = 1, ch do
    local it = list[i + off]
    if not it then break end
    local ry = cy + i - 1
    local qty = (it.provided or 0) .. "/" .. it.count
    local tgt = tostring(it.target or "")
    local left = qty .. " " .. (it.item_displayName or it.name)
    local room = cw - #tgt - 1
    draw.put(cx, ry, left:sub(1, math.max(0, room)), it.displayColor or C.text, C.card)
    if #tgt > 0 then draw.put(cx + cw - #tgt, ry, tgt, C.dim, C.card) end
  end
end

return M

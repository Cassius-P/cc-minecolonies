----------------------------------------------------------------------------
-- ui/sections/requests.lua -- open requests + CCxM auto-fulfill status.
--
-- Main row = "<provided>/<count> <item>" coloured by fulfill status (see
-- legend). Domum Ornamentum items get a second, indented line listing their
-- materials in a fixed colour. Title shows the auto-fulfill mode.
----------------------------------------------------------------------------

local draw  = require("ui.draw")
local theme = require("ui.theme")
local C = theme.C

local MAT_COLOR = colors.purple   -- fixed colour for Domum material lines (not used by the legend)

local M = {}
M.title = "Open Requests"

local function trunc(s, n) return #s > n and s:sub(1, math.max(0, n)) or s end

function M.draw(x, y, w, h, screen, d)
  local list = d.requests
  local modeCol = (d.reqMode == "AUTO") and C.good
      or (d.reqMode:find("PAUSED") and C.warn) or C.dim
  local cx, cy, cw, ch = draw.card(x, y, w, h, string.format("OPEN REQUESTS (%d) %s", #list, d.reqMode))
  draw.put(x + 1 + #string.format("OPEN REQUESTS (%d) ", #list), y, d.reqMode, modeCol, C.cardTitle)

  -- Flatten to display lines: one per request, plus a materials line for Domum.
  local lines = {}
  for _, it in ipairs(list) do
    lines[#lines + 1] = { kind = "main", it = it }
    if it.materials then lines[#lines + 1] = { kind = "mat", text = it.materials } end
  end

  screen.scroll = draw.scrollArrows("requests", x, y, w, #lines, ch, screen.scroll)
  if #list == 0 then draw.put(cx, cy, "No open requests.", C.good, C.card); return end

  local off = screen.scroll.requests or 0
  for i = 1, ch do
    local ln = lines[i + off]
    if not ln then break end
    local ry = cy + i - 1
    if ln.kind == "mat" then
      draw.put(cx + 2, ry, trunc("\26 " .. ln.text, cw - 2), MAT_COLOR, C.card)
    else
      local it = ln.it
      local qty = (it.provided or 0) .. "/" .. it.count
      local tgt = tostring(it.target or "")
      local left = qty .. " " .. (it.displayLabel or it.item_displayName or it.name)
      local room = cw - #tgt - 1
      draw.put(cx, ry, trunc(left, math.max(0, room)), it.displayColor or C.text, C.card)
      if #tgt > 0 then draw.put(cx + cw - #tgt, ry, tgt, C.dim, C.card) end
    end
  end
end

return M

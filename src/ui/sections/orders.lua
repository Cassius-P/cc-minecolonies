----------------------------------------------------------------------------
-- ui/sections/orders.lua -- queued work orders.
----------------------------------------------------------------------------

local draw  = require("ui.draw")
local theme = require("ui.theme")
local util  = require("common.util")
local C = theme.C

local M = {}
M.title = "Work Orders"

function M.draw(x, y, w, h, screen, d)
  local list = d.orders
  local cx, cy, cw, ch = draw.card(x, y, w, h, string.format("WORK ORDERS (%d)", #list))
  screen.scroll = draw.scrollArrows("orders", x, y, w, #list, ch, screen.scroll)
  if #list == 0 then draw.put(cx, cy, "None queued.", C.dim, C.card); return end
  local off = screen.scroll.orders or 0
  for i = 1, ch do
    local o = list[i + off]
    if not o then break end
    local kind = tostring(o.workOrderType or o.type or "?"):sub(1, 7)
    local tgt = util.jobKey(o.buildingName or o.structureName or o.name or "?") or "?"
    local lvl = o.targetLevel and ("L" .. o.targetLevel) or ""
    local claimed = o.isClaimed and "\7" or " "
    draw.put(cx, cy + i - 1, string.format("%s%-7s %s %s", claimed, kind, tgt, lvl),
      o.isClaimed and C.text or C.dim, C.card)
  end
end

return M

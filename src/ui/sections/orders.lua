----------------------------------------------------------------------------
-- ui/sections/orders.lua -- queued work orders.
--
-- Each row: a claim dot (green = claimed by a builder, orange = waiting), a
-- colour-coded action verb (Build / Upgrade / Repair / Remove), the target
-- building name, and the target level on the right.
----------------------------------------------------------------------------

local draw  = require("ui.draw")
local theme = require("ui.theme")
local util  = require("common.util")
local C = theme.C
local cap = util.capitalize

local M = {}
M.title = "Work Orders"

local function verb(t)
  t = tostring(t or ""):lower()
  if t:find("upgrade") then return "Upgrade", C.accent
  elseif t:find("repair") then return "Repair", C.warn
  elseif t:find("remov") or t:find("deconstruct") then return "Remove", C.bad
  elseif t:find("build") or t:find("create") then return "Build", C.good
  else return cap(t == "" and "Order" or t), C.accent2 end
end

local function trunc(s, n) return #s > n and s:sub(1, math.max(0, n)) or s end

function M.draw(x, y, w, h, screen, d)
  local list = d.orders or {}
  local claimed = 0
  for _, o in ipairs(list) do if o.isClaimed then claimed = claimed + 1 end end

  local cx, cy, cw, ch = draw.card(x, y, w, h, string.format("WORK ORDERS (%d)", #list))
  -- claimed/total badge on the title bar, right side
  if #list > 0 then
    local badge = ("%d/%d claimed"):format(claimed, #list)
    draw.put(x + w - #badge - 8, y, badge, claimed == #list and C.good or C.dim, C.cardTitle)
  end
  screen.scroll = draw.scrollArrows("orders", x, y, w, #list, ch, screen.scroll)
  if #list == 0 then draw.put(cx, cy, "None queued.", C.dim, C.card); return end

  local off = screen.scroll.orders or 0
  for i = 1, ch do
    local o = list[i + off]
    if not o then break end
    local ry = cy + i - 1
    local v, vc = verb(o.workOrderType or o.type)
    local name = cap(util.jobKey(o.buildingName or o.structureName or o.name or "?") or "?")
    local lvl = o.targetLevel and ("L" .. tostring(o.targetLevel)) or ""

    -- claim dot
    draw.put(cx, ry, "\7", o.isClaimed and C.good or C.warn, C.card)
    -- verb (coloured by action)
    draw.put(cx + 2, ry, v, vc, C.card)
    -- target name, clipped to leave room for the level
    local nameX = cx + 2 + #v + 1
    local room = (cx + cw - #lvl - 1) - nameX
    draw.put(nameX, ry, trunc(name, room), C.text, C.card)
    -- level on the right
    if lvl ~= "" then draw.put(cx + cw - #lvl, ry, lvl, C.dim, C.card) end
  end
end

return M

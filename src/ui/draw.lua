----------------------------------------------------------------------------
-- ui/draw.lua -- SCADA-card drawing primitives + click hitboxes.
--
-- Primitives write to the "current target": a CC window (from a Basalt Display
-- element) plus its size and a button-hitbox list. setTarget() switches target
-- before rendering a screen; sections then call put/card/hbar/button/etc.
-- Colors come live from ui/theme's semantic map C.
----------------------------------------------------------------------------

local theme = require("ui.theme")
local C = theme.C

local M = {}

local cur = { win = nil, W = 0, H = 0, buttons = {} }

function M.setTarget(win, w, h, buttons)
  cur.win, cur.W, cur.H, cur.buttons = win, w, h, buttons
end

function M.clearButtons() cur.buttons = {} ; return cur.buttons end
function M.setButtons(b) cur.buttons = b end

function M.addButton(x1, y1, x2, y2, action)
  cur.buttons[#cur.buttons + 1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, action = action }
end

function M.hit(x, y)
  for i = #cur.buttons, 1, -1 do
    local b = cur.buttons[i]
    if x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 then return b.action end
  end
end

function M.put(x, y, text, fg, bg)
  local win, W, H = cur.win, cur.W, cur.H
  if y < 1 or y > H then return end
  text = tostring(text)
  if x < 1 then text = text:sub(2 - x); x = 1 end
  local room = W - x + 1
  if room <= 0 then return end
  if #text > room then text = text:sub(1, room) end
  win.setCursorPos(x, y)
  win.setTextColor(fg or C.text)
  win.setBackgroundColor(bg or C.screen)
  win.write(text)
end

function M.fillRect(x, y, w, h, bg)
  local win, H = cur.win, cur.H
  if w <= 0 or h <= 0 then return end
  win.setBackgroundColor(bg)
  local line = string.rep(" ", w)
  for yy = y, y + h - 1 do
    if yy >= 1 and yy <= H then win.setCursorPos(x, yy); win.write(line) end
  end
end

-- SCADA card: gray title strip, dark/light body. Returns inner x,y,w,h.
function M.card(x, y, w, h, title)
  M.fillRect(x, y, w, h, C.card)
  M.fillRect(x, y, w, 1, C.cardTitle)
  M.put(x + 1, y, title, C.titleText, C.cardTitle)
  return x + 1, y + 1, w - 2, h - 2
end

function M.hbar(x, y, w, frac, fillColor, label)
  frac = math.max(0, math.min(1, frac or 0))
  local filled = math.floor(w * frac + 0.5)
  M.fillRect(x, y, w, 1, C.screen)
  if filled > 0 then M.fillRect(x, y, filled, 1, fillColor) end
  if label then
    for i = 1, #label do
      local lx = x + i - 1
      if lx > x + w - 1 then break end
      local on = (i <= filled)
      M.put(lx, y, label:sub(i, i), on and colors.black or C.dim, on and fillColor or C.screen)
    end
  end
end

function M.button(x, y, label, bg, fg, action)
  local lbl = " " .. label .. " "
  M.put(x, y, lbl, fg or C.btnText, bg or C.btn)
  M.addButton(x, y, x + #lbl - 1, y, action)
  return x + #lbl
end

-- Up/down scroll buttons on the far right of a card title bar. Clamps and
-- mutates scroll[id].
function M.scrollArrows(id, x, y, w, count, visible, scroll)
  local maxOff = math.max(0, count - visible)
  if count <= visible then return scroll end
  if (scroll[id] or 0) > maxOff then scroll[id] = maxOff end
  M.put(x + w - 7, y, " \24 ", C.btnText, C.btnOk)
  M.addButton(x + w - 7, y, x + w - 5, y, function() scroll[id] = math.max(0, (scroll[id] or 0) - 1) end)
  M.put(x + w - 4, y, " \25 ", C.btnText, C.btnOk)
  M.addButton(x + w - 4, y, x + w - 2, y, function() scroll[id] = math.min(maxOff, (scroll[id] or 0) + 1) end)
  return scroll
end

return M

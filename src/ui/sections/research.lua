----------------------------------------------------------------------------
-- ui/sections/research.lua -- colony research as a browsable vertical tree.
--
-- Root at top, tiers descending. Branch tabs switch trees; pan arrows move the
-- viewport (monitors are tap-only). Node colour = derived status:
--   finished (green) / active (orange) / available (accent, highlighted) /
--   locked (dim). Tapping a node opens the detail modal.
----------------------------------------------------------------------------

local draw     = require("ui.draw")
local theme    = require("ui.theme")
local research = require("colony.research")
local trunc    = require("ui.format").trunc
local C = theme.C

local M = {}
M.title = "Research"

-- One fixed, readable single-row tile (just the node name, coloured by status)
-- with generous gaps so the connector lines have room to breathe.
local TILE = { w = 18, h = 1, gapX = 3, gapY = 2 }

local function scolor(ds)
  if ds == "finished" then return C.good
  elseif ds == "active" then return C.warn
  elseif ds == "available" then return C.accent
  else return C.dim end
end

local function clampPan(v, canvas, view)
  local maxp = math.max(0, canvas - view)
  if v < 0 then return 0 elseif v > maxp then return maxp else return v end
end

-- Colour key on the card title strip.
local function drawLegend(x, y, w)
  local key = { { "F", C.good }, { "A", C.warn }, { "V", C.accent }, { "L", C.dim } }
  local px = x + w - 1 - (#key * 2)
  for _, e in ipairs(key) do
    draw.put(px, y, e[1], e[2], C.cardTitle)
    px = px + 2
  end
end

-- Windowed branch tabs with ‹/› pagers when they overflow the width.
local function drawTabs(cx, cy, cw, branches, R)
  R.tabOff = R.tabOff or 0
  if R.branchIdx <= R.tabOff then R.tabOff = R.branchIdx - 1 end

  local leftPager = R.tabOff > 0
  local px = cx + (leftPager and 2 or 0)
  local i = R.tabOff + 1
  while i <= #branches do
    local lbl = " " .. branches[i].label .. " "
    local needRight = (i < #branches) and 2 or 0
    if px + #lbl - 1 > cx + cw - 1 - needRight then break end
    local active = (i == R.branchIdx)
    draw.put(px, cy, lbl, active and C.btnText or C.dim, active and C.accent or C.btn)
    local ii = i
    draw.addButton(px, cy, px + #lbl - 1, cy, function()
      R.branchIdx = ii; R.panX, R.panY = 0, 0
    end)
    px = px + #lbl + 1                                   -- one blank cell between tabs
    i = i + 1
  end
  if R.branchIdx >= i and i <= #branches then R.tabOff = R.branchIdx - 1 end

  if leftPager then
    draw.put(cx, cy, "\27 ", C.btnText, C.btnOk)
    draw.addButton(cx, cy, cx + 1, cy, function() R.tabOff = math.max(0, R.tabOff - 1) end)
  end
  if i <= #branches then
    draw.put(cx + cw - 2, cy, " \26", C.btnText, C.btnOk)
    draw.addButton(cx + cw - 2, cy, cx + cw - 1, cy, function()
      R.tabOff = math.min(#branches - 1, R.tabOff + 1)
    end)
  end
end

-- Pan-only controls (left / right / up / down).
local function drawControls(cx, cy, R, stepX, stepY)
  local px = cx
  px = draw.button(px, cy, "\27", C.btn, C.btnText, function() R.panX = R.panX - stepX end) + 1
  px = draw.button(px, cy, "\26", C.btn, C.btnText, function() R.panX = R.panX + stepX end) + 2
  px = draw.button(px, cy, "\24", C.btn, C.btnText, function() R.panY = R.panY - stepY end) + 1
  draw.button(px, cy, "\25", C.btn, C.btnText, function() R.panY = R.panY + stepY end)
end

function M.draw(x, y, w, h, screen, d)
  local branches = d.research or {}
  local cx, cy, cw, ch = draw.card(x, y, w, h, "RESEARCH")
  drawLegend(x, y, w)
  if #branches == 0 then draw.put(cx, cy, "No research data.", C.dim, C.card); return end

  local R = screen.research
  if not R then R = { branchIdx = 1, panX = 0, panY = 0 }; screen.research = R end
  if R.branchIdx > #branches then R.branchIdx = 1 end
  local branch = branches[R.branchIdx]

  drawTabs(cx, cy, cw, branches, R)
  drawControls(cx, cy + 1, R, TILE.w + TILE.gapX, TILE.h + TILE.gapY)

  -- Blank spacer row (cy+2) between the controls and the tree.
  local vx0, vy0 = cx, cy + 3
  local vw, vh = cw, ch - 3
  if vh < 1 then return end
  local vx1, vy1 = vx0 + vw - 1, vy0 + vh - 1

  local lay = research.layout(branch, TILE)
  R.panX = clampPan(R.panX, lay.canvasW, vw)
  R.panY = clampPan(R.panY, lay.canvasH, vh)

  -- Viewport-clipped primitives (draw.put only clips to the whole window, which
  -- would let scrolled content paint over the tab/control rows).
  local function vput(px, py, txt, fg, bg)
    if py < vy0 or py > vy1 then return end
    txt = tostring(txt)
    if px < vx0 then txt = txt:sub(vx0 - px + 1); px = vx0 end
    local room = vx1 - px + 1
    if room <= 0 then return end
    if #txt > room then txt = txt:sub(1, room) end
    if #txt > 0 then draw.put(px, py, txt, fg, bg) end
  end
  local function vfill(px, py, ww, bg)
    if py < vy0 or py > vy1 then return end
    if px < vx0 then ww = ww - (vx0 - px); px = vx0 end
    local room = vx1 - px + 1
    if ww > room then ww = room end
    if ww > 0 then draw.fillRect(px, py, ww, 1, bg) end
  end

  local function pos(canvasX, canvasY) return vx0 + canvasX - 1 - R.panX, vy0 + canvasY - 1 - R.panY end

  -- Connector: a vertical | drop from the parent, then a horizontal - bus on the
  -- row just above the children (a plain | when the child sits straight below).
  local function connect(pcx, pTopY, ccx, cTopY)
    local busY = cTopY - 1
    for yy = pTopY + TILE.h, busY - 1 do vput(pcx, yy, "|", C.dim, C.card) end
    local a, b = math.min(pcx, ccx), math.max(pcx, ccx)
    if a == b then
      vput(a, busY, "|", C.dim, C.card)
    else
      for xx = a, b do vput(xx, busY, "-", C.dim, C.card) end
    end
  end

  local half = math.floor(TILE.w / 2)
  for _, e in ipairs(lay.nodes) do
    if e.parentX then
      local psx, psy = pos(e.parentX, e.parentY)
      local sx, sy = pos(e.x, e.y)
      connect(psx + half, psy, sx + half, sy)
    end
  end

  for _, e in ipairs(lay.nodes) do
    local node = e.node
    local ds = node.dstatus
    local col = scolor(ds)
    local sx, sy = pos(e.x, e.y)

    -- Highlight every node with a status-coloured background + centred,
    -- contrasting text.
    vfill(sx, sy, TILE.w, col)
    local nm = trunc(node.name, TILE.w)
    vput(sx + math.floor((TILE.w - #nm) / 2), sy, nm, colors.black, col)

    local hx1, hy1 = math.max(sx, vx0), math.max(sy, vy0)
    local hx2, hy2 = math.min(sx + TILE.w - 1, vx1), math.min(sy + TILE.h - 1, vy1)
    if hx1 <= hx2 and hy1 <= hy2 then
      draw.addButton(hx1, hy1, hx2, hy2, function() screen.modal = { kind = "research", node = node } end)
    end
  end
end

return M

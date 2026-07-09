----------------------------------------------------------------------------
-- ui/sections/research.lua -- colony research as a zoomable vertical tree.
--
-- Root at top, tiers descending. Branch tabs switch trees; zoom [-]/[+] cycles
-- three tile sizes (dots -> tiles -> tiles+progress); pan arrows move the
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

-- Zoom tiers: OUT (dots), MID (name), IN (name + progress).
local ZOOM = {
  { w = 1,  h = 1, gapX = 1, gapY = 1 },
  { w = 9,  h = 1, gapX = 1, gapY = 1 },
  { w = 16, h = 2, gapX = 2, gapY = 1 },
}

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
    px = px + #lbl
    i = i + 1
  end
  -- Active tab pushed past the window end: advance and correct next frame.
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

local function drawControls(cx, cy, R, stepX, stepY)
  local px = cx
  px = draw.button(px, cy, "-", C.btn, C.btnText, function() R.zoom = math.max(1, R.zoom - 1); R.panX, R.panY = 0, 0 end)
  draw.put(px, cy, "z" .. R.zoom, C.dim, C.card); px = px + 3
  px = draw.button(px, cy, "+", C.btn, C.btnText, function() R.zoom = math.min(#ZOOM, R.zoom + 1); R.panX, R.panY = 0, 0 end)
  px = px + 1
  px = draw.button(px, cy, "\27", C.btn, C.btnText, function() R.panX = R.panX - stepX end)
  px = draw.button(px, cy, "\26", C.btn, C.btnText, function() R.panX = R.panX + stepX end)
  px = draw.button(px, cy, "\24", C.btn, C.btnText, function() R.panY = R.panY - stepY end)
  px = draw.button(px, cy, "\25", C.btn, C.btnText, function() R.panY = R.panY + stepY end)
end

function M.draw(x, y, w, h, screen, d)
  local branches = d.research or {}
  local cx, cy, cw, ch = draw.card(x, y, w, h, "RESEARCH")
  drawLegend(x, y, w)
  if #branches == 0 then draw.put(cx, cy, "No research data.", C.dim, C.card); return end

  local R = screen.research
  if not R then R = { branchIdx = 1, zoom = 2, panX = 0, panY = 0 }; screen.research = R end
  if R.branchIdx > #branches then R.branchIdx = 1 end
  local branch = branches[R.branchIdx]
  local tile = ZOOM[R.zoom]

  drawTabs(cx, cy, cw, branches, R)
  drawControls(cx, cy + 1, R, tile.w + tile.gapX, tile.h + tile.gapY)

  local vx0, vy0 = cx, cy + 2
  local vw, vh = cw, ch - 2
  if vh < 1 then return end

  local lay = research.layout(branch, tile)
  R.panX = clampPan(R.panX, lay.canvasW, vw)
  R.panY = clampPan(R.panY, lay.canvasH, vh)

  -- Viewport-clipped primitives (draw.put only clips to the whole window, which
  -- would let scrolled content paint over the tab/control rows).
  local vx1, vy1 = vx0 + vw - 1, vy0 + vh - 1
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
  local function vbar(px, py, ww, frac, col)
    vfill(px, py, ww, C.screen)
    vfill(px, py, math.floor(ww * math.max(0, math.min(1, frac)) + 0.5), col)
  end

  -- Connector between a parent anchor and a child anchor (single gap row when
  -- gapY = 1). CC has no box-drawing glyphs, so use ASCII | - + for the bus.
  local function connect(pcx, pcy, ccx, ccy)
    local midY = pcy + tile.h                -- row just below the parent tile
    local a, b = math.min(pcx, ccx), math.max(pcx, ccx)
    for xx = a, b do vput(xx, midY, "-", C.dim, C.card) end
    vput(pcx, midY, "+", C.dim, C.card)
    vput(ccx, midY, "+", C.dim, C.card)
    for yy = midY + 1, ccy - 1 do vput(ccx, yy, "|", C.dim, C.card) end
  end

  -- Screen position of a canvas point.
  local function pos(canvasX, canvasY) return vx0 + canvasX - 1 - R.panX, vy0 + canvasY - 1 - R.panY end

  -- Connectors first (under tiles).
  for _, e in ipairs(lay.nodes) do
    if e.parentX then
      local psx, psy = pos(e.parentX, e.parentY)
      local sx, sy = pos(e.x, e.y)
      connect(psx + math.floor(tile.w / 2), psy, sx + math.floor(tile.w / 2), sy)
    end
  end

  -- Tiles + hitboxes.
  for _, e in ipairs(lay.nodes) do
    local node = e.node
    local ds = node.dstatus
    local col = scolor(ds)
    local sx, sy = pos(e.x, e.y)

    if tile.w == 1 then
      -- OUT: colored cell; available gets a bullet so it reads at a glance.
      vput(sx, sy, ds == "available" and "\7" or " ", colors.white, col)
    else
      if ds == "locked" then
        vput(sx, sy, trunc(node.name, tile.w), C.dim, C.card)
      else
        vfill(sx, sy, tile.w, col)
        local label = (ds == "available" and "*" or "") .. node.name
        vput(sx, sy, trunc(label, tile.w), colors.black, col)
      end
      if tile.h >= 2 then
        if ds == "active" or ds == "finished" then
          local pctTxt = tostring(math.floor(node.pct * 100 + 0.5)) .. "%"
          vbar(sx, sy + 1, tile.w - #pctTxt - 1, node.pct, col)
          vput(sx + tile.w - #pctTxt, sy + 1, pctTxt, C.dim, C.card)
        else
          vput(sx, sy + 1, ds == "available" and "ready" or "locked", ds == "available" and C.accent or C.dim, C.card)
        end
      end
    end

    -- Hitbox only over the visible portion of the tile.
    local hx1, hy1 = math.max(sx, vx0), math.max(sy, vy0)
    local hx2, hy2 = math.min(sx + tile.w - 1, vx1), math.min(sy + tile.h - 1, vy1)
    if hx1 <= hx2 and hy1 <= hy2 then
      draw.addButton(hx1, hy1, hx2, hy2, function() screen.modal = { kind = "research", node = node } end)
    end
  end
end

return M

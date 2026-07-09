----------------------------------------------------------------------------
-- ui/layout.lua -- monitor screen composition on Basalt (2-column layout).
--
-- Layout is two ordered columns of sections. Column WIDTH is shared by the
-- number of non-empty columns (an empty column disappears; the other takes the
-- full width). Row HEIGHT within a column is shared by the number of enabled
-- sections in it -- so size is driven purely by how many elements are where,
-- with no manual resizing.
--
-- CC monitors emit only `monitor_touch` (no drag, no scroll wheel), so moving
-- a section is done with tap controls in EDIT mode (reorder within a column,
-- or send it to the other column). Overflow scrolls via touch arrows, plus a
-- Basalt onScroll handler for terminals that do send scroll events.
----------------------------------------------------------------------------

local draw          = require("ui.draw")
local theme         = require("ui.theme")
local engine        = require("ui.layout.engine")
local modalCommon   = require("ui.modals.common")
local applyModal    = require("ui.modals.apply")
local sectionsModal = require("ui.modals.sections")
local researchModal = require("ui.modals.research")
local C = theme.C

local SECTIONS = {
  status    = require("ui.sections.status"),
  workforce = require("ui.sections.workforce"),
  workers   = require("ui.sections.workers"),
  orders    = require("ui.sections.orders"),
  requests  = require("ui.sections.requests"),
  legend    = require("ui.sections.legend"),
  jobskills = require("ui.sections.jobskills"),
  research  = require("ui.sections.research"),
}
-- Section order + geometry live in the pure engine; SECTIONS here maps each id
-- to its draw module (the Basalt/draw side).
local SECTION_ORDER = engine.SECTION_ORDER

local M = {}
M.SECTIONS = SECTIONS
M.SECTION_ORDER = SECTION_ORDER
M.normalizeColumns = engine.normalizeColumns

----------------------------------------------------------------------------
-- Bind the pure geometry (engine.computeRects) to the Basalt section frames.
----------------------------------------------------------------------------

-- Position/size/show the section frames from the current columns.
function M.applyRects(screen)
  engine.normalizeColumns(screen)
  local rects = engine.computeRects(screen)
  for _, id in ipairs(SECTION_ORDER) do
    local sf, sd, r = screen.secFrames[id], screen.secDisp[id], rects[id]
    if sf then
      if r then
        sf.set("visible", true)
        sf:setPosition(r.x, r.y); sf:setSize(r.w, r.h); sd:setSize(r.w, r.h)
      else
        sf.set("visible", false)
      end
    end
  end
end

----------------------------------------------------------------------------
-- Build the Basalt frames for one screen
----------------------------------------------------------------------------

local function routeClick(win, w, h, buttons, x, y, screen)
  draw.setTarget(win, w, h, buttons)
  local action = draw.hit(x, y)
  if action then
    action()
    if screen.env.state.quit then screen.env.stop(); return end
    screen.env.redraw()
  end
end

-- Clickable surfaces attach handlers to a Frame (Containers define the
-- mouse_click / mouse_scroll events); content renders into a child Display,
-- whose window is at (1,1) so frame-relative coords match the drawn hitboxes.
local function makeSectionFrame(screen, id)
  local sf = screen.frame:addFrame({ x = 1, y = 1, width = 10, height = 5 })
  sf.set("visible", false)
  local sd = sf:addDisplay({ x = 1, y = 1, width = 10, height = 5 })
  screen.secFrames[id] = sf
  screen.secDisp[id]   = sd
  screen.secButtons[id] = {}
  sf:onClick(function(_, _btn, x, y)
    routeClick(sd:getWindow(), sf.get("width"), sf.get("height"), screen.secButtons[id], x, y, screen)
    return true
  end)
  -- Basalt native scroll (fires on terminals; monitors use the touch arrows).
  sf:onScroll(function(_, dir)
    screen.scroll[id] = math.max(0, (screen.scroll[id] or 0) + (dir or 0))
    screen.env.redraw()
    return true
  end)
end

function M.buildScreen(screen, env)
  screen.env = env
  screen.secFrames, screen.secDisp, screen.secButtons = {}, {}, {}
  screen.footerButtons = {}

  for _, id in ipairs(SECTION_ORDER) do makeSectionFrame(screen, id) end

  local ff = screen.frame:addFrame({ x = 1, y = screen.H, width = screen.W, height = 1 })
  ff.set("z", 20)
  local fd = ff:addDisplay({ x = 1, y = 1, width = screen.W, height = 1 })
  screen.footerDisp = fd
  ff:onClick(function(_, _btn, x, y)
    routeClick(fd:getWindow(), screen.W, 1, screen.footerButtons, x, y, screen)
    return true
  end)

  -- Native Basalt progress bar for the scan countdown, in the footer gap left of
  -- the EDIT button. Driven by M.updateScanBar from the app's fine-grained loop.
  local barW = math.min(14, screen.W - 20)
  if barW >= 4 then
    screen.scanBar = ff:addProgressBar({ x = screen.W - 3 - barW, y = 1,
      width = barW, height = 1, progress = 0, direction = "right" })
    screen.scanBar.set("z", 30)
  end

  -- Native Basalt modal (real widgets) for BOTH the suggestion popup and the
  -- SECTIONS toggle overlay. Full-screen so it blocks taps to the sections
  -- beneath; the card subtree is built on open and torn down on close.
  local nmf = screen.frame:addFrame({ x = 1, y = 1, width = screen.W, height = screen.H,
    background = C.screen })
  nmf.set("z", 600); nmf.set("visible", false); nmf.set("enabled", false)
  nmf:onClick(function() return true end)  -- swallow taps outside the card
  screen.nmodalFrame = nmf

  M.applyRects(screen)
end

----------------------------------------------------------------------------
-- EDIT mode: tap-move (reorder within a column / change column)
----------------------------------------------------------------------------

local function findCol(screen, id)
  for ci = 1, 2 do
    for i, v in ipairs(screen.columns[ci] or {}) do
      if v == id then return ci, i end
    end
  end
end

local function afterEdit(screen)
  M.applyRects(screen)
  screen.env.hooks.save()
end

local function moveInCol(screen, id, dir)
  local ci, i = findCol(screen, id); if not ci then return end
  local l = screen.columns[ci]; local j = i + dir
  if l[j] then l[i], l[j] = l[j], l[i] end
  afterEdit(screen)
end

local function moveToOtherCol(screen, id)
  local ci, i = findCol(screen, id); if not ci then return end
  local other = (ci == 1) and 2 or 1
  table.remove(screen.columns[ci], i)
  screen.columns[other] = screen.columns[other] or {}
  table.insert(screen.columns[other], id)
  afterEdit(screen)
end

local function resizeHeight(screen, id, delta)
  screen.weights = screen.weights or {}
  screen.weights[id] = math.max(1, engine.weightOf(screen, id) + delta)
  afterEdit(screen)
end

function M.toggleEdit(screen) screen.edit = not screen.edit end

-- EDIT controls on a section's bottom row: reorder, change column, resize height.
local function moveControls(screen, id, w, h)
  local ci = findCol(screen, id)
  local y = h
  local x = 1
  x = draw.button(x, y, "\24", C.accent, colors.black, function() moveInCol(screen, id, -1) end)
  x = draw.button(x, y, "\25", C.accent, colors.black, function() moveInCol(screen, id, 1) end)
  local lbl = (ci == 1) and "\26" or "\27"  -- -> to column 2, <- to column 1
  x = draw.button(x, y, lbl, C.good, colors.black, function() moveToOtherCol(screen, id) end)
  x = draw.button(x, y, "-", C.warn, C.btnText, function() resizeHeight(screen, id, -1) end)
  draw.button(x, y, "+", C.good, C.btnText, function() resizeHeight(screen, id, 1) end)
end

----------------------------------------------------------------------------
-- Footer + modals
----------------------------------------------------------------------------

-- Right-aligned button: draws " label " ending at the current right edge,
-- returns the new right edge (one cell of gap to its left).
local function rbutton(rx, label, bg, fg, action)
  local w = #label + 2
  local x = rx - w + 1
  draw.button(x, 1, label, bg, fg, action)
  return x - 2
end

local function drawFooter(screen, data, state, hooks)
  local W = screen.W
  draw.fillRect(1, 1, W, 1, C.cardTitle)

  -- Left: colony / theme info.
  local info = string.format("%s #%s  %s",
    tostring(data and data.name or "?"), tostring(data and data.id or "?"),
    theme.THEMES[state.theme] and state.theme or "?")
  draw.put(2, 1, info, C.dim, C.cardTitle)

  -- Right: small EDIT icon; THEME + SECTIONS appear (to its left) only in EDIT.
  local rx = W - 1
  rx = rbutton(rx, screen.edit and "E*" or "E",
    screen.edit and C.good or C.accent2, colors.black, function() M.toggleEdit(screen) end)
  if screen.edit then
    rx = rbutton(rx, "THEME", C.accent, colors.black, function() hooks.cycleTheme() end)
    rx = rbutton(rx, "SECTIONS", C.btn, C.btnText, function() screen.modal = { kind = "sections" } end)
  end
end


----------------------------------------------------------------------------
-- Render one screen (called each refresh)
----------------------------------------------------------------------------

-- Deps handed to the sections modal (passed in to avoid a require cycle back
-- into layout, which owns section registration + geometry).
local modalDeps = { SECTION_ORDER = SECTION_ORDER, SECTIONS = SECTIONS,
  isShown = engine.isShown, applyRects = M.applyRects }

-- Track a moving citizen in the open apply modal (called by the app poll loop).
M.refreshModalLocation = applyModal.refreshLocation

-- Update the native scan progress bar (0..1). Called frequently by the app's
-- fine-grained loop; hidden in EDIT mode so the THEME/SECTIONS buttons show.
function M.updateScanBar(screen, frac)
  local b = screen.scanBar
  if not b then return end
  if screen.edit then b.set("visible", false); return end
  b.set("visible", true)
  b.set("background", C.screen)
  b.set("progressColor", C.good)
  b.set("progress", math.max(0, math.min(100, math.floor((frac or 0) * 100 + 0.5))))
end

function M.render(screen, data, state, hooks)
  for _, id in ipairs(SECTION_ORDER) do
    local sf, sd = screen.secFrames[id], screen.secDisp[id]
    if sf and sf.get("visible") and data then
      local w, h = sf.get("width"), sf.get("height")
      local win = sd:getWindow()
      local btns = {}
      draw.setTarget(win, w, h, btns)
      screen.secButtons[id] = btns
      win.setBackgroundColor(C.screen); win.clear()
      SECTIONS[id].draw(1, 1, w, h, screen, data)
      if screen.edit then moveControls(screen, id, w, h) end
    end
  end

  do
    local fw = screen.footerDisp:getWindow()
    local btns = {}
    draw.setTarget(fw, screen.W, 1, btns)
    screen.footerButtons = btns
    drawFooter(screen, data, state, hooks)
  end

  if screen.modal and screen.modal.kind == "apply" then
    applyModal.show(screen, screen.modal.sug)
  elseif screen.modal and screen.modal.kind == "sections" then
    sectionsModal.show(screen, hooks, modalDeps)
  elseif screen.modal and screen.modal.kind == "research" then
    researchModal.show(screen, screen.modal.node)
  else
    modalCommon.hide(screen)
  end
end

return M

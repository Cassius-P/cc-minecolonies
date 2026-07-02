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

local draw  = require("ui.draw")
local theme = require("ui.theme")
local util  = require("common.util")
local C = theme.C

local SECTIONS = {
  status    = require("ui.sections.status"),
  workforce = require("ui.sections.workforce"),
  workers   = require("ui.sections.workers"),
  orders    = require("ui.sections.orders"),
  requests  = require("ui.sections.requests"),
  legend    = require("ui.sections.legend"),
  jobskills = require("ui.sections.jobskills"),
}
local SECTION_ORDER = { "status", "workforce", "workers", "orders", "requests", "legend", "jobskills" }
-- Sections hidden unless explicitly enabled (enabled[id] == true).
local DEFAULT_HIDDEN = { jobskills = true }

local function isShown(screen, id)
  if DEFAULT_HIDDEN[id] then return screen.enabled[id] == true end
  return screen.enabled[id] ~= false
end

local M = {}
M.SECTIONS = SECTIONS
M.SECTION_ORDER = SECTION_ORDER

----------------------------------------------------------------------------
-- Geometry from the two columns
----------------------------------------------------------------------------

-- Ensure screen.columns is two clean lists holding every section exactly once.
-- Tolerates a missing/old config (e.g. preserved config.lua from a prior
-- version that used the flexbox layout instead of columns).
function M.normalizeColumns(screen)
  local cols = type(screen.columns) == "table" and screen.columns or {}
  cols[1] = type(cols[1]) == "table" and cols[1] or {}
  cols[2] = type(cols[2]) == "table" and cols[2] or {}
  local seen = {}
  for ci = 1, 2 do
    local clean = {}
    for _, id in ipairs(cols[ci]) do
      if SECTIONS[id] and not seen[id] then seen[id] = true; clean[#clean + 1] = id end
    end
    cols[ci] = clean
  end
  for _, id in ipairs(SECTION_ORDER) do
    if not seen[id] then table.insert(cols[1], id); seen[id] = true end
  end
  screen.columns = cols
end

-- Enabled sections in a column, in order.
local function enabledIn(screen, ci)
  local out = {}
  for _, id in ipairs(screen.columns[ci] or {}) do
    if isShown(screen, id) then out[#out + 1] = id end
  end
  return out
end

local COLGAP = 1        -- blank column between the two columns
local DEFAULT_WEIGHT = 6 -- baseline height share, so a section can shrink below default

local function weightOf(screen, id)
  local w = screen.weights and screen.weights[id]
  return (type(w) == "number" and w > 0) and w or DEFAULT_WEIGHT
end

-- rects[id] = {x,y,w,h} for every visible section. Column width is shared by
-- the active columns (minus a gap); row height within a column is shared by
-- each section's weight (so resizing one grows/shrinks its siblings).
local function computeRects(screen)
  local active = {}
  for ci = 1, 2 do
    local ids = enabledIn(screen, ci)
    if #ids > 0 then active[#active + 1] = ids end
  end
  local rects = {}
  local nCols = #active
  if nCols == 0 then return rects end
  local availW = screen.W - COLGAP * (nCols - 1)
  local availH = screen.H - 1                         -- last row is the footer
  local baseW = math.floor(availW / nCols)
  local xcursor = 1
  for i, ids in ipairs(active) do
    local w = (i == nCols) and (screen.W - xcursor + 1) or baseW
    local x = xcursor
    local sum = 0
    for _, id in ipairs(ids) do sum = sum + weightOf(screen, id) end
    local ycursor, used = 1, 0
    for j, id in ipairs(ids) do
      local wt = weightOf(screen, id)
      local h = (j == #ids) and (availH - used) or math.max(1, math.floor(availH * wt / sum))
      rects[id] = { x = x, y = ycursor, w = w, h = h }
      ycursor = ycursor + h
      used = used + h
    end
    xcursor = xcursor + w + COLGAP
  end
  return rects
end

-- Position/size/show the section frames from the current columns.
function M.applyRects(screen)
  M.normalizeColumns(screen)
  local rects = computeRects(screen)
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
  screen.footerButtons, screen.modalButtons = {}, {}

  for _, id in ipairs(SECTION_ORDER) do makeSectionFrame(screen, id) end

  local ff = screen.frame:addFrame({ x = 1, y = screen.H, width = screen.W, height = 1 })
  ff.set("z", 20)
  local fd = ff:addDisplay({ x = 1, y = 1, width = screen.W, height = 1 })
  screen.footerDisp = fd
  ff:onClick(function(_, _btn, x, y)
    routeClick(fd:getWindow(), screen.W, 1, screen.footerButtons, x, y, screen)
    return true
  end)

  local mf = screen.frame:addFrame({ x = 1, y = 1, width = screen.W, height = screen.H })
  mf.set("z", 500); mf.set("visible", false)
  local md = mf:addDisplay({ x = 1, y = 1, width = screen.W, height = screen.H })
  screen.modalFrame, screen.modalDisp = mf, md
  mf:onClick(function(_, _btn, x, y)
    routeClick(md:getWindow(), screen.W, screen.H, screen.modalButtons, x, y, screen)
    return true
  end)

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
  screen.weights[id] = math.max(1, weightOf(screen, id) + delta)
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

  -- Left: colony / theme / countdown info.
  local info = string.format("%s #%s  %s  %02ds",
    tostring(data and data.name or "?"), tostring(data and data.id or "?"),
    theme.THEMES[state.theme] and state.theme or "?", state.countdown)
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

local function applyModal(screen, s, data)
  local W, H = screen.W, screen.H
  local locStr = util.locStr
  local mw = math.min(W - 4, 46)
  local mh = math.min(H - 4, 13)
  local mx = math.floor((W - mw) / 2) + 1
  local my = math.floor((H - mh) / 2) + 1
  local cx, cy = draw.card(mx, my, mw, mh, "APPLY SUGGESTION")
  local row = cy
  local lines
  if s.kind == "assign" then
    lines = {
      { "Job:      " .. s.job, C.text }, { "Building: " .. locStr(s.building.location), C.text },
      { "Hire:     " .. s.candidate.name .. " (" .. s.candidate.score .. ")", C.good },
      { "", C.text }, { "Manual steps:", C.accent2 },
      { " 1. Go to " .. locStr(s.building.location), C.dim },
      { " 2. Open hut GUI \26 Hire/Fire", C.dim }, { " 3. Slot in " .. s.candidate.name, C.dim },
    }
  elseif s.kind == "reassign" then
    lines = {
      { "Move:     " .. s.candidate.name, C.note },
      { "From job: " .. tostring(s.from), C.text },
      { "To job:   " .. s.job .. " (fit " .. s.candidate.score .. ")", C.good },
      { "At:       " .. locStr(s.building.location), C.text },
      { "Manual steps:", C.accent2 },
      { " 1. Fire " .. s.candidate.name .. " from their " .. tostring(s.from) .. " hut", C.dim },
      { " 2. Go to " .. locStr(s.building.location), C.dim },
      { " 3. " .. (s.target and ("Fire " .. s.target.name .. ", hire " .. s.candidate.name)
          or ("Hire " .. s.candidate.name)), C.dim },
    }
  else
    lines = {
      { "Job:      " .. s.job, C.text }, { "Building: " .. locStr(s.building.location), C.text },
      { "Fire:     " .. s.target.name .. " (" .. s.target.score .. ")", C.bad },
      { "Hire:     " .. s.candidate.name .. " (" .. s.candidate.score .. ")", C.good },
      { "Manual steps:", C.accent2 }, { " 1. Go to " .. locStr(s.building.location), C.dim },
      { " 2. Open GUI \26 Hire/Fire", C.dim },
      { " 3. Fire " .. s.target.name .. ", hire " .. s.candidate.name, C.dim },
    }
  end
  for _, ln in ipairs(lines) do
    if row > my + mh - 3 then break end
    draw.put(cx, row, ln[1], ln[2], C.card); row = row + 1
  end
  draw.put(cx, my + mh - 2, "API read-only; hire manually.", C.dim, C.card)
  local bx = cx
  bx = draw.button(bx, my + mh - 1, "HANDLED", C.btnOk, C.btnText, function()
    for i, it in ipairs(data.suggestions) do if it == s then table.remove(data.suggestions, i); break end end
    screen.modal = nil
  end) + 1
  draw.button(bx, my + mh - 1, "BACK", colors.lightGray, colors.black, function() screen.modal = nil end)
end

local function sectionsModal(screen, hooks)
  local W, H = screen.W, screen.H
  local mw = math.min(W - 4, 34)
  local mh = math.min(H - 4, #SECTION_ORDER + 4)
  local mx = math.floor((W - mw) / 2) + 1
  local my = math.floor((H - mh) / 2) + 1
  local cx, cy = draw.card(mx, my, mw, mh, "SECTIONS")
  draw.put(cx, cy, "Tap to toggle visibility:", C.dim, C.card)
  for i, id in ipairs(SECTION_ORDER) do
    local ry = cy + i
    if ry > my + mh - 2 then break end
    local on = isShown(screen, id)
    draw.put(cx, ry, on and "[x]" or "[ ]", on and C.good or C.dim, C.card)
    draw.put(cx + 4, ry, SECTIONS[id].title, on and C.text or C.dim, C.card)
    draw.addButton(cx, ry, cx + mw - 3, ry, function()
      screen.enabled[id] = not on
      M.applyRects(screen)
      hooks.save()
    end)
  end
  draw.button(cx, my + mh - 1, "CLOSE", C.btnOk, C.btnText, function() screen.modal = nil end)
end

----------------------------------------------------------------------------
-- Render one screen (called each refresh)
----------------------------------------------------------------------------

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

  if screen.modal then
    screen.modalFrame.set("visible", true)
    local mw = screen.modalDisp:getWindow()
    local btns = {}
    draw.setTarget(mw, screen.W, screen.H, btns)
    screen.modalButtons = btns
    mw.setBackgroundColor(C.screen); mw.clear()
    if screen.modal.kind == "apply" then applyModal(screen, screen.modal.sug, data)
    elseif screen.modal.kind == "sections" then sectionsModal(screen, hooks) end
  else
    screen.modalFrame.set("visible", false)
  end
end

return M

----------------------------------------------------------------------------
-- ui/layout.lua -- monitor screen composition on Basalt.
--
-- Each section is its own Basalt Frame (with a Display inside for rendering).
-- Sections are positioned by a saved per-monitor geometry; defaults are
-- derived once from the flexbox tree in config. In EDIT mode a section frame
-- becomes `draggable` (drag its top row to move it anywhere) and shows resize
-- controls that call the frame's setSize. A footer Display carries the
-- THEME/SECTIONS/EDIT buttons; a high-z overlay frame carries modals.
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
}
local SECTION_ORDER = { "status", "workforce", "workers", "orders", "requests", "legend" }

local M = {}
M.SECTIONS = SECTIONS
M.SECTION_ORDER = SECTION_ORDER

local GAP, MINW, MINH = 1, 8, 3

----------------------------------------------------------------------------
-- Default geometry from the flexbox tree (all sections laid out once)
----------------------------------------------------------------------------

local function countLeaves(node)
  if node.section then return 1 end
  local n = 0
  for _, ch in ipairs(node) do n = n + countLeaves(ch) end
  return n
end

local function walk(node, x, y, w, h, out)
  if w <= 0 or h <= 0 then return end
  if node.section then out[node.section] = { x = x, y = y, w = w, h = h }; return end
  local horizontal = (node.dir == "row")
  local vis = {}
  for _, ch in ipairs(node) do if countLeaves(ch) > 0 then vis[#vis + 1] = ch end end
  local n = #vis; if n == 0 then return end
  local main = horizontal and w or h
  local avail = main - GAP * (n - 1); if avail < n then avail = n end
  local sizes, sumMin, totalFlex = {}, 0, 0
  for _, ch in ipairs(vis) do sumMin = sumMin + (ch.min or 1); totalFlex = totalFlex + (ch.flex or 1) end
  if sumMin <= avail then
    local surplus = avail - sumMin
    for i, ch in ipairs(vis) do
      local add = totalFlex > 0 and math.floor(surplus * (ch.flex or 1) / totalFlex) or 0
      local sz = (ch.min or 1) + add
      local mx = ch.max or math.huge; if sz > mx then sz = mx end
      sizes[i] = sz
    end
  else
    for i, ch in ipairs(vis) do sizes[i] = math.max(1, math.floor(avail * (ch.flex or 1) / math.max(1, totalFlex))) end
  end
  local tot = 0
  for _, sz in ipairs(sizes) do tot = tot + sz end
  sizes[n] = math.max(1, sizes[n] + (avail - tot))
  local pos = horizontal and x or y
  for i, ch in ipairs(vis) do
    local s = sizes[i]
    if horizontal then walk(ch, pos, y, s, h, out) else walk(ch, x, pos, w, s, out) end
    pos = pos + s + GAP
  end
end

function M.defaultGeometry(screen)
  local out = {}
  walk(screen.layoutTree, 1, 1, screen.W, screen.H - 1, out)
  for _, id in ipairs(SECTION_ORDER) do
    if not out[id] then
      out[id] = { x = 2, y = 2, w = math.min(20, screen.W - 2), h = math.min(6, screen.H - 2) }
    end
  end
  return out
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

local function makeSectionFrame(screen, id)
  local g = screen.geometry[id]
  local sf = screen.frame:addFrame({ x = g.x, y = g.y, width = g.w, height = g.h })
  sf.set("visible", screen.enabled[id] ~= false)
  local sd = sf:addDisplay({ x = 1, y = 1, width = g.w, height = g.h })
  screen.secFrames[id] = sf
  screen.secDisp[id]   = sd
  screen.secButtons[id] = {}
  sd:onClick(function(_, _btn, x, y)
    routeClick(sd:getWindow(), sf.get("width"), sf.get("height"), screen.secButtons[id], x, y, screen)
    return true
  end)
end

function M.buildScreen(screen, env)
  screen.env = env
  screen.secFrames, screen.secDisp, screen.secButtons = {}, {}, {}
  screen.footerButtons, screen.modalButtons = {}, {}
  if not screen.geometry then screen.geometry = M.defaultGeometry(screen) end

  for _, id in ipairs(SECTION_ORDER) do makeSectionFrame(screen, id) end

  -- Footer strip (1 row at the bottom).
  local fd = screen.frame:addDisplay({ x = 1, y = screen.H, width = screen.W, height = 1 })
  fd.set("z", 20)
  screen.footerDisp = fd
  fd:onClick(function(_, _btn, x, y)
    routeClick(fd:getWindow(), screen.W, 1, screen.footerButtons, x, y, screen)
    return true
  end)

  -- Modal overlay (hidden until a modal is set).
  local mf = screen.frame:addFrame({ x = 1, y = 1, width = screen.W, height = screen.H })
  mf.set("z", 500); mf.set("visible", false)
  local md = mf:addDisplay({ x = 1, y = 1, width = screen.W, height = screen.H })
  screen.modalFrame, screen.modalDisp = mf, md
  md:onClick(function(_, _btn, x, y)
    routeClick(md:getWindow(), screen.W, screen.H, screen.modalButtons, x, y, screen)
    return true
  end)
end

-- Reposition/resize existing frames from screen.geometry + visibility.
function M.applyGeometry(screen)
  for _, id in ipairs(SECTION_ORDER) do
    local sf, sd, g = screen.secFrames[id], screen.secDisp[id], screen.geometry[id]
    if sf and g then sf:setPosition(g.x, g.y); sf:setSize(g.w, g.h); sd:setSize(g.w, g.h) end
    if sf then sf.set("visible", screen.enabled[id] ~= false) end
  end
end

----------------------------------------------------------------------------
-- EDIT mode: native drag (move) + setSize (resize)
----------------------------------------------------------------------------

local function captureGeometry(screen)
  for _, id in ipairs(SECTION_ORDER) do
    local sf = screen.secFrames[id]
    if sf then
      screen.geometry[id] = { x = sf.get("x"), y = sf.get("y"), w = sf.get("width"), h = sf.get("height") }
    end
  end
end

function M.toggleEdit(screen)
  screen.edit = not screen.edit
  for _, id in ipairs(SECTION_ORDER) do
    local sf = screen.secFrames[id]
    if sf then sf.set("draggable", screen.edit) end
  end
  if not screen.edit then captureGeometry(screen); screen.env.hooks.save() end
end

local function resize(screen, id, dw, dh)
  local sf, sd = screen.secFrames[id], screen.secDisp[id]
  local w = math.max(MINW, math.min(screen.W, sf.get("width") + dw))
  local h = math.max(MINH, math.min(screen.H - 1, sf.get("height") + dh))
  sf:setSize(w, h); sd:setSize(w, h)
  screen.geometry[id] = { x = sf.get("x"), y = sf.get("y"), w = w, h = h }
  screen.env.hooks.save()
end

local function resizeControls(screen, id, w, h)
  local y = h
  local x = 1
  x = draw.button(x, y, "-W", C.warn, C.btnText, function() resize(screen, id, -2, 0) end)
  x = draw.button(x, y, "+W", C.good, C.btnText, function() resize(screen, id, 2, 0) end)
  x = draw.button(x, y, "-H", C.warn, C.btnText, function() resize(screen, id, 0, -1) end)
  x = draw.button(x, y, "+H", C.good, C.btnText, function() resize(screen, id, 0, 1) end)
end

----------------------------------------------------------------------------
-- Footer + modals
----------------------------------------------------------------------------

local function drawFooter(screen, data, state, hooks)
  local W = screen.W
  draw.fillRect(1, 1, W, 1, C.cardTitle)
  local x = 2
  x = draw.button(x, 1, "THEME", C.accent, colors.black, function() hooks.cycleTheme() end) + 1
  x = draw.button(x, 1, "SECTIONS", C.btn, C.btnText, function() screen.modal = { kind = "sections" } end) + 1
  x = draw.button(x, 1, screen.edit and "EDIT*" or "EDIT", screen.edit and C.good or C.accent2, colors.black,
    function() M.toggleEdit(screen) end) + 2
  local right = string.format("%s #%s  %s  %02ds",
    tostring(data and data.name or "?"), tostring(data and data.id or "?"),
    theme.THEMES[state.theme] and state.theme or "?", state.countdown)
  draw.put(W - #right - 1, 1, right, C.dim, C.cardTitle)
  if state.msg ~= "" and x < W - #right - 2 then draw.put(x, 1, state.msg, C.dim, C.cardTitle) end
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
    local on = screen.enabled[id] ~= false
    draw.put(cx, ry, on and "[x]" or "[ ]", on and C.good or C.dim, C.card)
    draw.put(cx + 4, ry, SECTIONS[id].title, on and C.text or C.dim, C.card)
    draw.addButton(cx, ry, cx + mw - 3, ry, function()
      screen.enabled[id] = not on
      local sf = screen.secFrames[id]
      if sf then sf.set("visible", not on) end
      hooks.save()
    end)
  end
  draw.button(cx, my + mh - 1, "CLOSE", C.btnOk, C.btnText, function() screen.modal = nil end)
end

----------------------------------------------------------------------------
-- Render one screen (called each refresh)
----------------------------------------------------------------------------

function M.render(screen, data, state, hooks)
  -- Sections
  for _, id in ipairs(SECTION_ORDER) do
    local sf, sd = screen.secFrames[id], screen.secDisp[id]
    if sf then
      local visible = screen.enabled[id] ~= false
      sf.set("visible", visible)
      if visible and data then
        local w, h = sf.get("width"), sf.get("height")
        local win = sd:getWindow()
        local btns = {}
        draw.setTarget(win, w, h, btns)
        screen.secButtons[id] = btns
        win.setBackgroundColor(C.screen); win.clear()
        SECTIONS[id].draw(1, 1, w, h, screen, data)
        if screen.edit then resizeControls(screen, id, w, h) end
      end
    end
  end

  -- Footer
  do
    local fw = screen.footerDisp:getWindow()
    local btns = {}
    draw.setTarget(fw, screen.W, 1, btns)
    screen.footerButtons = btns
    drawFooter(screen, data, state, hooks)
  end

  -- Modal overlay
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

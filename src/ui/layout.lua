----------------------------------------------------------------------------
-- ui/layout.lua -- flexbox-like layout engine + section registry + footer +
-- modals. Renders one screen (into its Basalt Display window) each frame.
--
-- The layout is a tree of row/col containers and section leaves. Each node has
-- flex (main-axis weight), min, max (cell clamps); the cross axis fills. On a
-- monitor too small for all mins, sections shrink but never vanish.
----------------------------------------------------------------------------

local draw  = require("ui.draw")
local theme = require("ui.theme")
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

local GAP = 1

local function isEnabled(screen, id) return screen.enabled[id] ~= false end

local function countVisible(screen, node)
  if node.section then return isEnabled(screen, node.section) and 1 or 0 end
  local n = 0
  for _, ch in ipairs(node) do n = n + countVisible(screen, ch) end
  return n
end

local function moveNode(parent, ri, dir)
  local j = ri + dir
  if parent[j] then parent[ri], parent[j] = parent[j], parent[ri] end
end

local function editControls(node, parent, ri, x, y, w, hooks)
  if not parent then return end
  local bx = x + w - 13
  if bx < x + 1 then bx = x + 1 end
  bx = draw.button(bx, y, "-", C.warn, C.btnText, function() node.flex = math.max(1, (node.flex or 1) - 2); hooks.save() end)
  bx = draw.button(bx, y, "+", C.good, C.btnText, function() node.flex = (node.flex or 1) + 2; hooks.save() end)
  bx = draw.button(bx, y, "\24", C.accent, colors.black, function() moveNode(parent, ri, -1); hooks.save() end)
  bx = draw.button(bx, y, "\25", C.accent, colors.black, function() moveNode(parent, ri, 1); hooks.save() end)
end

local function layoutNode(screen, data, hooks, node, x, y, w, h, parent, ri)
  if w <= 0 or h <= 0 then return end
  if node.section then
    if not isEnabled(screen, node.section) then return end
    local sec = SECTIONS[node.section]
    if sec then sec.draw(x, y, w, h, screen, data) end
    if screen.edit then editControls(node, parent, ri, x, y, w, hooks) end
    return
  end

  local horizontal = (node.dir == "row")
  local vis = {}
  for i, ch in ipairs(node) do if countVisible(screen, ch) > 0 then vis[#vis + 1] = { node = ch, ri = i } end end
  local n = #vis
  if n == 0 then return end

  local main = horizontal and w or h
  local avail = main - GAP * (n - 1)
  if avail < n then avail = n end

  local sizes = {}
  local sumMin, totalFlex = 0, 0
  for _, e in ipairs(vis) do sumMin = sumMin + (e.node.min or 1); totalFlex = totalFlex + (e.node.flex or 1) end

  if sumMin <= avail then
    local surplus = avail - sumMin
    for i, e in ipairs(vis) do
      local add = totalFlex > 0 and math.floor(surplus * (e.node.flex or 1) / totalFlex) or 0
      local sz = (e.node.min or 1) + add
      local mx = e.node.max or math.huge
      if sz > mx then sz = mx end
      sizes[i] = sz
    end
  else
    for i, e in ipairs(vis) do
      sizes[i] = math.max(1, math.floor(avail * (e.node.flex or 1) / math.max(1, totalFlex)))
    end
  end

  local tot = 0
  for _, sz in ipairs(sizes) do tot = tot + sz end
  sizes[n] = math.max(1, sizes[n] + (avail - tot))

  local pos = horizontal and x or y
  for i, e in ipairs(vis) do
    local s = sizes[i]
    if s > 0 then
      if horizontal then layoutNode(screen, data, hooks, e.node, pos, y, s, h, node, e.ri)
      else layoutNode(screen, data, hooks, e.node, x, pos, w, s, node, e.ri) end
      pos = pos + s + GAP
    end
  end
end

----------------------------------------------------------------------------
-- Footer / modals
----------------------------------------------------------------------------

local function drawFooter(screen, data, state, hooks)
  local W, H = screen.W, screen.H
  draw.fillRect(1, H, W, 1, C.cardTitle)
  local x = 2
  x = draw.button(x, H, "REFRESH", C.btnOk, C.btnText, function() hooks.requestScan() end) + 1
  x = draw.button(x, H, "THEME", C.accent, colors.black, function() hooks.cycleTheme() end) + 1
  x = draw.button(x, H, "SECTIONS", C.btn, C.btnText, function() screen.modal = { kind = "sections" } end) + 1
  x = draw.button(x, H, screen.edit and "EDIT*" or "EDIT", screen.edit and C.good or C.accent2, colors.black,
    function() screen.edit = not screen.edit end) + 2
  local right = string.format("%s #%s  %s  %02ds",
    tostring(data.name), tostring(data.id), theme.THEMES[state.theme] and state.theme or "?", state.countdown)
  draw.put(W - #right - 1, H, right, C.dim, C.cardTitle)
  if state.msg ~= "" and x < W - #right - 2 then draw.put(x, H, state.msg, C.dim, C.cardTitle) end
end

local function drawApplyModal(screen, s, data)
  local W, H = screen.W, screen.H
  local util = require("common.util")
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

local function drawSectionsModal(screen, hooks)
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
    local on = isEnabled(screen, id)
    draw.put(cx, ry, on and "[x]" or "[ ]", on and C.good or C.dim, C.card)
    draw.put(cx + 4, ry, SECTIONS[id].title, on and C.text or C.dim, C.card)
    draw.addButton(cx, ry, cx + mw - 3, ry, function() screen.enabled[id] = not on; hooks.save() end)
  end
  draw.button(cx, my + mh - 1, "CLOSE", C.btnOk, C.btnText, function() screen.modal = nil end)
end

----------------------------------------------------------------------------
-- Render one screen
----------------------------------------------------------------------------

function M.render(screen, data, state, hooks)
  local win = screen.win
  screen.W, screen.H = win.getSize()
  draw.setTarget(win, screen.W, screen.H, screen.buttons or {})
  screen.buttons = draw.clearButtons()
  win.setBackgroundColor(C.screen); win.clear()

  if not data then draw.put(2, 2, "Scanning...", C.dim); return end

  layoutNode(screen, data, hooks, screen.layout, 1, 1, screen.W, screen.H - 1)
  drawFooter(screen, data, state, hooks)

  if screen.modal then
    screen.buttons = draw.clearButtons()  -- overlay captures all clicks
    if screen.modal.kind == "apply" then drawApplyModal(screen, screen.modal.sug, data)
    elseif screen.modal.kind == "sections" then drawSectionsModal(screen, hooks) end
  end
end

return M

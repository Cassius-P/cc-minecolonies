----------------------------------------------------------------------------
-- ui/modals/research.lua -- research node detail (native Basalt widgets).
--
-- Title = node name. Body: derived status + progress, then requirements (each
-- ✓/✗ so an unmet precondition is obvious), effects, and cost. Content-sized
-- card clamped to the screen; overflow is capped with a "(+N more)" line
-- (modals here are static -- no scroll).
----------------------------------------------------------------------------

local theme  = require("ui.theme")
local common = require("ui.modals.common")
local trunc  = require("ui.format").trunc
local C = theme.C

local M = {}

local DS = {
  finished  = { "Finished", C.good },
  active    = { "In progress", C.warn },
  available = { "Available", C.accent },
  locked    = { "Locked", C.dim },
}

local function build(screen, node)
  local W, H = screen.W, screen.H
  local nmf = screen.nmodalFrame
  common.clearCard(screen)
  nmf.set("background", C.screen)
  nmf.set("visible", true)
  nmf.set("enabled", true)

  local rows = {}
  local function add(txt, fg) rows[#rows + 1] = { txt, fg or C.text } end

  local ds = DS[node.dstatus] or { node.status or "?", C.text }
  add("Status: " .. ds[1], ds[2])
  add("Progress: " .. math.floor((node.pct or 0) * 100 + 0.5) .. "%", C.text)
  if #node.requirements > 0 then
    add("Requirements:", C.dim)
    for _, r in ipairs(node.requirements) do
      add((r.fulfilled and "\7 " or "! ") .. tostring(r.desc or "?"), r.fulfilled and C.good or C.bad)
    end
  end
  if #node.effects > 0 then
    add("Effects:", C.dim)
    for _, e in ipairs(node.effects) do add("- " .. tostring(e), C.text) end
  end
  if #node.cost > 0 then
    add("Cost:", C.dim)
    for _, c in ipairs(node.cost) do
      local it = c.validItems and c.validItems[1]
      local nm = it and (it.displayName or it.name) or "?"
      add("- " .. tostring(c.count or 1) .. " x " .. tostring(nm), C.text)
    end
  end

  local mw = math.min(W - 2, 46)
  local mh = math.min(H - 2, #rows + 4)
  local capacity = mh - 3                                  -- content rows: y = 3 .. mh-1
  local mx = math.floor((W - mw) / 2) + 1
  local my = math.floor((H - mh) / 2) + 1
  local card = nmf:addFrame({ x = mx, y = my, width = mw, height = mh, background = C.card })
  screen.nmodalCard = card

  card:addLabel({ x = 1, y = 1, width = mw, height = 1, autoSize = false,
    backgroundEnabled = true, background = C.cardTitle, foreground = C.titleText })
    :setText(" " .. tostring(node.name or "?"))

  local shown = #rows
  if shown > capacity then shown = capacity - 1 end
  local iy = 3
  for i = 1, shown do
    card:addLabel({ x = 2, y = iy, background = C.card, foreground = rows[i][2] })
      :setText(trunc(rows[i][1], mw - 2))
    iy = iy + 1
  end
  if #rows > capacity then
    card:addLabel({ x = 2, y = iy, background = C.card, foreground = C.dim })
      :setText(("... (+%d more)"):format(#rows - shown))
  end

  card:addButton({ x = mw - 8, y = mh, width = 8, height = 1,
    background = C.btnOk, foreground = C.btnText }):setText("Close")
    :onClick(function() screen.modal = nil; screen.env.redraw() end)
end

-- Rebuild only when the shown node changes (render runs every tick).
function M.show(screen, node)
  if screen.nmodalKind == "research" and screen.nmodalNode == node and screen.nmodalFrame.get("visible") then return end
  build(screen, node)
  screen.nmodalKind = "research"; screen.nmodalNode = node
end

return M

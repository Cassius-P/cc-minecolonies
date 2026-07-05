----------------------------------------------------------------------------
-- ui/modals/sections.lua -- the SECTIONS toggle modal (native Basalt widgets).
--
-- One CheckBox per section, toggled in place so state updates without a full
-- rebuild. Needs a small deps table from the layout (which owns section
-- registration + geometry), passed in to avoid a require cycle:
--   deps = { SECTION_ORDER, SECTIONS, isShown(screen,id), applyRects(screen) }
----------------------------------------------------------------------------

local theme  = require("ui.theme")
local common = require("ui.modals.common")
local C = theme.C

local M = {}

local function buildSectionsModal(screen, hooks, deps)
  local W, H = screen.W, screen.H
  local nmf = screen.nmodalFrame
  common.clearCard(screen)
  nmf.set("background", C.screen)
  nmf.set("visible", true)
  nmf.set("enabled", true)

  local SECTION_ORDER, SECTIONS = deps.SECTION_ORDER, deps.SECTIONS
  local isShown, applyRects = deps.isShown, deps.applyRects

  local mw = math.min(W - 2, 34)
  local mh = math.min(H - 2, #SECTION_ORDER + 5)
  local mx = math.floor((W - mw) / 2) + 1
  local my = math.floor((H - mh) / 2) + 1
  local card = nmf:addFrame({ x = mx, y = my, width = mw, height = mh, background = C.card })
  screen.nmodalCard = card

  card:addLabel({ x = 1, y = 1, width = mw, height = 1, autoSize = false,
    backgroundEnabled = true, background = C.cardTitle, foreground = C.titleText })
    :setText(" SECTIONS")
  card:addLabel({ x = 2, y = 3, width = mw - 2, background = C.card, foreground = C.dim })
    :setText("Tap to toggle:")

  for i, id in ipairs(SECTION_ORDER) do
    local ry = 3 + i
    if ry <= mh - 2 then
      local on = isShown(screen, id)
      local title = SECTIONS[id].title
      -- CheckBox renders its text left-aligned with a transparent background, so
      -- the row isn't a solid green block and the box lines up on the left. The
      -- CheckBox auto-toggles its own `checked`; we mirror that into `enabled`
      -- (derived from our own state, so it's correct regardless of dispatch order).
      local cb = card:addCheckBox({ x = 2, y = ry, height = 1,
        text = "[ ] " .. title, checkedText = "[x] " .. title,
        checked = on, foreground = on and C.text or C.dim })
      cb:onClick(function(self)
        local now = not isShown(screen, id)
        screen.enabled[id] = now
        self:setForeground(now and C.text or C.dim)
        applyRects(screen)
        hooks.save()
        screen.env.redraw()
      end)
    end
  end

  card:addButton({ x = mw - 7, y = mh, width = 7, height = 1,
    background = C.btnOk, foreground = C.btnText }):setText("CLOSE")
    :onClick(function() screen.modal = nil; screen.env.redraw() end)
end

function M.show(screen, hooks, deps)
  if screen.nmodalKind == "sections" and screen.nmodalFrame.get("visible") then return end
  buildSectionsModal(screen, hooks, deps)
  screen.nmodalKind = "sections"
end

return M

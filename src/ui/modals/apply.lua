----------------------------------------------------------------------------
-- ui/modals/apply.lua -- the suggestion "apply" modal (native Basalt widgets).
--
-- Title = the action + who. Skill levels render as bars (green = the hire); when
-- a worker is displaced, a red bar under each skill shows their level so the
-- upgrade is visible at a glance. The citizen location label is polled + updated
-- in place (refreshLocation) while the modal is open, so it tracks a moving
-- citizen without rescanning the whole suggestion list.
----------------------------------------------------------------------------

local theme  = require("ui.theme")
local util   = require("common.util")
local skills = require("colony.skills")
local common = require("ui.modals.common")
local C = theme.C
local locStr = util.locStr
local cap = util.capitalize

local M = {}

-- Action verb per kind; the title is "<Verb> <candidate name>".
local VERB = { assign = "Hire", replace = "Replace", reassign = "Move", recruit = "Recruit" }

local function buildApplyModal(screen, s)
  local W, H = screen.W, screen.H
  local nmf = screen.nmodalFrame
  common.clearCard(screen)
  nmf.set("background", C.screen)
  nmf.set("visible", true)
  nmf.set("enabled", true)

  local cand = s.candidate or {}
  local tgt = s.target
  local isRecruit = s.kind == "recruit"

  -- Size the card to its content so nothing is cramped or clipped.
  local nInfo = 3                                             -- Role + Job at + entity location
    + ((s.kind == "reassign" and s.from) and 1 or 0)          -- From
    + (isRecruit and 1 or 0)                                  -- Cost
    + (tgt and 1 or 0)                                        -- Replacing
  local nSkill = tgt and 4 or 2
  local mw = math.min(W - 2, 42)
  -- +1 for the blank row between the primary and secondary skill groups.
  local mh = math.min(H - 2, 3 + nInfo + 1 + nSkill + 1 + 1)
  local mx = math.floor((W - mw) / 2) + 1
  local my = math.floor((H - mh) / 2) + 1
  local card = nmf:addFrame({ x = mx, y = my, width = mw, height = mh, background = C.card })
  screen.nmodalCard = card

  -- One Label that paints its OWN full-width title strip (backgroundEnabled), so
  -- the text is guaranteed on the C.cardTitle background -- a transparent label
  -- over a separate strip frame could land on the card body with no contrast.
  card:addLabel({ x = 1, y = 1, width = mw, height = 1, autoSize = false,
    backgroundEnabled = true, background = C.cardTitle, foreground = C.titleText })
    :setText(" " .. (VERB[s.kind] or "Apply") .. " " .. (cand.name or "?"))

  local iy = 3
  local function line(label, val, fg)
    local lbl = card:addLabel({ x = 2, y = iy, background = C.card, foreground = fg or C.text })
    lbl:setText(label .. tostring(val))
    iy = iy + 1
    return lbl
  end

  line("Role: ", s.jobLabel or cap(s.job), C.text)
  if s.kind == "reassign" and s.from then line("From: ", cap(s.from), C.dim) end
  line("Job at: ", locStr(s.building.location), C.dim)
  if isRecruit then
    -- Visitor entity position isn't tracked (0,0,0); point at the Tavern instead.
    line("Recruit at: ", locStr(s.tavernLoc), C.accent2)
    line("Cost: ", s.cost and (tostring(s.cost.count) .. " x " .. s.cost.displayName) or "?", C.warn)
  else
    -- Live citizen position: polled + updated in place while the modal is open.
    screen.nmodalEntityLabel = line("Citizen at: ", locStr(cand.location), C.accent2)
    screen.nmodalEntity = { id = cand.id, prefix = "Citizen at: " }
  end
  if tgt then line("Replacing: ", tgt.name, C.bad) end

  iy = iy + 1  -- gap before the skill bars

  local barX, levW = 14, 3
  local barW = math.max(4, mw - barX - levW - 2)
  local function bar(name, y, lvl, color)
    if name ~= "" then
      card:addLabel({ x = 2, y = y, background = C.card, foreground = color }):setText(name)
    end
    local pct = math.max(0, math.min(100, math.floor((lvl / skills.MAX_SKILL) * 100 + 0.5)))
    card:addProgressBar({ x = barX, y = y, width = barW, height = 1,
      progress = pct, progressColor = color, background = C.screen, foreground = color })
    card:addLabel({ x = barX + barW + 1, y = y, background = C.card, foreground = color })
      :setText(tostring(lvl))
  end
  bar(tostring(s.pri), iy, cand.pri or 0, C.good); iy = iy + 1
  if tgt then bar("", iy, tgt.pri or 0, C.bad); iy = iy + 1 end
  iy = iy + 1  -- small spacing between the primary + secondary skill stats
  bar(tostring(s.sec), iy, cand.sec or 0, C.good); iy = iy + 1
  if tgt then bar("", iy, tgt.sec or 0, C.bad); iy = iy + 1 end

  card:addButton({ x = mw - 8, y = mh, width = 8, height = 1,
    background = C.btnOk, foreground = C.btnText }):setText("Close")
    :onClick(function() screen.modal = nil; screen.env.redraw() end)
end

-- Rebuild only when the shown suggestion changes (render runs every tick).
function M.show(screen, s)
  if screen.nmodalKind == "apply" and screen.nmodalSug == s and screen.nmodalFrame.get("visible") then return end
  buildApplyModal(screen, s)
  screen.nmodalKind = "apply"; screen.nmodalSug = s
end

-- Update the open apply-modal's citizen-location label in place from a fresh
-- id -> location map. (Recruit modals show a static Tavern, no entity.)
function M.refreshLocation(screen, citizenLoc)
  local e, lbl = screen.nmodalEntity, screen.nmodalEntityLabel
  if not (e and lbl and e.id) then return end
  local loc = citizenLoc[e.id]
  if loc then lbl:setText(e.prefix .. locStr(loc)) end
end

return M

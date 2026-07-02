----------------------------------------------------------------------------
-- ui/sections/status.lua -- colony happiness / population / threat / construction.
----------------------------------------------------------------------------

local draw  = require("ui.draw")
local theme = require("ui.theme")
local C = theme.C

local HAPPINESS_MAX = 10

local M = {}
M.title = "Colony Status"

function M.draw(x, y, w, h, screen, d)
  local cx, cy, cw = draw.card(x, y, w, h, "COLONY STATUS")
  local row = cy
  local hc = d.happiness >= 7 and C.good or (d.happiness >= 4 and C.warn or C.bad)
  draw.put(cx, row, "Happiness", C.dim, C.card); row = row + 1
  draw.hbar(cx, row, cw, d.happiness / HAPPINESS_MAX, hc, string.format(" %.1f / %d", d.happiness, HAPPINESS_MAX)); row = row + 1
  draw.put(cx, row, "Population", C.dim, C.card); row = row + 1
  draw.hbar(cx, row, cw, d.maxPop > 0 and d.pop / d.maxPop or 0, C.accent, string.format(" %d / %d", d.pop, d.maxPop)); row = row + 1
  local threat = d.attack and "UNDER ATTACK" or (d.raid and "RAID INCOMING" or "SECURE")
  draw.put(cx, row, "Threat", C.dim, C.card)
  draw.put(cx + cw - #threat, row, threat, (d.attack or d.raid) and C.bad or C.good, C.card); row = row + 1
  local sg = string.format("%d sites  %d graves", d.sites, d.graves)
  draw.put(cx, row, "Constr.", C.dim, C.card)
  draw.put(cx + cw - #sg, row, sg, d.graves > 0 and C.warn or C.text, C.card)
end

return M

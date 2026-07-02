----------------------------------------------------------------------------
-- ui/sections/status.lua -- colony happiness / population / threat / construction.
--
-- Happiness and population are shown as vertical bars; threat and construction
-- as text to the right of the bars.
----------------------------------------------------------------------------

local draw  = require("ui.draw")
local theme = require("ui.theme")
local C = theme.C

local HAPPINESS_MAX = 10

local M = {}
M.title = "Colony Status"

function M.draw(x, y, w, h, screen, d)
  local cx, cy, cw, ch = draw.card(x, y, w, h, "COLONY STATUS")
  local barH = math.max(1, ch - 1)          -- last inner row holds labels
  local bw = 3
  local gap = 2
  local hc = d.happiness >= 7 and C.good or (d.happiness >= 4 and C.warn or C.bad)

  -- Happiness bar
  draw.vbar(cx, cy, bw, barH, d.happiness / HAPPINESS_MAX, hc)
  draw.put(cx, cy + barH, "Hap", C.dim, C.card)
  draw.put(cx, cy, string.format("%.0f", d.happiness), hc, C.card)

  -- Population bar
  local px = cx + bw + gap
  draw.vbar(px, cy, bw, barH, d.maxPop > 0 and d.pop / d.maxPop or 0, C.accent)
  draw.put(px, cy + barH, "Pop", C.dim, C.card)
  draw.put(px, cy, tostring(d.pop), C.accent, C.card)

  -- Text column to the right of the bars
  local tx = px + bw + gap
  if tx <= cx + cw - 1 then
    draw.put(tx, cy, ("Happy %.1f/%d"):format(d.happiness, HAPPINESS_MAX), C.text, C.card)
    draw.put(tx, cy + 1, ("Pop %d/%d"):format(d.pop, d.maxPop), C.text, C.card)
    local threat = d.attack and "UNDER ATTACK" or (d.raid and "RAID SOON" or "Secure")
    draw.put(tx, cy + 2, threat, (d.attack or d.raid) and C.bad or C.good, C.card)
    draw.put(tx, cy + 3, ("%d sites %d graves"):format(d.sites, d.graves),
      d.graves > 0 and C.warn or C.dim, C.card)
  end
end

return M

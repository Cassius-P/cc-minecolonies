----------------------------------------------------------------------------
-- ui/sections/status.lua -- colony happiness / population / threat / construction.
--
-- Happiness and population are vertical bars; threat and construction are
-- labelled text beside the bars.
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
  local gap = 2
  local bw = 9
  local hc = d.happiness >= 7 and C.good or (d.happiness >= 4 and C.warn or C.bad)

  -- Happiness bar (value on top, full label under)
  draw.vbar(cx, cy, bw, barH, d.happiness / HAPPINESS_MAX, hc)
  draw.put(cx, cy, string.format(" %.1f", d.happiness), colors.black, hc)
  draw.put(cx, cy + barH, "Happiness", C.dim, C.card)

  -- Population bar. maxPop = housing/bed cap, so this is citizens/beds. It can be
  -- exceeded (bed removed under a resident) -> vbar clamps to full, so we signal
  -- over-capacity by colour (red) + the value reads "pop/max" (e.g. 12/10).
  local px = cx + bw + gap
  local hasCap = d.maxPop > 0
  local over = hasCap and d.pop > d.maxPop
  local full = hasCap and d.pop >= d.maxPop
  local pc = over and C.bad or (full and C.warn or C.accent)
  draw.vbar(px, cy, bw, barH, hasCap and d.pop / d.maxPop or 0, pc)
  draw.put(px, cy, hasCap and string.format(" %d/%d", d.pop, d.maxPop) or string.format(" %d", d.pop),
    colors.black, pc)
  draw.put(px, cy + barH, "Population", C.dim, C.card)

  -- Labelled non-chart info to the right of the bars
  local tx = px + bw + gap
  if tx <= cx + cw - 1 then
    local threat = d.attack and "UNDER ATTACK" or (d.raid and "RAID SOON" or "Secure")
    draw.put(tx, cy, "Threat:", C.dim, C.card)
    draw.put(tx, cy + 1, threat, (d.attack or d.raid) and C.bad or C.good, C.card)
    -- Beds: free housing, or homeless count in red when citizens exceed beds.
    if hasCap then
      local free = d.maxPop - d.pop
      draw.put(tx, cy + 2, "Beds:", C.dim, C.card)
      if free < 0 then
        draw.put(tx + 6, cy + 2, ("%d homeless"):format(-free), C.bad, C.card)
      else
        draw.put(tx + 6, cy + 2, tostring(free), free == 0 and C.warn or C.good, C.card)
      end
    end
    draw.put(tx, cy + 3, "Sites:", C.dim, C.card)
    draw.put(tx + 7, cy + 3, tostring(d.sites), C.text, C.card)
    draw.put(tx, cy + 4, "Graves:", C.dim, C.card)
    draw.put(tx + 7, cy + 4, tostring(d.graves), d.graves > 0 and C.warn or C.text, C.card)
  end
end

return M

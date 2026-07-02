----------------------------------------------------------------------------
-- ui/sections/workers.lua -- full job roster.
--
-- Every job building with its assigned workers (tagged ok / -> replace w/ X)
-- and its open slots (+ assign X / + empty). [DO] opens the manual-hire card.
----------------------------------------------------------------------------

local draw  = require("ui.draw")
local theme = require("ui.theme")
local util  = require("common.util")
local C = theme.C

local M = {}
M.title = "Workers"

function M.draw(x, y, w, h, screen, d)
  local list = d.roster or {}
  local cx, cy, cw, ch = draw.card(x, y, w, h, string.format("WORKERS (%d to act)", #d.suggestions))
  screen.scroll = draw.scrollArrows("workers", x, y, w, #list, ch, screen.scroll)
  if #list == 0 then draw.put(cx, cy, "No job buildings found.", C.dim, C.card); return end
  local off = screen.scroll.workers or 0
  for i = 1, ch do
    local r = list[i + off]
    if not r then break end
    local ry = cy + i - 1
    if r.kind == "head" then
      draw.put(cx, ry, string.format("%s (%d/%d)", util.capitalize(r.building), r.filled, r.max), C.accent2, C.card)
    elseif r.kind == "worker" then
      if r.status == "replace" then
        draw.button(cx, ry, "DO", C.btn, C.btnText, function() screen.modal = { kind = "apply", sug = r.sug } end)
        draw.put(cx + 5, ry, string.format("%s \26 replace w/ %s", r.name, r.repl), C.warn, C.card)
      else
        draw.put(cx + 3, ry, r.name .. "  ok", C.good, C.card)
      end
    else -- slot
      if r.status == "assign" then
        draw.button(cx, ry, "DO", C.btn, C.btnText, function() screen.modal = { kind = "apply", sug = r.sug } end)
        draw.put(cx + 5, ry, "+ assign " .. r.cand, C.good, C.card)
      else
        draw.put(cx + 3, ry, "+ (empty)", C.dim, C.card)
      end
    end
  end
end

return M

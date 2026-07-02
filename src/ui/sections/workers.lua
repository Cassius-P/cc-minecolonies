----------------------------------------------------------------------------
-- ui/sections/workers.lua -- actionable suggestions pinned on top, then the
-- full job roster in a two-column grid.
--
-- Top block: the assign/replace suggestions with [DO] (pinned, not sorted into
-- the roster). A blank gap separates them from the roster grid below, which
-- lists every job building + its workers (tagged ok / -> replace) and open
-- slots, laid out across two columns and scrollable.
----------------------------------------------------------------------------

local draw  = require("ui.draw")
local theme = require("ui.theme")
local util  = require("common.util")
local C = theme.C
local cap = util.capitalize

local M = {}
M.title = "Workers"

local function trunc(s, n) return #s > n and s:sub(1, n) or s end

local function drawRosterRow(rx, ry, colW, r)
  if r.kind == "gap" then
    return  -- blank spacer row between jobs
  elseif r.kind == "head" then
    draw.put(rx, ry, trunc(string.format("%s (%d/%d)", r.label or cap(r.building), r.filled, r.max), colW), C.accent2, C.card)
  elseif r.kind == "worker" then
    if r.status == "reassign" then
      draw.put(rx, ry, trunc(" " .. r.name .. " \26 " .. tostring(r.to), colW), C.note, C.card)
    elseif r.status == "replace" then
      draw.put(rx, ry, trunc(" " .. r.name .. " \26 " .. r.repl, colW), C.warn, C.card)
    else
      draw.put(rx, ry, trunc(" " .. r.name .. " ok", colW), C.good, C.card)
    end
  else -- slot
    if r.status == "assign" then
      draw.put(rx, ry, trunc(" + " .. r.cand, colW), C.good, C.card)
    else
      draw.put(rx, ry, trunc(" + (empty)", colW), C.dim, C.card)
    end
  end
end

function M.draw(x, y, w, h, screen, d)
  local sugs = d.suggestions or {}
  local roster = d.roster or {}
  local cx, cy, cw, ch = draw.card(x, y, w, h, string.format("WORKERS (%d to act)", #sugs))
  local bottom = cy + ch - 1
  local row = cy

  -- Pinned suggestions (actionable), capped to at most half the card height.
  if #sugs == 0 then
    draw.put(cx, row, "All jobs optimally staffed.", C.good, C.card); row = row + 1
  else
    local maxSug = math.max(1, math.min(#sugs, math.floor(ch / 2)))
    for i = 1, maxSug do
      if row > bottom then break end
      local s = sugs[i]
      local txt, col
      local toLabel = s.jobLabel or cap(s.job)
      if s.kind == "assign" then
        txt = ("assign %s \26 %s"):format(s.candidate.name, toLabel); col = C.good
      elseif s.kind == "reassign" then
        txt = ("%s: %s \26 %s"):format(s.candidate.name, cap(s.from), toLabel); col = C.note
      else
        txt = ("%s \26 %s (rep %s)"):format(s.candidate.name, toLabel, s.target.name); col = C.warn
      end
      -- Highlight + make the WHOLE row the clickable action.
      draw.fillRect(cx, row, cw, 1, C.cardTitle)
      draw.put(cx + 1, row, "\16 " .. trunc(txt, cw - 3), col, C.cardTitle)
      draw.addButton(cx, row, cx + cw - 1, row, function() screen.modal = { kind = "apply", sug = s } end)
      row = row + 1
    end
    if #sugs > maxSug and row <= bottom then
      draw.put(cx, row, ("+%d more"):format(#sugs - maxSug), C.dim, C.card); row = row + 1
    end
  end

  -- Gap between suggestions and the roster grid.
  row = row + 1

  -- Roster grid: two columns, scrollable.
  local gridTop = row
  local gridH = bottom - gridTop + 1
  if gridH < 1 then return end
  local colW = math.floor((cw - 1) / 2)
  local capacity = gridH * 2
  screen.scroll = draw.scrollArrows("workers", x, y, w, #roster, capacity, screen.scroll)
  local off = screen.scroll.workers or 0
  for i = 1, capacity do
    local r = roster[i + off]
    if not r then break end
    local left = (i - 1) < gridH
    local rx = left and cx or (cx + colW + 1)
    local ry = gridTop + ((i - 1) % gridH)
    drawRosterRow(rx, ry, colW, r)
  end
end

return M

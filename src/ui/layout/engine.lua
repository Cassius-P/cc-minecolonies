----------------------------------------------------------------------------
-- ui/layout/engine.lua -- PURE two-column geometry (no Basalt, no draw).
--
-- Owns the section id list + which are hidden-by-default, and the math that
-- turns a screen's {W, H, columns, weights, enabled} into per-section rects.
-- Fully unit-testable: computeRects takes a plain screen-shaped table and
-- returns { id = {x,y,w,h} }. layout.lua binds these to Basalt frames.
----------------------------------------------------------------------------

local M = {}

M.SECTION_ORDER = { "status", "workforce", "workers", "orders", "requests", "legend", "jobskills", "research" }
-- Sections hidden unless explicitly enabled (enabled[id] == true).
M.DEFAULT_HIDDEN = { jobskills = true, research = true }

-- A monitor holds up to this many independent layout slots (columns/enabled/
-- weights/cfgIdx), switchable from the footer. Slot 1 is populated from config;
-- the rest start empty.
M.MAX_LAYOUTS = 5

local VALID = {}
for _, id in ipairs(M.SECTION_ORDER) do VALID[id] = true end

-- enabled map with every section hidden (an "empty" layout).
function M.emptyEnabled()
  local e = {}
  for _, id in ipairs(M.SECTION_ORDER) do e[id] = false end
  return e
end

-- A fresh empty layout slot.
function M.blankLayout()
  return { columns = { {}, {} }, enabled = M.emptyEnabled(), weights = {}, cfgIdx = 1 }
end

-- Point a screen's live layout fields at its active slot, so all existing
-- render / edit / persistence code keeps reading screen.columns/enabled/etc.
function M.activate(screen)
  local L = screen.layouts and screen.layouts[screen.activeLayout or 1]
  if not L then return end
  screen.columns, screen.enabled, screen.weights, screen.cfgIdx =
    L.columns, L.enabled, L.weights, L.cfgIdx
end

local COLGAP = 1         -- blank column between the two columns
local DEFAULT_WEIGHT = 6 -- baseline height share, so a section can shrink below default

function M.isShown(screen, id)
  if M.DEFAULT_HIDDEN[id] then return screen.enabled[id] == true end
  return screen.enabled[id] ~= false
end

function M.weightOf(screen, id)
  local w = screen.weights and screen.weights[id]
  return (type(w) == "number" and w > 0) and w or DEFAULT_WEIGHT
end

-- Ensure screen.columns is two clean lists holding every section exactly once.
-- Tolerates a missing/old config (e.g. preserved config.lua from a prior
-- version that used the flexbox layout instead of columns).
function M.normalizeColumns(screen)
  local cols = type(screen.columns) == "table" and screen.columns or {}
  cols[1] = type(cols[1]) == "table" and cols[1] or {}
  cols[2] = type(cols[2]) == "table" and cols[2] or {}
  local seen = {}
  for ci = 1, 2 do
    local clean = {}
    for _, id in ipairs(cols[ci]) do
      if VALID[id] and not seen[id] then seen[id] = true; clean[#clean + 1] = id end
    end
    cols[ci] = clean
  end
  for _, id in ipairs(M.SECTION_ORDER) do
    if not seen[id] then table.insert(cols[1], id); seen[id] = true end
  end
  screen.columns = cols
end

-- Enabled sections in a column, in order.
local function enabledIn(screen, ci)
  local out = {}
  for _, id in ipairs(screen.columns[ci] or {}) do
    if M.isShown(screen, id) then out[#out + 1] = id end
  end
  return out
end

-- rects[id] = {x,y,w,h} for every visible section. Column width is shared by
-- the active columns (minus a gap); row height within a column is shared by
-- each section's weight (so resizing one grows/shrinks its siblings).
function M.computeRects(screen)
  local active = {}
  for ci = 1, 2 do
    local ids = enabledIn(screen, ci)
    if #ids > 0 then active[#active + 1] = ids end
  end
  local rects = {}
  local nCols = #active
  if nCols == 0 then return rects end
  local availW = screen.W - COLGAP * (nCols - 1)
  local availH = screen.H - 1                         -- last row is the footer
  local baseW = math.floor(availW / nCols)
  local xcursor = 1
  for i, ids in ipairs(active) do
    local w = (i == nCols) and (screen.W - xcursor + 1) or baseW
    local x = xcursor
    local sum = 0
    for _, id in ipairs(ids) do sum = sum + M.weightOf(screen, id) end
    local ycursor, used = 1, 0
    for j, id in ipairs(ids) do
      local wt = M.weightOf(screen, id)
      local h = (j == #ids) and (availH - used) or math.max(1, math.floor(availH * wt / sum))
      rects[id] = { x = x, y = ycursor, w = w, h = h }
      ycursor = ycursor + h
      used = used + h
    end
    xcursor = xcursor + w + COLGAP
  end
  return rects
end

return M

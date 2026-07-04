----------------------------------------------------------------------------
-- ui/sections/orders.lua -- queued work orders, grouped by type.
--
-- Orders are grouped under a coloured type header (Build / Upgrade / Repair /
-- Remove). Each order row: a claim dot (green claimed / orange waiting), the
-- target building name, and the target level on the right.
----------------------------------------------------------------------------

local draw  = require("ui.draw")
local theme = require("ui.theme")
local util  = require("common.util")
local C = theme.C
local cap = util.capitalize

local M = {}
M.title = "Work Orders"

local GROUP_ORDER = { "Build", "Upgrade", "Repair", "Remove" }

local function verb(t)
  t = tostring(t or ""):lower()
  if t:find("upgrade") then return "Upgrade", C.accent
  elseif t:find("repair") then return "Repair", C.warn
  elseif t:find("remov") or t:find("deconstruct") then return "Remove", C.bad
  elseif t:find("build") or t:find("create") then return "Build", C.good
  else return "Other", C.accent2 end
end

local function trunc(s, n) return #s > n and s:sub(1, math.max(0, n)) or s end
-- Note: the colony_integrator exposes NO build-progress field (work orders and
-- buildings only give claimed/built booleans), so a % cannot be shown. The
-- claim dot (green claimed / orange waiting) is the available progress signal.

-- Full building name (NOT jobKey, which would keep only the last word, turning
-- "Town Hall" -> "Hall" and "Courier's Hut" -> "Hut"). Drop a namespace prefix,
-- normalise separators, capitalise each word.
local function cleanName(s)
  s = tostring(s or "?")
  s = s:match("([^:]+)$") or s      -- strip "namespace:" prefix if present
  s = s:gsub("[_/]", " "):gsub("%s+", " ")
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  local dup = s:match("^(.+) %1$")   -- collapse "Courier's Hut Courier's Hut"
  if dup then s = dup end
  s = s:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end)
  return s
end

function M.draw(x, y, w, h, screen, d)
  local list = d.orders or {}
  local claimed = 0
  for _, o in ipairs(list) do if o.isClaimed then claimed = claimed + 1 end end

  local cx, cy, cw, ch = draw.card(x, y, w, h, string.format("WORK ORDERS (%d)", #list))
  if #list > 0 then
    local badge = ("%d/%d claimed"):format(claimed, #list)
    draw.put(x + w - #badge - 8, y, badge, claimed == #list and C.good or C.dim, C.cardTitle)
  end
  if #list == 0 then draw.put(cx, cy, "None queued.", C.dim, C.card); return end

  -- Group by type.
  local groups, gcol = {}, {}
  for _, o in ipairs(list) do
    local v, col = verb(o.workOrderType or o.type)
    groups[v] = groups[v] or {}; gcol[v] = col
    table.insert(groups[v], o)
  end
  local verbs, seen = {}, {}
  for _, v in ipairs(GROUP_ORDER) do if groups[v] then verbs[#verbs + 1] = v; seen[v] = true end end
  for v in pairs(groups) do if not seen[v] then verbs[#verbs + 1] = v end end

  -- Flatten to display rows (header + orders + gaps between groups).
  local rows = {}
  for gi, v in ipairs(verbs) do
    if gi > 1 then rows[#rows + 1] = { kind = "gap" } end
    rows[#rows + 1] = { kind = "head", verb = v, col = gcol[v], n = #groups[v] }
    for _, o in ipairs(groups[v]) do rows[#rows + 1] = { kind = "order", o = o } end
  end

  screen.scroll = draw.scrollArrows("orders", x, y, w, #rows, ch, screen.scroll)
  local off = screen.scroll.orders or 0
  for i = 1, ch do
    local r = rows[i + off]
    if not r then break end
    local ry = cy + i - 1
    if r.kind == "gap" then
      -- blank
    elseif r.kind == "head" then
      draw.put(cx, ry, trunc(("%s (%d)"):format(r.verb, r.n), cw), r.col, C.card)
    else
      local o = r.o
      local name = cleanName(o.buildingName or o.structureName or o.name or "?")
      local lvl = o.targetLevel and ("L" .. tostring(o.targetLevel)) or ""
      local loc = o.location
      local coords = (type(loc) == "table") and util.locStr(loc) or ""
      draw.put(cx + 1, ry, "\7", o.isClaimed and C.good or C.warn, C.card)

      local nameX = cx + 3
      local rightEdge = cx + cw
      local lvlX = (lvl ~= "") and (rightEdge - #lvl) or rightEdge
      local leftLimit = lvlX - 1
      -- name, then the assigned builder's name in a distinct colour (falls back
      -- to coordinates when no builder is assigned yet).
      local nameShown = trunc(name, math.max(0, leftLimit - nameX))
      draw.put(nameX, ry, nameShown, C.text, C.card)
      local sx = nameX + #nameShown + 1
      local builder = o.builderName
      if builder and builder ~= "" and sx <= leftLimit then
        draw.put(sx, ry, trunc(builder, leftLimit - sx + 1), C.note, C.card)
      elseif coords ~= "" and sx + #coords - 1 <= leftLimit then
        draw.put(sx, ry, coords, C.dim, C.card)
      end
      if lvl ~= "" then draw.put(lvlX, ry, lvl, C.dim, C.card) end
    end
  end
end

return M

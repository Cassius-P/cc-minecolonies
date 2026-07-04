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

-- Work progress percent, best-effort (the API field name isn't documented).
-- Accepts a 0-100 number, a 0-1 fraction, or a {current,total} table.
local function pct(o)
  local p = o.progress or o.workProgress or o.percentage or o.buildingProgress or o.completion
  if type(p) == "table" then
    local cur, tot = p.current or p[1], p.total or p[2]
    if type(cur) == "number" and type(tot) == "number" and tot > 0 then
      return math.max(0, math.min(100, math.floor(cur / tot * 100 + 0.5)))
    end
    return nil
  end
  if type(p) == "number" then
    if p >= 0 and p <= 1 then p = p * 100 end
    return math.max(0, math.min(100, math.floor(p + 0.5)))
  end
  return nil
end

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
      local loc = o.location or o.pos or o.buildingLocation or o.workOrderLocation
      local coords = (type(loc) == "table") and util.locStr(loc) or ""
      local p = pct(o)
      local prog = p and (p .. "%") or ""
      draw.put(cx + 1, ry, "\7", o.isClaimed and C.good or C.warn, C.card)

      local nameX = cx + 3
      local rightEdge = cx + cw
      -- right cluster: progress then level
      local lvlX  = (lvl ~= "") and (rightEdge - #lvl) or rightEdge
      local progX = (prog ~= "") and (lvlX - 1 - #prog) or lvlX
      local leftLimit = progX - 1
      -- name, then coordinates right after it in a discrete colour
      local nameShown = trunc(name, math.max(0, leftLimit - nameX))
      draw.put(nameX, ry, nameShown, C.text, C.card)
      local coordsX = nameX + #nameShown + 1
      if coords ~= "" and coordsX + #coords - 1 <= leftLimit then
        draw.put(coordsX, ry, coords, C.dim, C.card)  -- discrete colour, next to name
      end
      if prog ~= "" then
        draw.put(progX, ry, prog, (p >= 100 and C.good) or C.accent, C.card)
      end
      if lvl ~= "" then draw.put(lvlX, ry, lvl, C.dim, C.card) end
    end
  end
end

return M

----------------------------------------------------------------------------
-- colony/research.lua -- PURE normalize + vertical-tree layout for the Research
-- section. No peripheral/http: given the raw getResearch() table it is fully
-- deterministic and unit-testable.
--
-- getResearch() returns { branchName -> { <primary node>, ... } } where a node is
--   { id, name, status="NOT_STARTED"|"IN_PROGRESS"|"FINISHED", progress,
--     requiredTime, researchEffects={...}, cost={...}, requirements={...},
--     children={ <node>, ... } }   (children present only when non-empty)
--
-- normalize() flattens status into a display status `dstatus`:
--   finished / active / available (unlockable now) / locked. `available` is the
--   highlight: NOT_STARTED with every requirement fulfilled AND parent finished.
----------------------------------------------------------------------------

local M = {}

-- "minecolonies:combat" -> "Combat"; "higherlearning" -> "Higherlearning".
local function cleanLabel(s)
  s = tostring(s or "?")
  s = s:match("([^:]+)$") or s
  s = s:gsub("[_/]", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  s = s:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end)
  return s
end

local function reqsMet(node)
  for _, r in ipairs(node.requirements or {}) do
    if not r.fulfilled then return false end
  end
  return true
end

-- Recursively normalize a node. `available` = startable now: not started, its
-- parent research finished (the structural prerequisite -- MineColonies does NOT
-- list the parent among `requirements`), AND every listed requirement fulfilled.
local function normNode(n, parentFinished)
  local status = tostring(n.status or "NOT_STARTED")
  local dstatus
  if status == "FINISHED" then
    dstatus = "finished"
  elseif status == "IN_PROGRESS" then
    dstatus = "active"
  elseif parentFinished and reqsMet(n) then
    dstatus = "available"
  else
    dstatus = "locked"
  end

  local requiredTime = tonumber(n.requiredTime) or 0
  local progress = tonumber(n.progress) or 0
  local pct
  if dstatus == "finished" then pct = 1
  elseif requiredTime > 0 then pct = math.max(0, math.min(1, progress / requiredTime))
  else pct = 0 end

  local node = {
    id = n.id, name = n.name or n.id or "?",
    status = status, dstatus = dstatus,
    progress = progress, requiredTime = requiredTime, pct = pct,
    effects = n.researchEffects or {},
    cost = n.cost or {},
    requirements = n.requirements or {},
    children = {},
  }
  local finished = dstatus == "finished"
  for _, c in ipairs(n.children or {}) do
    node.children[#node.children + 1] = normNode(c, finished)
  end
  return node
end

-- raw = getResearch() output. Returns an ordered branch list (stable by key):
--   { { key=<branchName>, label=<clean>, roots={ <node>, ... } }, ... }
function M.normalize(raw)
  local branches = {}
  if type(raw) ~= "table" then return branches end
  local keys = {}
  for k in pairs(raw) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    local roots = {}
    for _, n in ipairs(raw[k] or {}) do
      roots[#roots + 1] = normNode(n, true)   -- a branch's primary research has no parent
    end
    -- Skip branches with no visible research (e.g. MineColonies' "unlockable"
    -- branch, whose entries are hidden -> the integrator returns an empty list).
    if #roots > 0 then
      branches[#branches + 1] = { key = k, label = cleanLabel(k), roots = roots }
    end
  end

  -- Synthetic first tab: a flat list of every startable ("available") research
  -- across all branches, rendered as a detail grid rather than a tree.
  local avail = {}
  local function gather(node)
    if node.dstatus == "available" then avail[#avail + 1] = node end
    for _, c in ipairs(node.children) do gather(c) end
  end
  for _, b in ipairs(branches) do for _, r in ipairs(b.roots) do gather(r) end end
  if #avail > 0 then
    table.insert(branches, 1, { key = "_unlockable", label = "Unlockable", grid = true, nodes = avail, roots = {} })
  end

  return branches
end

-- Vertical tidy tree: depth = row band (top -> down), siblings packed left-first
-- with each parent centred over the span of its children so siblings never
-- overlap. `tile = { w, h, gapX, gapY }`. Returns:
--   { nodes = { { node, x, y, w, h, depth, parentX, parentY }, ... },
--     canvasW, canvasH }   (x,y are 1-based canvas coords)
function M.layout(branch, tile)
  local w, h = tile.w, tile.h
  local sx, sy = w + tile.gapX, h + tile.gapY
  local pos, order = {}, {}
  local nextSlot, maxDepth = 0, 0

  local function assignX(node, depth)
    if depth > maxDepth then maxDepth = depth end
    local x
    if #node.children == 0 then
      x = nextSlot * sx + 1
      nextSlot = nextSlot + 1
    else
      local first, last
      for i, c in ipairs(node.children) do
        local cx = assignX(c, depth + 1)
        if i == 1 then first = cx end
        last = cx
      end
      x = math.floor((first + last) / 2 + 0.5)
    end
    pos[node] = { x = x, y = depth * sy + 1, depth = depth }
    return x
  end

  for _, r in ipairs(branch and branch.roots or {}) do assignX(r, 0) end

  local nodes = {}
  local function collect(node, parent)
    local p, pp = pos[node], parent and pos[parent]
    nodes[#nodes + 1] = {
      node = node, x = p.x, y = p.y, w = w, h = h, depth = p.depth,
      parentX = pp and pp.x, parentY = pp and pp.y,
    }
    for _, c in ipairs(node.children) do collect(c, node) end
  end
  for _, r in ipairs(branch and branch.roots or {}) do collect(r, nil) end

  return {
    nodes = nodes,
    canvasW = nextSlot > 0 and (nextSlot * sx - tile.gapX) or 0,
    canvasH = #nodes > 0 and ((maxDepth + 1) * sy - tile.gapY) or 0,
  }
end

M._cleanLabel = cleanLabel

return M

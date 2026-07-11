local t = require("helper")
local research = require("colony.research")

local raw = {
  ["minecolonies:combat"] = {
    { id = "c:root", name = "Combat Academy", status = "FINISHED",
      progress = 1, requiredTime = 1, requirements = {},
      children = {
        { id = "c:squire", name = "Squire Training", status = "IN_PROGRESS",
          progress = 45, requiredTime = 100, requirements = {} },
        { id = "c:avail", name = "Avant-Garde", status = "NOT_STARTED",
          requirements = { { fulfilled = true, desc = "ok" } } },
        { id = "c:locked", name = "Knight", status = "NOT_STARTED",
          requirements = { { fulfilled = false, desc = "Build Barracks L3" } } },
      } },
  },
  ["minecolonies:civilian"] = {
    { id = "v:root", name = "Keep", status = "NOT_STARTED", requirements = {} },
  },
}

local branches = research.normalize(raw)

t.case("normalize: synthetic Unlockable grid tab first")
t.eq(#branches, 3, "unlockable + civilian + combat")
t.truthy(branches[1].grid, "first tab is the grid")
t.eq(branches[1].label, "Unlockable (2)", "grid tab label with count")
t.eq(#branches[1].nodes, 2, "two available nodes gathered (v:root + c:avail)")
t.eq(branches[1].nodes[1].cat, "Civilian", "available node tagged with its branch category")

t.case("normalize: ordered, cleaned branches")
t.eq(branches[2].label, "Civilian", "sorted: civilian < combat")
t.eq(branches[3].label, "Combat", "second real branch")

t.case("normalize: tree intact")
local combat = branches[3].roots[1]
t.eq(#combat.children, 3, "combat root children")

t.case("normalize: dstatus derivation")
t.eq(combat.dstatus, "finished", "finished root")
t.eq(combat.children[1].dstatus, "active", "in-progress -> active")
t.eq(combat.children[2].dstatus, "available", "not-started + reqs met + parent finished -> available")
t.eq(combat.children[3].dstatus, "locked", "not-started + unmet req -> locked")
t.eq(branches[2].roots[1].dstatus, "available", "root with empty reqs -> available")

t.case("normalize: progress pct")
t.near(combat.children[1].pct, 0.45, 1e-6, "45/100")
t.eq(combat.pct, 1, "finished pct = 1")

t.case("layout: vertical tidy tree")
local lay = research.layout(branches[3], { w = 8, h = 1, gapX = 1, gapY = 1 })
-- one entry per node (root + 3 children)
t.eq(#lay.nodes, 4, "node count")

local byId = {}
for _, e in ipairs(lay.nodes) do byId[e.node.id] = e end

-- root at top (smaller y than its children)
t.truthy(byId["c:root"].y < byId["c:squire"].y, "root above children")

-- leaves packed at distinct slots (no overlap within tier), sx = w+gapX = 9
t.eq(byId["c:squire"].x, 1, "leaf 1 x")
t.eq(byId["c:avail"].x, 10, "leaf 2 x")
t.eq(byId["c:locked"].x, 19, "leaf 3 x")

-- parent centred over span of children: mid(1,19) = 10
t.eq(byId["c:root"].x, 10, "parent x = midpoint of children")

-- children carry parent coords for connectors
t.eq(byId["c:squire"].parentX, 10, "child.parentX = root.x")
t.eq(byId["c:squire"].parentY, byId["c:root"].y, "child.parentY = root.y")

t.case("layout: canvas dims")
t.eq(lay.canvasW, 26, "3 slots * 9 - gap")
t.eq(lay.canvasH, 3, "2 tiers * 2 - gap")

t.case("normalize: empty/nil safe")
t.eq(#research.normalize(nil), 0, "nil -> empty")
t.eq(#research.normalize({}), 0, "empty -> empty")

t.case("normalize: drop empty branches; synthetic Unlockable when available exists")
local dropped = research.normalize({
  ["minecolonies:unlockable"] = {},
  ["minecolonies:combat"] = { { id = "c", name = "C", status = "NOT_STARTED", requirements = {} } },
})
t.eq(#dropped, 2, "empty branch dropped, grid tab added")
t.truthy(dropped[1].grid, "grid tab first")
t.eq(dropped[2].label, "Combat", "real empty 'unlockable' branch dropped")

t.case("normalize: no synthetic tab when nothing available")
local none = research.normalize({
  ["minecolonies:combat"] = { { id = "c", name = "C", status = "FINISHED", requirements = {} } },
})
t.eq(#none, 1, "only the real branch")
t.eq(none[1].label, "Combat", "no grid tab without available research")

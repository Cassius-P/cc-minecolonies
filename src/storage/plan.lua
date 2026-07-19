----------------------------------------------------------------------------
-- storage/plan.lua -- PURE auto-fulfill decisions (no bridge, no colours-as-
-- ints, no I/O). storage/fulfill.lua is the effectful executor that drives the
-- ME/RS bridge and applies the tokens these functions return.
--
--   equipNames(item, af)          -> in-range equipment item ids (tier range)
--   skipSet(list) / shouldSkip    -> skip-list membership
--   selectCandidates(cands)       -> first stocked filter, first craftable filter
--   exportToken(provided, count)  -> "filled"|"partial", done(bool)
--   craftResultToken(ok)          -> "crafting"|"partial"
--   withCount(filter, count)      -> filter clone carrying a count
----------------------------------------------------------------------------

local M = {}

-- Equipment material tiers (low -> high) + level rank for range filtering.
local ARMOR_PART = { Helmet = "helmet", Chestplate = "chestplate", Leggings = "leggings", Boots = "boots" }
local TOOL_PART  = { Sword = "sword", Pickaxe = "pickaxe", Axe = "axe", Shovel = "shovel", Hoe = "hoe" }
local SPECIAL    = { Bow = "minecraft:bow", Shears = "minecraft:shears", Shield = "minecraft:shield" }
local ARMOR_MATS = { "leather", "golden", "chainmail", "iron", "diamond", "netherite" }
local TOOL_MATS  = { "wooden", "golden", "stone", "iron", "diamond", "netherite" }
local RANK = { Wood = 1, Leather = 1, Gold = 2, Chain = 2, Stone = 3, Iron = 4, Diamond = 5, Netherite = 6 }
local MAT_RANK = { leather = 1, wooden = 1, golden = 2, chainmail = 2, stone = 3, iron = 4, diamond = 5, netherite = 6 }
local CAP_RANK = { ["Iron"] = 4, ["Diamond"] = 5, ["Iron and Diamond"] = 5 }

-- In-range candidate item ids (names) for an equipment request.
function M.equipNames(item, af)
  local piece = item.equipPiece
  if not piece then return { item.item_name } end
  if SPECIAL[piece] then return { SPECIAL[piece] } end
  local part = ARMOR_PART[piece]
  local mats = part and ARMOR_MATS
  if not part then part = TOOL_PART[piece]; mats = part and TOOL_MATS end
  if not part then return { item.item_name } end
  local lo = (item.minLevel and RANK[item.minLevel]) or 1
  local hi = math.min((item.maxLevel and RANK[item.maxLevel]) or 99, CAP_RANK[af.equipmentLevel] or 99)
  local out = {}
  for _, m in ipairs(mats) do
    local r = MAT_RANK[m] or 99
    if r >= lo and r <= hi then out[#out + 1] = "minecraft:" .. m .. "_" .. part end
  end
  if #out == 0 then out[1] = item.item_name end
  return out
end

-- Order an equipment request's accepted items ({name, fingerprint}) vanilla-first
-- (minecraft:*), then the rest, keeping each group's order and dropping name dups.
-- Lets fulfill prefer a vanilla item over a modded one while still falling back.
function M.orderAccept(items)
  local van, rest, seen = {}, {}, {}
  for _, it in ipairs(items or {}) do
    local n = it and it.name
    if type(n) == "string" and not seen[n] then
      seen[n] = true
      if n:find("^minecraft:") then van[#van + 1] = it else rest[#rest + 1] = it end
    end
  end
  for _, it in ipairs(rest) do van[#van + 1] = it end
  return van
end

-- Count how many of `names` already sit in a warehouse `.list()` result (slot ->
-- {name, count}). Equipment we exported but the colony hasn't collected yet
-- lives here; without this, fulfill re-crafts every scan during delivery lag.
-- pristineOnly skips stacks carrying NBT (enchantments/damage/components): an
-- enchanted "Blessed Iron Leggings" must NOT satisfy a request for a plain one,
-- or fulfill marks it filled forever while the colony keeps waiting.
function M.warehouseHave(list, names, pristineOnly)
  if not list or not names then return 0 end
  local want = {}
  for _, n in ipairs(names) do want[n] = true end
  local total = 0
  for _, s in pairs(list) do
    if s and want[s.name] and not (pristineOnly and s.nbt) then total = total + (s.count or 0) end
  end
  return total
end

-- skipItems list -> lookup set; shouldSkip tests membership by item_name.
function M.skipSet(list)
  local skip = {}
  for _, n in ipairs(list or {}) do skip[n] = true end
  return skip
end

function M.shouldSkip(item, skip) return skip[item.item_name] == true end

-- From resolved candidates ({amount, craftable, filter}), pick the first
-- in-stock filter and the first craftable filter.
function M.selectCandidates(cands)
  local stocked, craftFilter
  for _, c in ipairs(cands) do
    if c.amount > 0 and not stocked then stocked = c.filter end
    if c.craftable and not craftFilter then craftFilter = c.filter end
  end
  return stocked, craftFilter
end

-- Colour token after an export attempt provided `provided` of `count`. `done`
-- means fully satisfied (stop processing this item).
function M.exportToken(provided, count)
  if provided >= count then return "filled", true end
  return "partial", false
end

-- Colour token after a craft request: queued -> crafting, else stuck/partial.
function M.craftResultToken(ok) return ok and "crafting" or "partial" end

-- Filter clone carrying a count (bridge export/craft filters need it).
function M.withCount(filter, count)
  local f = { count = count }
  for k, v in pairs(filter) do f[k] = v end
  return f
end

return M

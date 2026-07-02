----------------------------------------------------------------------------
-- colony/requests.lua -- split colony open-requests into equipment / builder /
-- other, parsing equipment level from the request description.
----------------------------------------------------------------------------

local util = require("common.util")
local trimLead = util.trimLead

local M = {}

local EQUIPMENT_KEYWORDS = {
  "Sword", "Bow", "Pickaxe", "Axe", "Shovel", "Hoe", "Shears",
  "Helmet", "Chestplate", "Leggings", "Boots", "Shield",
}

function M.isEquipment(desc)
  for _, k in ipairs(EQUIPMENT_KEYWORDS) do
    if string.find(desc, k) then return true end
  end
  return false
end

-- The equipment type word (Boots, Sword, ...) mentioned in the text.
local function baseItem(s)
  for _, k in ipairs(EQUIPMENT_KEYWORDS) do if string.find(s, k) then return k end end
  return nil
end

-- Parse "minimal level: X" / "maximal level: X" (X may be e.g. "Wood or Gold").
local function levelWord(s, which)
  local v = s:match(which .. " level:%s*(%a[%a ]-)%s+and with")
    or s:match(which .. " level:%s*(%a[%a ]-)%.?%s*$")
    or s:match(which .. " level:%s*(%a+)")
  if v then v = v:gsub("%s+$", "") end
  return v
end

-- "minecraft:spruce_log" -> "Spruce Log"
local function prettyMat(id)
  id = tostring(id):gsub("^.*[:/]", ""):gsub("_", " ")
  return (id:gsub("(%w+)", function(w) return w:sub(1, 1):upper() .. w:sub(2) end))
end

-- Domum Ornamentum blocks carry two texture materials in item components. The
-- recipe wording varies by block (frame/center, pillar/base, ...), so use
-- generic PRIMARY / SECONDARY. Returns (baseName, materialsString) -- the
-- materials string is nil when none are present. Non-domum -> nil.
local function domumInfo(it)
  if type(it.name) ~= "string" or not it.name:find("^domum_ornamentum:") then return nil end
  local td = it.components and it.components["domum_ornamentum:texture_data"]
  local base = (it.displayName or it.name):gsub("^%[", ""):gsub("%]$", "")
  if type(td) ~= "table" then return base, nil end
  -- Known slot order (primary then secondary), then any other slots. Blocks may
  -- have just one material -- that is fine, we simply list what is present.
  local SLOT_ORDER = { "minecraft:block/oak_planks", "minecraft:block/dark_oak_planks" }
  local mats, seen = {}, {}
  for _, k in ipairs(SLOT_ORDER) do
    if td[k] then mats[#mats + 1] = prettyMat(td[k]); seen[k] = true end
  end
  for k, v in pairs(td) do
    if not seen[k] then mats[#mats + 1] = prettyMat(v) end
  end
  if #mats == 0 then return base, nil end
  return base, table.concat(mats, " + ")
end

-- "Leather -> Chain", "up to Chain", "Leather+", or "Any".
local function rangeText(minL, maxL)
  if minL and maxL then
    if minL == maxL then return maxL end
    return minL .. " -> " .. maxL
  elseif maxL then return "up to " .. maxL
  elseif minL then return minL .. "+"
  else return "Any" end
end

-- categorize(rawRequests, log) -> equipment, builder, others
function M.categorize(rawRequests, log)
  local equipment, builder, others = {}, {}, {}
  for _, req in ipairs(rawRequests or {}) do
    if req.items and req.items[1] then
      local isEq = M.isEquipment(req.desc or "")
      local base = {
        name = req.name, target = req.target or "", count = req.count,
        item_displayName = trimLead(req.items[1].displayName),
        item_name = req.items[1].name, desc = req.desc or "",
        fingerprint = req.items[1].fingerprint,  -- AP item id: exact match for any item
        provided = 0, isCraftable = false, equipment = isEq,
        displayColor = colors.white, level = "",
      }
      if isEq then
        local bi = baseItem(base.desc) or baseItem(req.name) or req.name
        local minL = levelWord(base.desc, "minimal")
        local maxL = levelWord(base.desc, "maximal")
        local level = maxL or "Any Level"
        base.name = (maxL and (maxL .. " ") or "") .. req.name  -- keep for crafting
        base.level = level
        base.minLevel = minL
        base.maxLevel = maxL
        base.equipPiece = bi
        base.displayLabel = bi .. " (" .. rangeText(minL, maxL) .. ")"
        equipment[#equipment + 1] = base
      else
        local dbase, dmats = domumInfo(req.items[1])  -- nil for non-domum
        base.displayLabel = dbase
        base.materials = dmats
        if string.find(base.target, "Builder") then
          builder[#builder + 1] = base
        else
          others[#others + 1] = base
        end
      end
    elseif log then
      log.write("Skipping request with no items: " .. (req.name or "unknown"))
    end
  end
  return equipment, builder, others
end

return M

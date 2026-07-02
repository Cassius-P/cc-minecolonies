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
      elseif string.find(base.target, "Builder") then
        builder[#builder + 1] = base
      else
        others[#others + 1] = base
      end
    elseif log then
      log.write("Skipping request with no items: " .. (req.name or "unknown"))
    end
  end
  return equipment, builder, others
end

return M

----------------------------------------------------------------------------
-- colony/requests.lua -- split colony open-requests into equipment / builder /
-- other, parsing equipment level from the request description.
----------------------------------------------------------------------------

local util = require("common.util")
local trimLead = util.trimLead

local M = {}

local EQUIPMENT_KEYWORDS = {
  "Sword ", "Bow ", "Pickaxe ", "Axe ", "Shovel ", "Hoe ", "Shears ",
  "Helmet ", "Chestplate ", "Leggings ", "Boots ", "Shield",
}

function M.isEquipment(desc)
  for _, k in ipairs(EQUIPMENT_KEYWORDS) do
    if string.find(desc, k) then return true end
  end
  return false
end

local LEVEL_TABLE = {
  ["and with maximal level: Leather"] = "Leather",
  ["and with maximal level: Stone"]   = "Stone",
  ["and with maximal level: Chain"]   = "Chain",
  ["and with maximal level: Gold"]    = "Gold",
  ["and with maximal level: Iron"]    = "Iron",
  ["and with maximal level: Diamond"] = "Diamond",
  ["with maximal level: Wood or Gold"] = "Wood or Gold",
}

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
        local level = "Any Level"
        for pat, mapped in pairs(LEVEL_TABLE) do
          if string.find(base.desc, pat) then level = mapped; break end
        end
        base.name = level .. " " .. req.name
        base.level = level
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

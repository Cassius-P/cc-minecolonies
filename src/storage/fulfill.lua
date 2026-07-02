----------------------------------------------------------------------------
-- storage/fulfill.lua -- CCxM auto-fulfill core.
--
-- Exports colony requests from an ME/RS bridge to the warehouse inventory and
-- queues crafts for what is missing. Peripherals are passed in (found by
-- network name), so this works with the bridge/inventory anywhere on a
-- wired-modem network. Sets item.displayColor for the UI legend.
----------------------------------------------------------------------------

local util = require("common.util")
local lastWord = util.lastWord

local M = {}

local quantityField = nil  -- "amount" (ME) or "count" (RS), detected once

-- Map an equipment request to a concrete craftable item id, honouring the
-- configured equipmentLevel. Returns (itemName, craftAllowed).
local function equipmentCraft(name, level, item_name, want)
  if item_name == "minecraft:bow" then return item_name, true end
  if (level == "Iron" or level == "Iron and Diamond" or level == "Any Level")
      and (want == "Iron" or want == "Iron and Diamond") then
    if level == "Any Level" then level = "Iron" end
    return string.lower("minecraft:" .. level .. "_" .. lastWord(name)), true
  elseif (level == "Diamond" or level == "Iron and Diamond" or level == "Any Level") and want == "Diamond" then
    if level == "Any Level" then level = "Diamond" end
    return string.lower("minecraft:" .. level .. "_" .. lastWord(name)), true
  end
  return item_name, false
end

local function detectQuantityField(bridge, itemName)
  local ok, data = pcall(function() return bridge.getItem({ name = itemName }) end)
  if ok and data then
    if type(data.amount) == "number" then return "amount" end
    if type(data.count) == "number" then return "count" end
  end
  return nil
end

-- handle(list, ctx): ctx = { bridge, storage, config, log }
function M.handle(list, ctx)
  local bridge, storage = ctx.bridge, ctx.storage
  local af = ctx.config.autofulfill
  local log = ctx.log
  local skip = {}
  for _, n in ipairs(af.skipItems or {}) do skip[n] = true end

  for _, item in ipairs(list) do
    local stored, crafting, eqOk = 0, false, true
    if skip[item.item_name] then
      item.displayColor = colors.gray
      goto continue
    end
    if item.equipment then
      item.item_name, eqOk = equipmentCraft(item.name, item.level, item.item_name, af.equipmentLevel)
    end
    if not quantityField then quantityField = detectQuantityField(bridge, item.item_name) end

    local gotItem = pcall(function()
      local d = bridge.getItem({ name = item.item_name })
      stored = d[quantityField] or 0
      item.isCraftable = d.isCraftable
    end)
    if not gotItem then
      log.write(item.item_displayName .. " not in system or craftable.")
      item.displayColor = colors.red
      if string.sub(item.item_name, 1, 17) == "domum_ornamentum:" then item.displayColor = colors.lightBlue end
      goto continue
    end

    if stored ~= 0 then
      local exported = pcall(function()
        item.provided = bridge.exportItemToPeripheral({ name = item.item_name, count = item.count }, storage)
      end) or pcall(function()
        item.provided = bridge.exportItem({ name = item.item_name, count = item.count }, storage)
      end)
      if not exported then item.displayColor = colors.yellow end
      if item.provided == item.count then
        item.displayColor = colors.green
        if string.sub(item.item_name, 1, 17) == "domum_ornamentum:" then item.displayColor = colors.lightBlue end
      else
        item.displayColor = colors.yellow
      end
    end

    if not af.equipment and item.equipment then goto continue end
    if not af.craftMissing then goto continue end

    if (item.provided < item.count) and item.isCraftable and eqOk then
      log.safeCall(function() crafting = bridge.isItemCrafting({ name = item.item_name }) end)
      if crafting then item.displayColor = colors.blue; goto continue end
    end

    if not crafting and item.isCraftable and (item.provided < item.count) then
      local ok = log.safeCall(function()
        return bridge.craftItem({ name = item.item_name, count = item.count - item.provided })
      end)
      if not ok then
        item.displayColor = colors.yellow
        goto continue
      end
      item.displayColor = colors.blue
    end

    ::continue::
  end
end

return M

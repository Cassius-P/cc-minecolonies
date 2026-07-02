----------------------------------------------------------------------------
-- common/peripherals.lua -- discovery over the (wired-modem) peripheral network.
--
-- peripheral.find / getNames / getType / hasType transparently traverse a
-- wired-modem network, so remote peripherals resolve by their network name
-- with no side assumptions. CONFIG.peripherals lets a user pin a specific
-- remote by network name when several exist.
----------------------------------------------------------------------------

local M = {}

local function overrides(config)
  return (config and config.peripherals) or {}
end

-- Wrap a network name if it currently exists, else nil.
local function wrapIfPresent(name)
  if type(name) ~= "string" then return nil end
  local ok = pcall(peripheral.getType, name)
  if ok and peripheral.getType(name) then return peripheral.wrap(name) end
  return nil
end

function M.findColony(config)
  return wrapIfPresent(overrides(config).colony) or peripheral.find("colony_integrator")
end

function M.findBridge(config)
  return wrapIfPresent(overrides(config).bridge)
      or peripheral.find("meBridge") or peripheral.find("me_bridge")
      or peripheral.find("rsBridge") or peripheral.find("rs_bridge")
end

-- Storage = export target. Returns a network NAME string (bridge exports by name).
function M.findStorage(config)
  local pin = overrides(config).storage
  if type(pin) == "string" and peripheral.hasType and peripheral.hasType(pin, "inventory") then
    return pin
  end
  for _, side in pairs(peripheral.getNames()) do
    if peripheral.hasType(side, "inventory") then return side end
  end
  return nil
end

-- Returns an ordered list of monitor network names.
function M.listMonitors(config)
  local pin = overrides(config).monitors
  local out = {}
  if type(pin) == "table" then
    for _, n in ipairs(pin) do
      if peripheral.getType(n) == "monitor" then out[#out + 1] = n end
    end
    if #out > 0 then return out end
  end
  for _, n in ipairs(peripheral.getNames()) do
    if peripheral.getType(n) == "monitor" then out[#out + 1] = n end
  end
  return out
end

-- Diagnostics for the terminal: every peripheral and its primary type.
function M.diagnostics()
  local out = {}
  for _, n in ipairs(peripheral.getNames()) do
    out[#out + 1] = { name = n, type = peripheral.getType(n) or "?" }
  end
  return out
end

return M

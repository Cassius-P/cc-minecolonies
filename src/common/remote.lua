----------------------------------------------------------------------------
-- common/remote.lua -- rednet protocol shared by the host broadcast service
-- and the pocket client. Pure helpers (snapshot/serializable) are unit-tested;
-- openModem touches CC globals and is in-game-only.
----------------------------------------------------------------------------

local M = {
  PROTOCOL = "mc_dash",
  HELLO    = "HELLO",
  SNAPSHOT = "SNAPSHOT",
}

function M.snapshot(data, name, id)
  return { kind = M.SNAPSHOT, data = data, name = name, id = id }
end

-- True when v has no functions/threads/userdata anywhere (safe to send/persist).
function M.serializable(v)
  local ty = type(v)
  if ty == "table" then
    for k, val in pairs(v) do
      if not M.serializable(k) or not M.serializable(val) then return false end
    end
    return true
  end
  return ty == "number" or ty == "string" or ty == "boolean" or ty == "nil"
end

-- Open rednet on the first wireless (ender) modem found. Returns false when none.
function M.openModem()
  local name = nil
  peripheral.find("modem", function(n, m)
    if not name and m.isWireless and m.isWireless() then name = n end
  end)
  if not name then return false end
  if not rednet.isOpen(name) then rednet.open(name) end
  return true
end

return M

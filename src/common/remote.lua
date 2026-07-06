----------------------------------------------------------------------------
-- common/remote.lua -- modem-channel protocol shared by the host service and
-- the pocket client (cc-mek-scada style: one shared channel = the pairing key).
-- Pure helpers are unit-tested; openModem touches CC globals (in-game only).
----------------------------------------------------------------------------

local M = {
  PROTO      = "mc_dash",
  HELLO      = "HELLO",
  SNAPSHOT   = "SNAPSHOT",
  MIN_CH     = 10000,
  MAX_CH     = 65535,
  DEFAULT_CH = 10000,
}

function M.validChannel(n)
  return type(n) == "number" and n == math.floor(n) and n >= M.MIN_CH and n <= M.MAX_CH
end

function M.channelOr(n)
  if M.validChannel(n) then return n end
  return M.DEFAULT_CH
end

function M.snapshot(data, name, id)
  return { proto = M.PROTO, kind = M.SNAPSHOT, data = data, name = name, id = id }
end

function M.hello()
  return { proto = M.PROTO, kind = M.HELLO }
end

function M.isOurs(msg)
  return type(msg) == "table" and msg.proto == M.PROTO
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

-- First wireless (ender) modem peripheral, or nil. Does NOT open a channel.
function M.openModem()
  return (peripheral.find("modem", function(_, m)
    return m.isWireless and m.isWireless()
  end))
end

return M

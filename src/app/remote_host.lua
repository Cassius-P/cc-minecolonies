----------------------------------------------------------------------------
-- app/remote_host.lua -- serves the latest colony snapshot to pocket clients.
-- broadcast() pushes on each scan; serve() answers a pocket's HELLO with the
-- current snapshot (boot / reconnect). Caller only starts this when a modem
-- opened (common/remote.openModem()).
----------------------------------------------------------------------------

local remote = require("common.remote")

local M = {}

function M.new(getSnapshot)
  local function broadcast()
    local snap = getSnapshot()
    if snap then rednet.broadcast(snap, remote.PROTOCOL) end
  end

  local function serve(basalt)
    basalt.schedule(function()
      while true do
        local sender, msg = rednet.receive(remote.PROTOCOL)
        if type(msg) == "table" and msg.kind == remote.HELLO then
          local snap = getSnapshot()
          if snap then rednet.send(sender, snap, remote.PROTOCOL) end
        end
      end
    end)
  end

  return { broadcast = broadcast, serve = serve }
end

return M

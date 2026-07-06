----------------------------------------------------------------------------
-- app/remote_client.lua -- pocket side: request + receive colony snapshots.
-- serve() runs two coroutines: one blocks on rednet.receive and feeds valid
-- snapshots to onData; one ticks staleness (and re-HELLOs) once a second.
----------------------------------------------------------------------------

local remote = require("common.remote")

local M = {}

function M.new(cfg, state, onData, onStale)
  local lastSeen = 0
  local ever = false

  local function hello()
    if cfg.hostId then rednet.send(cfg.hostId, { kind = remote.HELLO }, remote.PROTOCOL) end
  end

  local function serve(basalt)
    basalt.schedule(function()
      while true do
        local sender, msg = rednet.receive(remote.PROTOCOL)
        if sender == cfg.hostId and type(msg) == "table" and msg.kind == remote.SNAPSHOT then
          lastSeen = os.epoch("utc"); ever = true
          onData(msg)
        end
      end
    end)
    basalt.schedule(function()
      while true do
        local age = os.epoch("utc") - lastSeen
        local stale = (not ever) or age > (cfg.staleSeconds or 15) * 1000
        onStale(stale, ever)
        if stale then hello() end
        sleep(1)
      end
    end)
  end

  return { hello = hello, serve = serve }
end

return M

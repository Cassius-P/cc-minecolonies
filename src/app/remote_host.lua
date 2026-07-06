----------------------------------------------------------------------------
-- app/remote_host.lua -- serves colony snapshots to pocket clients over a
-- shared modem channel. broadcast() pushes on each scan; serve() answers a
-- pocket HELLO with the current snapshot. setChannel() moves channel live
-- (admin edit). Caller starts this only when a modem is present.
----------------------------------------------------------------------------

local remote = require("common.remote")

local M = {}

function M.new(modem, channel, getSnapshot)
  local function send(snap)
    if snap and remote.serializable(snap) then modem.transmit(channel, channel, snap) end
  end

  local function broadcast() send(getSnapshot()) end

  local function open() modem.open(channel) end

  local function serve(basalt)
    basalt.schedule(function()
      while true do
        local _, _, ch, _, msg = os.pullEvent("modem_message")
        if ch == channel and remote.isOurs(msg) and msg.kind == remote.HELLO then
          send(getSnapshot())
        end
      end
    end)
  end

  local function setChannel(ch)
    if ch == channel then return end
    modem.close(channel); channel = ch; modem.open(channel)
  end

  return { open = open, broadcast = broadcast, serve = serve, setChannel = setChannel }
end

return M

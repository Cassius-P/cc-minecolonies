----------------------------------------------------------------------------
-- app/remote_client.lua -- pocket side: receive colony snapshots on a shared
-- modem channel + re-HELLO while stale. serve() runs two coroutines; the first
-- consumes modem_message, the second ticks staleness. setChannel() re-pairs.
----------------------------------------------------------------------------

local remote = require("common.remote")

local M = {}

function M.new(modem, channel, staleSeconds, onData, onStale)
  local lastSeen = 0
  local ever = false
  staleSeconds = staleSeconds or 15

  local function open() modem.open(channel) end
  local function hello() modem.transmit(channel, channel, remote.hello()) end

  local function setChannel(ch)
    if ch ~= channel then modem.close(channel); channel = ch; modem.open(channel) end
    lastSeen = 0; ever = false; hello()
  end

  local function serve(basalt)
    basalt.schedule(function()
      while true do
        local _, _, ch, _, msg = os.pullEvent("modem_message")
        if ch == channel and remote.isOurs(msg) and msg.kind == remote.SNAPSHOT then
          lastSeen = os.epoch("utc"); ever = true
          onData(msg)
        end
      end
    end)
    basalt.schedule(function()
      while true do
        local stale = (not ever) or (os.epoch("utc") - lastSeen) > staleSeconds * 1000
        onStale(stale, ever)
        if stale then hello() end
        sleep(1)
      end
    end)
  end

  return { open = open, hello = hello, serve = serve, setChannel = setChannel }
end

return M

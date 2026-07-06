----------------------------------------------------------------------------
-- ui/pocket.lua -- the pocket-computer "remote monitor". Receives colony data
-- over a shared modem channel and renders it with the monitor layout/section
-- stack. Its layout + theme + channel are local to the pocket (own settings
-- file), independent of the host monitors.
----------------------------------------------------------------------------

local basalt   = require("basalt")
local remote   = require("common.remote")
local settings = require("common.settings")
local store    = require("app.store")
local client   = require("app.remote_client")
local theme    = require("ui.theme")
local layout   = require("ui.layout")
local loaderUI = require("ui.loader")

local M = {}

function M.start(cfgModule)
  local config = cfgModule.config
  local modem = remote.openModem()
  if not modem then
    term.clear(); term.setCursorPos(1, 1)
    term.setTextColor(colors.red)
    print("No wireless/ender modem. Attach one and reboot.")
    return
  end

  local state = store.new(config)

  -- Single screen bound to the pocket terminal.
  local W, H = term.getSize()
  local frame = basalt.getMainFrame()
  local cfg1 = config.screens and config.screens[1] or { columns = { {}, {} }, enabled = {} }
  local screen = {
    mon = term.current(), name = "pocket:" .. os.getComputerID(), frame = frame,
    W = W, H = H, scroll = {}, modal = nil, edit = false,
    columns = { {}, {} }, enabled = {}, weights = {}, cfgIdx = 1,
  }
  for ci = 1, 2 do for _, id in ipairs(cfg1.columns[ci] or {}) do
    screen.columns[ci][#screen.columns[ci] + 1] = id
  end end
  if type(cfg1.enabled) == "table" then
    for k, v in pairs(cfg1.enabled) do screen.enabled[k] = v and true or false end
  end
  local screens = { screen }

  local hooks = {}
  local function redrawAll() layout.render(screen, state.data, state, hooks) end
  hooks.save       = function() settings.save(config, screens) end
  hooks.cycleTheme = function()
    local n = theme.cycle(config)
    theme.apply(n, screens, config); state.setTheme(n)
    settings.save(config, screens)
  end

  -- Per-pocket persisted layout + theme + channel (local file).
  settings.load(config, screens, theme.isTheme)
  state.setTheme(config.theme)

  local env = {
    state = state, hooks = hooks, redraw = redrawAll, reassign = function() end,
    stop = function() state.setQuit(); basalt.stop() end,
  }
  layout.buildScreen(screen, env)
  theme.apply(config.theme, screens, config)

  local loader = loaderUI.build({ frame })
  loader.show("Waiting for host")

  local rc   -- forward declaration; used by the prompt's OK handler

  -- Channel prompt overlay: prefilled input, validates a 5-digit channel.
  local prompt = frame:addFrame({ x = 1, y = 1, width = W, height = H, background = colors.black })
  prompt.set("z", 1000); prompt.set("visible", false)   -- above the loader overlay (z 900)
  local py = math.max(1, math.floor(H / 2) - 2)
  prompt:addLabel({ x = 2, y = py, width = W - 2, foreground = colors.white })
    :setText("Host link channel (10000-65535):")
  local input = prompt:addInput({ x = 2, y = py + 1, width = 7, height = 1,
    background = colors.gray, foreground = colors.white })
  local warn = prompt:addLabel({ x = 2, y = py + 3, width = W - 2, foreground = colors.red })
  local function showPrompt()
    input:setText(tostring(remote.channelOr(config.channel)))
    warn:setText(""); prompt.set("visible", true)
  end
  prompt:addButton({ x = 2, y = py + 2, width = 4, height = 1 })
    :setText(" OK "):setBackground(colors.green):setForeground(colors.black)
    :onClick(function()
      local n = tonumber(input.get("text"))
      if not remote.validChannel(n) then warn:setText("Need 10000-65535"); return end
      config.channel = n
      settings.save(config, screens)
      if rc then rc.setChannel(n) end
      prompt.set("visible", false)
    end)

  -- Keys: q quit, r manual refresh, h edit channel. Others are footer buttons.
  basalt.onEvent("char", function(ch)
    local f = basalt.getFocus and basalt.getFocus()
    if f and f.get and (f.get("type") == "Input" or f.get("type") == "TextBox") then return end
    if ch == "q" then basalt.stop()
    elseif ch == "r" and rc then rc.hello()
    elseif ch == "h" then showPrompt() end
  end)

  rc = client.new(modem, remote.channelOr(config.channel), (config.pocket or {}).staleSeconds,
    function(snap)                              -- onData
      state.setData(snap.data, "")
      loader.hide(); redrawAll()
    end,
    function(stale, ever)                       -- onStale
      if stale then loader.show(ever and "Host offline" or "Waiting for host") else loader.hide() end
    end)
  rc.open(); rc.serve(basalt)
  if not remote.validChannel(config.channel) then showPrompt() end

  -- Animate the loader dots while disconnected.
  basalt.schedule(function() while true do loader.tick(); sleep(0.3) end end)

  basalt.run()
  theme.restore(screens)
end

return M

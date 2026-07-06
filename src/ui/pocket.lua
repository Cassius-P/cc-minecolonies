----------------------------------------------------------------------------
-- ui/pocket.lua -- the pocket-computer "remote monitor". Renders colony data
-- received over rednet from the host, reusing the monitor layout/section
-- stack. Its layout + theme are local to the pocket (own settings file), so
-- the pocket theme is independent of the host monitors.
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

function M.start(config)
  if not remote.openModem() then
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

  -- Per-pocket persisted layout + theme (local file). Reuses the monitor store.
  settings.load(config, screens, theme.isTheme)
  state.setTheme(config.theme)

  local env = {
    state = state, hooks = hooks, redraw = redrawAll, reassign = function() end,
    stop = function() state.setQuit(); basalt.stop() end,
  }
  layout.buildScreen(screen, env)
  theme.apply(config.theme, screens, config)

  loader = loaderUI.build({ frame })
  loader.show("Waiting for host")

  -- Keys: q quit, r manual refresh (re-HELLO). Everything else is footer buttons.
  local rc
  basalt.onEvent("char", function(ch)
    local f = basalt.getFocus and basalt.getFocus()
    if f and f.get and (f.get("type") == "Input" or f.get("type") == "TextBox") then return end
    if ch == "q" then basalt.stop()
    elseif ch == "r" and rc then rc.hello() end
  end)

  rc = client.new(config.pocket or {}, state,
    function(snap)                              -- onData
      state.setData(snap.data, "")
      loader.hide()
      redrawAll()
    end,
    function(stale, ever)                       -- onStale
      if stale then loader.show(ever and "Host offline" or "Waiting for host") else loader.hide() end
    end)
  rc.serve(basalt)

  -- Animate the loader dots while disconnected.
  basalt.schedule(function() while true do loader.tick(); sleep(0.3) end end)

  basalt.run()
  theme.restore(screens)
end

return M

----------------------------------------------------------------------------
-- ui/app.lua -- Basalt application: one frame per monitor (+ the computer
-- terminal), wired to the colony scan loop.
--
-- Basalt owns the event loop (basalt.run), monitor->frame binding (a frame's
-- `term` property bound to a monitor peripheral; Basalt converts monitor_touch
-- to a click on the matching frame) and scheduling. Each frame carries a
-- full-size Display whose window is the draw surface for ui/draw primitives.
----------------------------------------------------------------------------

local basalt   = require("basalt")
local util     = require("common.util")
local log      = require("common.log")
local perif    = require("common.peripherals")
local settings = require("common.settings")
local updater  = require("common.updater")
local theme    = require("ui.theme")
local layout   = require("ui.layout")
local terminal = require("ui.terminal")
local loaderUI = require("ui.loader")
local api      = require("colony.api")

local M = {}

local deepCopy = util.deepCopy

function M.start(cfgModule)
  local config = cfgModule.config
  local VERSION = cfgModule.VERSION
  config.VERSION = VERSION                       -- fallback for the update check
  local installedVersion = updater.installed(VERSION)  -- from /version stamp
  log.init(config)

  -- Required: colony integrator (adjacent or over a wired modem).
  local colony = perif.findColony(config)
  if not colony then error("No colony_integrator found (adjacent or via wired modem)", 0) end
  if not colony.isInColony() then error("Integrator is not inside a colony", 0) end

  local monNames = perif.listMonitors(config)
  if #monNames == 0 then error("No monitor found (adjacent or via wired modem)", 0) end

  ----------------------------------------------------------------------------
  -- State
  ----------------------------------------------------------------------------
  local state = { data = nil, msg = "", countdown = config.refreshSeconds,
    quit = false, needScan = false, theme = config.theme, update = nil }
  local screens, screenByName = {}, {}
  local loading, loader = true, nil   -- Basalt loading overlay (set up below)

  ----------------------------------------------------------------------------
  -- Build one Basalt frame + Display per monitor
  ----------------------------------------------------------------------------
  local reserved = {}
  for _, sc in ipairs(config.screens) do
    if sc.monitor and peripheral.getType(sc.monitor) == "monitor" then reserved[sc.monitor] = true end
  end
  local pool = {}
  for _, n in ipairs(monNames) do if not reserved[n] then pool[#pool + 1] = n end end
  local pi = 1

  local function mkScreen(name, cfg, cfgIdx)
    if screenByName[name] then return end
    local mon = peripheral.wrap(name)
    mon.setTextScale(0.5)
    local frame = basalt.createFrame()
    frame.set("term", mon)
    local W, H = mon.getSize()

    local s = { mon = mon, name = name, frame = frame,
      W = W, H = H, scroll = {}, modal = nil, edit = false,
      columns = deepCopy(cfg.columns), enabled = {}, weights = {}, cfgIdx = cfgIdx }
    if type(cfg.enabled) == "table" then
      for k, v in pairs(cfg.enabled) do s.enabled[k] = v and true or false end
    end
    screens[#screens + 1] = s
    screenByName[name] = s
    return s
  end

  ----------------------------------------------------------------------------
  -- Scan + render
  ----------------------------------------------------------------------------
  local hooks = {}

  local function rescan()
    local ok, res = pcall(api.gather, { colony = colony, config = config, log = log })
    if ok then
      state.data = res
      state.msg = string.format("%d workers  %d req", #res.suggestions, #res.requests)
    else
      state.msg = "Scan error: " .. tostring(res)
    end
    state.needScan = false
    state.countdown = config.refreshSeconds
  end

  local function checkUpdate()
    local ok, res = pcall(updater.check, config)
    if ok and type(res) == "table" then
      state.update = res; state.checkFailed = false
    else
      state.checkFailed = true
    end
  end

  local termUI
  local function redrawAll()
    for _, s in ipairs(screens) do layout.render(s, state.data, state, hooks) end
    if termUI then termUI.update(state, screens) end
  end

  local function reassignScreen(i)
    local s = screens[i]; if not s then return end
    s.cfgIdx = ((s.cfgIdx or 1) % #config.screens) + 1
    local cfg = config.screens[s.cfgIdx]
    s.columns = deepCopy(cfg.columns)
    s.enabled = {}
    if type(cfg.enabled) == "table" then for k, v in pairs(cfg.enabled) do s.enabled[k] = v and true or false end end
    s.weights = {}
    s.scroll = {}; s.modal = nil
    layout.applyRects(s)
    settings.save(config, screens)
  end

  hooks.save        = function() settings.save(config, screens) end
  hooks.cycleTheme  = function()
    local n = theme.cycle(config)
    theme.apply(n, screens, config); state.theme = n
    settings.save(config, screens)
  end

  ----------------------------------------------------------------------------
  -- Wire monitor screens + terminal frame
  ----------------------------------------------------------------------------
  for idx, cfg in ipairs(config.screens) do
    local name = cfg.monitor
    if not (name and peripheral.getType(name) == "monitor") then name = pool[pi]; pi = pi + 1 end
    if name then mkScreen(name, cfg, idx) end
  end
  local lastIdx = #config.screens
  while pi <= #pool do
    local name = pool[pi]; pi = pi + 1
    mkScreen(name, config.screens[lastIdx], lastIdx)
  end

  -- Computer terminal: native Basalt tabbed UI on the main frame.
  local mainFrame = basalt.getMainFrame()
  termUI = terminal.build(mainFrame, {
    version = installedVersion, config = config,
    onUpdateButton = function()
      if state.update and state.update.available then
        -- Install: run the updater behind the loader, then reboot.
        if loading then return end
        loading = true
        if loader then loader.show("Updating from GitHub...") end
        basalt.schedule(function()
          sleep(0.3)
          shell.run("/update.lua", "force")  -- already confirmed newer; just install
          os.reboot()
        end)
      else
        -- Check: manual version check with visible feedback.
        basalt.schedule(function()
          state.checking = true; redrawAll()
          checkUpdate()
          state.checking = false; redrawAll()
        end)
      end
    end,
  })

  ----------------------------------------------------------------------------
  -- Settings, then build the Basalt section frames, then theme + first scan
  ----------------------------------------------------------------------------
  settings.load(config, screens, theme.isTheme)
  state.theme = config.theme

  local env = {
    state = state, hooks = hooks, redraw = redrawAll, reassign = reassignScreen,
    stop = function() state.quit = true; basalt.stop() end,
  }
  for _, s in ipairs(screens) do layout.buildScreen(s, env) end

  theme.apply(config.theme, screens, config)

  -- Basalt loading overlay on the computer + every monitor until the first scan.
  local frames = { mainFrame }
  for _, s in ipairs(screens) do frames[#frames + 1] = s.frame end
  loader = loaderUI.build(frames)
  loader.show("Loading colony data")

  ----------------------------------------------------------------------------
  -- Global keys + periodic refresh
  ----------------------------------------------------------------------------
  basalt.onEvent("char", function(ch)
    if ch == "q" then
      basalt.stop()
    elseif ch == "r" then
      rescan(); redrawAll()
    elseif ch == "t" then
      hooks.cycleTheme(); redrawAll()
    elseif type(ch) == "string" and ch:match("%d") then
      reassignScreen(tonumber(ch)); redrawAll()
    end
  end)

  -- Animate the loading overlay until the first scan completes.
  basalt.schedule(function()
    while loading do loader.tick(); sleep(0.3) end
  end)

  -- First scan, then reveal the UI and check for updates in the background.
  basalt.schedule(function()
    rescan()
    loading = false
    loader.hide()
    redrawAll()
    checkUpdate(); redrawAll()
  end)

  -- Periodic refresh (countdown).
  basalt.schedule(function()
    while true do
      sleep(1)
      state.countdown = state.countdown - 1
      local anyModal = false
      for _, s in ipairs(screens) do if s.modal then anyModal = true; break end end
      if state.countdown <= 0 and not anyModal and not loading then rescan() end
      redrawAll()
    end
  end)

  -- Hourly update check.
  basalt.schedule(function()
    while true do sleep(3600); checkUpdate(); redrawAll() end
  end)

  basalt.run()

  -- Teardown: restore palettes + clear.
  theme.restore(screens)
  for _, s in ipairs(screens) do
    s.mon.setBackgroundColor(colors.black); s.mon.clear(); s.mon.setCursorPos(1, 1)
  end
  term.setBackgroundColor(colors.black); term.setTextColor(colors.white)
  term.clear(); term.setCursorPos(1, 1)
  print("colony_dashboard stopped.")
end

return M

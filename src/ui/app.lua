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
local store    = require("app.store")
local dumpService = require("app.dump_service")
local keys     = require("app.keys")
local teardown = require("app.teardown")
local colonyPort = require("common.ports.colony")
local remote     = require("common.remote")
local remoteHost = require("app.remote_host")

local M = {}

local deepCopy = util.deepCopy

function M.start(cfgModule)
  local config = cfgModule.config
  -- Single version source: the /version stamp written by install.lua from
  -- manifest.version. "?" until a stamped install exists.
  local installedVersion = updater.installed()
  log.init(config)

  -- Required: colony integrator (adjacent or over a wired modem).
  local colony = perif.findColony(config)
  if not colony then error("No colony_integrator found (adjacent or via wired modem)", 0) end
  if not colony.isInColony() then error("Integrator is not inside a colony", 0) end
  local colPort = colonyPort.new(colony)   -- guarded reads for the modal poll + dump

  local monNames = perif.listMonitors(config)
  if #monNames == 0 then error("No monitor found (adjacent or via wired modem)", 0) end

  ----------------------------------------------------------------------------
  -- State
  ----------------------------------------------------------------------------
  local state = store.new(config)   -- explicit state container (app/store.lua)
  local screens, screenByName = {}, {}
  local loading, loader = true, nil   -- Basalt loading overlay (set up below)

  -- Remote pocket monitors: opt-in, only when a wireless/ender modem is present.
  local modem = remote.openModem()
  local rhost = modem and remoteHost.new(modem, remote.channelOr(config.channel), function()
    if not state.data then return nil end
    return remote.snapshot(state.data, state.data.name, state.data.id)
  end) or nil
  if rhost then rhost.open() end

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
      state.setData(res, string.format("%d workers  %d req", #res.suggestions, #res.requests))
    else
      state.setScanError("Scan error: " .. tostring(res))
    end
    if rhost then rhost.broadcast() end
  end

  local function checkUpdate()
    local ok, res = pcall(updater.check, config)
    if ok and type(res) == "table" then
      state.setUpdate(res)
    else
      state.setUpdateFailed()
    end
  end

  local termUI
  local function redrawAll()
    for _, s in ipairs(screens) do layout.render(s, state.data, state, hooks) end
    if termUI then termUI.update(state, screens) end
  end

  -- Update actions (used by both the keyboard shortcuts and the tab button).
  local function doCheck()
    basalt.schedule(function()
      state.setChecking(true); redrawAll()
      checkUpdate()
      state.setChecking(false); redrawAll()
    end)
  end
  -- Hand off to the updater cleanly: stop our Basalt app, then run /update.lua
  -- (which draws its OWN Basalt UI) AFTER basalt.run() returns -- never nested,
  -- so the progress bar no longer flickers against our still-live UI.
  local function doInstall()
    if loading or state.pendingInstall then return end
    state.beginInstall()
    basalt.stop()
  end

  local function setMargin(key, value)
    local n = tonumber(value)
    if not n then return end   -- ignore partial/empty input
    config.suggestions = config.suggestions or { replaceMargin = 1, reassignMargin = 1 }
    config.suggestions[key] = math.max(0, math.min(20, math.floor(n)))
    settings.save(config, screens)
    state.markScan()      -- apply on the next tick, NOT per keystroke (was laggy)
  end

  local function setChannel(v)
    local n = tonumber(v)
    if not remote.validChannel(n) then return end   -- ignore partial/invalid input
    config.channel = n
    settings.save(config, screens)
    if rhost then rhost.setChannel(n) end
  end

  local function setPolling(v)
    local n = tonumber(v)
    if not n then return end   -- ignore partial/empty input
    config.refreshSeconds = math.max(1, math.min(60, math.floor(n)))
    settings.save(config, screens)
    state.markScan()      -- apply on the next tick
  end

  -- Dump selected colony data to paste.rs (JSON) and show the link. The payload
  -- build + upload lives in app/dump_service; here we only manage UI state.
  local function onDump(sel)
    if state.dumping then return end
    state.beginDump(); redrawAll()
    basalt.schedule(function()
      local ok, link = pcall(dumpService.run, colPort.raw(), sel or {})
      if ok and link and link ~= "" then
        state.finishDump(link, nil)
        -- CC has no OS clipboard (sandboxed); save the link to a file instead.
        pcall(function() local f = fs.open("/dump_link.txt", "w"); f.write(link); f.close() end)
      else
        state.finishDump(nil, tostring(link))
      end
      redrawAll()
    end)
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
    theme.apply(n, screens, config); state.setTheme(n)
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

  ----------------------------------------------------------------------------
  -- Settings, then build the Basalt section frames, then theme + first scan
  ----------------------------------------------------------------------------
  settings.load(config, screens, theme.isTheme)
  state.setTheme(config.theme)
  -- settings.load may have restored a saved channel; move the host service onto
  -- it and let the admin field (built below) read the loaded value.
  if rhost then rhost.setChannel(remote.channelOr(config.channel)) end

  -- Computer terminal: native Basalt tabbed UI on the main frame.
  local mainFrame = basalt.getMainFrame()
  termUI = terminal.build(mainFrame, {
    version = installedVersion, config = config,
    onUpdateButton = function()
      if state.update and state.update.available then doInstall() else doCheck() end
    end,
    onMargin = setMargin,
    onChannel = setChannel,
    onPolling = setPolling,
    onDump = onDump,
  })

  local env = {
    state = state, hooks = hooks, redraw = redrawAll, reassign = reassignScreen,
    stop = function() state.setQuit(); basalt.stop() end,
  }
  for _, s in ipairs(screens) do layout.buildScreen(s, env) end

  theme.apply(config.theme, screens, config)

  -- Basalt loading overlay on the computer + every monitor until the first scan.
  local frames = { mainFrame }
  for _, s in ipairs(screens) do frames[#frames + 1] = s.frame end
  loader = loaderUI.build(frames)
  loader.show("Starting - hold a key to cancel")

  ----------------------------------------------------------------------------
  -- Global keys + periodic refresh
  ----------------------------------------------------------------------------
  -- Global keyboard dispatch (boot-cancel + q/r/t/u/i/d/a/1-9).
  keys.register(basalt, {
    state = state, rescan = rescan, redraw = redrawAll,
    cycleTheme = hooks.cycleTheme, doCheck = doCheck, doInstall = doInstall,
    termUI = termUI, reassign = reassignScreen,
  })

  -- Animate the loading overlay until the first scan completes.
  basalt.schedule(function()
    while loading do loader.tick(); sleep(0.3) end
  end)

  -- Boot splash (2s cancel window) -> first scan -> reveal -> background update check.
  -- All in this one Basalt session, so boot is a single seamless screen.
  basalt.schedule(function()
    for _ = 1, 7 do                       -- ~2s, but bail immediately on cancel
      if state.cancelBoot then return end
      sleep(0.3)
    end
    state.endBoot()
    loader.show("Loading colony data")
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
      state.tick()
      local anyModal = false
      for _, s in ipairs(screens) do if s.modal then anyModal = true; break end end
      if (state.needScan or state.countdown <= 0) and not anyModal and not loading then rescan() end
      redrawAll()
    end
  end)

  -- Smooth scan-countdown progress bar: finer than the 1s tick so it animates.
  -- Only updates a native Basalt ProgressBar property (cheap; no full redraw).
  basalt.schedule(function()
    while true do
      sleep(0.25)
      if not loading then
        local interval = config.refreshSeconds or 5
        local frac = (os.epoch("utc") - state.armAt) / 1000 / interval
        for _, s in ipairs(screens) do layout.updateScanBar(s, frac) end
      end
    end
  end)

  -- While a suggestion modal is open the full rescan is paused (so the list
  -- doesn't churn under it), but the citizen/visitor it points at keeps MOVING.
  -- Poll just their live position and update the modal's location label in place.
  basalt.schedule(function()
    while true do
      sleep(1)
      local open = false
      for _, s in ipairs(screens) do if s.modal and s.modal.kind == "apply" then open = true; break end end
      if open and not loading then
        local cloc = {}
        -- Guarded read via the colony port (returns {} when the peripheral errors).
        for _, c in ipairs(colPort.citizens()) do
          if c.id then cloc[c.id] = c.location end
        end
        for _, s in ipairs(screens) do
          if s.modal and s.modal.kind == "apply" then layout.refreshModalLocation(s, cloc) end
        end
      end
    end
  end)

  -- Hourly update check.
  basalt.schedule(function()
    while true do sleep(3600); checkUpdate(); redrawAll() end
  end)

  -- Answer pocket HELLO requests with the current snapshot.
  if rhost then rhost.serve(basalt) end

  basalt.run()

  teardown.run(state, screens)
end

return M

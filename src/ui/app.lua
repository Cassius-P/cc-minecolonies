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
  -- Single version source: the /version stamp written by install.lua from
  -- manifest.version. "?" until a stamped install exists.
  local installedVersion = updater.installed()
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
    quit = false, needScan = false, theme = config.theme, update = nil,
    booting = true }   -- true during the boot splash / cancel window
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

  -- Update actions (used by both the keyboard shortcuts and the tab button).
  local function doCheck()
    basalt.schedule(function()
      state.checking = true; redrawAll()
      checkUpdate()
      state.checking = false; redrawAll()
    end)
  end
  -- Hand off to the updater cleanly: stop our Basalt app, then run /update.lua
  -- (which draws its OWN Basalt UI) AFTER basalt.run() returns -- never nested,
  -- so the progress bar no longer flickers against our still-live UI.
  local function doInstall()
    if loading or state.pendingInstall then return end
    state.pendingInstall = true
    basalt.stop()
  end

  local function setMargin(key, value)
    local n = tonumber(value)
    if not n then return end   -- ignore partial/empty input
    config.suggestions = config.suggestions or { replaceMargin = 1, reassignMargin = 1 }
    config.suggestions[key] = math.max(0, math.min(20, math.floor(n)))
    settings.save(config, screens)
    state.needScan = true      -- apply on the next tick, NOT per keystroke (was laggy)
  end

  -- Dump selected colony data to paste.rs (JSON) and show the link.
  local function doDump(sel)
    local function g(fn, d) local ok, v = pcall(fn); if ok and v ~= nil then return v else return d end end
    local payload = { at = os.epoch and os.epoch("utc") or 0 }
    if sel.colony then
      payload.colony = { name = g(colony.getColonyName), id = g(colony.getColonyID),
        happiness = g(colony.getHappiness), pop = g(colony.amountOfCitizens),
        maxPop = g(colony.maxOfCitizens), attack = g(colony.isUnderAttack),
        raid = g(colony.isUnderRaid), sites = g(colony.amountOfConstructionSites),
        graves = g(colony.amountOfGraves) }
    end
    if sel.citizens   then payload.citizens   = g(function() return colony.getCitizens() end, {}) end
    if sel.buildings  then payload.buildings  = g(function() return colony.getBuildings() end, {}) end
    if sel.workOrders then payload.workOrders = g(function() return colony.getWorkOrders() end, {}) end
    if sel.requests   then payload.requests   = g(function() return colony.getRequests() end, {}) end
    if sel.visitors   then payload.visitors   = g(function() return colony.getVisitors() end, {}) end
    -- Deep-clone to break shared table references (serializeJSON errors on
    -- "repeated entries" when the same table is referenced more than once).
    local function clone(t)
      if type(t) ~= "table" then return t end
      local c = {}
      for k, v in pairs(t) do c[k] = clone(v) end
      return c
    end
    local okj, body = pcall(textutils.serializeJSON, clone(payload))
    if not okj then body = textutils.serialize(payload) end
    local res = http.post("https://paste.rs", body)
    if not res then error("paste.rs post failed (http)", 0) end
    local link = res.readAll(); res.close()
    return (link:gsub("%s+$", ""))
  end

  local function onDump(sel)
    if state.dumping then return end
    state.dumping = true; state.dumpLink = nil; state.dumpError = nil; redrawAll()
    basalt.schedule(function()
      local ok, link = pcall(doDump, sel or {})
      state.dumping = false
      if ok and link and link ~= "" then
        state.dumpLink = link
        -- CC has no OS clipboard (sandboxed); save the link to a file instead.
        pcall(function() local f = fs.open("/dump_link.txt", "w"); f.write(link); f.close() end)
      else
        state.dumpError = tostring(link)
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
      if state.update and state.update.available then doInstall() else doCheck() end
    end,
    onMargin = setMargin,
    onDump = onDump,
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
  loader.show("Starting - hold a key to cancel")

  ----------------------------------------------------------------------------
  -- Global keys + periodic refresh
  ----------------------------------------------------------------------------
  -- During the boot splash, ANY key cancels auto-launch and drops to the shell.
  basalt.onEvent("key", function()
    if state.booting then state.cancelBoot = true; basalt.stop() end
  end)

  basalt.onEvent("char", function(ch)
    if state.booting then return end   -- splash window: keys handled by the "key" cancel above
    -- Ignore global shortcuts while typing in an input field.
    local f = basalt.getFocus and basalt.getFocus()
    if f and f.get and (f.get("type") == "Input" or f.get("type") == "TextBox") then return end
    if ch == "q" then
      basalt.stop()
    elseif ch == "r" then
      rescan(); redrawAll()
    elseif ch == "t" then
      hooks.cycleTheme(); redrawAll()
    elseif ch == "u" then
      doCheck()
    elseif ch == "i" then
      doInstall()
    elseif ch == "d" then
      if termUI and termUI.triggerDump then termUI.triggerDump() end
    elseif ch == "a" then
      if termUI and termUI.toggleAllDump then termUI.toggleAllDump() end
    elseif type(ch) == "string" and ch:match("%d") then
      reassignScreen(tonumber(ch)); redrawAll()
    end
  end)

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
    state.booting = false
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
      state.countdown = state.countdown - 1
      local anyModal = false
      for _, s in ipairs(screens) do if s.modal then anyModal = true; break end end
      if (state.needScan or state.countdown <= 0) and not anyModal and not loading then rescan() end
      redrawAll()
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
        local okc, cits = pcall(function() return colony.getCitizens() end)
        if okc and type(cits) == "table" then
          for _, c in ipairs(cits) do if c.id then cloc[c.id] = c.location end end
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

  basalt.run()

  -- Teardown: restore palettes + clear.
  theme.restore(screens)
  for _, s in ipairs(screens) do
    s.mon.setBackgroundColor(colors.black); s.mon.clear(); s.mon.setCursorPos(1, 1)
  end
  term.setBackgroundColor(colors.black); term.setTextColor(colors.white)
  term.clear(); term.setCursorPos(1, 1)
  if state.cancelBoot then
    print("Auto-launch cancelled. Run 'main' to start the dashboard.")
    return
  end
  if state.pendingInstall then
    -- App Basalt is fully stopped now; the updater runs in its own single
    -- Basalt session (no nesting -> no flicker), then reboots.
    shell.run("/update.lua", "force")
    os.reboot()
    return
  end
  print("colony_dashboard stopped.")
end

return M

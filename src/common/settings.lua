----------------------------------------------------------------------------
-- common/settings.lua -- persist GLOBAL theme + PER-MONITOR section visibility
-- and layout (keyed by monitor name). Survives script updates.
----------------------------------------------------------------------------

local util = require("common.util")
local remote = require("common.remote")
local engine = require("ui.layout.engine")
local deepCopy = util.deepCopy

local M = {}
local FILE = "colony_dashboard.settings"

-- Apply one persisted layout entry `e` onto a layout slot in place.
local function applyInto(slot, e, config)
  if type(e.cfgIdx) == "number" and config.screens[e.cfgIdx] then
    slot.cfgIdx = e.cfgIdx
    slot.columns = deepCopy(config.screens[e.cfgIdx].columns)
    slot.weights = {}
  end
  if type(e.columns) == "table" then slot.columns = deepCopy(e.columns) end
  if type(e.weights) == "table" then slot.weights = deepCopy(e.weights) end
  if type(e.enabled) == "table" then
    local en = {}
    for k, v in pairs(e.enabled) do en[k] = v and true or false end
    slot.enabled = en
  end
end

-- Apply a persisted per-monitor entry `sc` onto screen `s`. Handles BOTH the
-- new multi-layout shape ({ activeLayout, layouts={...} }) and the legacy
-- single-layout shape (<=3.72, flat fields -> backfilled into slot 1). A pocket
-- screen has no `s.layouts`, so it stays on the single-layout path. Pure (no fs).
function M.applyScreenEntry(s, sc, config)
  if s.layouts then
    if type(sc.layouts) == "table" then
      for i = 1, engine.MAX_LAYOUTS do
        if type(sc.layouts[i]) == "table" then applyInto(s.layouts[i], sc.layouts[i], config) end
      end
      if type(sc.activeLayout) == "number" then
        s.activeLayout = math.max(1, math.min(engine.MAX_LAYOUTS, math.floor(sc.activeLayout)))
      end
    else
      applyInto(s.layouts[1], sc, config)   -- legacy: current layout -> slot 1
      s.activeLayout = 1
    end
    engine.activate(s)
  else
    local e = (type(sc.layouts) == "table" and sc.layouts[sc.activeLayout or 1]) or sc
    applyInto(s, e, config)
  end
end

-- load(config, screens, isTheme): mutate config.theme + each screen in place.
-- isTheme(name) validates a persisted theme name.
function M.load(config, screens, isTheme)
  if not fs.exists(FILE) then return end
  local f = fs.open(FILE, "r"); if not f then return end
  local raw = f.readAll(); f.close()
  local ok, t = pcall(textutils.unserialize, raw)
  if not (ok and type(t) == "table") then return end

  if type(t.theme) == "string" and isTheme(t.theme) then config.theme = t.theme end
  if remote.validChannel(t.channel) then config.channel = t.channel end
  if type(t.refreshSeconds) == "number" then config.refreshSeconds = t.refreshSeconds end
  if type(t.suggestions) == "table" then
    config.suggestions = config.suggestions or {}
    if type(t.suggestions.replaceMargin) == "number" then config.suggestions.replaceMargin = t.suggestions.replaceMargin end
    if type(t.suggestions.reassignMargin) == "number" then config.suggestions.reassignMargin = t.suggestions.reassignMargin end
  end
  if type(t.screens) ~= "table" then return end

  for _, s in ipairs(screens) do
    local sc = t.screens[s.name]
    if type(sc) == "table" then M.applyScreenEntry(s, sc, config) end
  end
end

function M.save(config, screens)
  -- MERGE over the existing file: a monitor that is not currently attached (e.g.
  -- slow to re-attach over the wired modem after an update/reboot) is absent from
  -- `screens`, and a plain rewrite would drop its saved layout for good. Read the
  -- persisted screens first and only overwrite the entries for present monitors.
  local out = { screens = {} }
  if fs.exists(FILE) then
    local f = fs.open(FILE, "r")
    if f then
      local raw = f.readAll(); f.close()
      local ok, t = pcall(textutils.unserialize, raw)
      if ok and type(t) == "table" and type(t.screens) == "table" then out.screens = t.screens end
    end
  end
  out.theme = config.theme
  out.channel = config.channel
  out.refreshSeconds = config.refreshSeconds
  out.suggestions = config.suggestions
  for _, s in ipairs(screens) do
    if s.layouts then
      local layouts = {}
      for i = 1, engine.MAX_LAYOUTS do
        local L = s.layouts[i] or engine.blankLayout()
        layouts[i] = { enabled = L.enabled, cfgIdx = L.cfgIdx, columns = L.columns, weights = L.weights }
      end
      out.screens[s.name] = { activeLayout = s.activeLayout or 1, layouts = layouts }
    else
      out.screens[s.name] = { enabled = s.enabled, cfgIdx = s.cfgIdx,
        columns = s.columns, weights = s.weights }
    end
  end
  local f = fs.open(FILE, "w"); if not f then return end
  f.write(textutils.serialize(out)); f.close()
end

return M

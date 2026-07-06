----------------------------------------------------------------------------
-- common/settings.lua -- persist GLOBAL theme + PER-MONITOR section visibility
-- and layout (keyed by monitor name). Survives script updates.
----------------------------------------------------------------------------

local util = require("common.util")
local deepCopy = util.deepCopy

local M = {}
local FILE = "colony_dashboard.settings"

-- load(config, screens, isTheme): mutate config.theme + each screen in place.
-- isTheme(name) validates a persisted theme name.
function M.load(config, screens, isTheme)
  if not fs.exists(FILE) then return end
  local f = fs.open(FILE, "r"); if not f then return end
  local raw = f.readAll(); f.close()
  local ok, t = pcall(textutils.unserialize, raw)
  if not (ok and type(t) == "table") then return end

  if type(t.theme) == "string" and isTheme(t.theme) then config.theme = t.theme end
  if type(t.channel) == "number" then config.channel = t.channel end
  if type(t.suggestions) == "table" then
    config.suggestions = config.suggestions or {}
    if type(t.suggestions.replaceMargin) == "number" then config.suggestions.replaceMargin = t.suggestions.replaceMargin end
    if type(t.suggestions.reassignMargin) == "number" then config.suggestions.reassignMargin = t.suggestions.reassignMargin end
  end
  if type(t.screens) ~= "table" then return end

  for _, s in ipairs(screens) do
    local sc = t.screens[s.name]
    if type(sc) == "table" then
      if type(sc.cfgIdx) == "number" and config.screens[sc.cfgIdx] then
        s.cfgIdx = sc.cfgIdx
        s.columns = deepCopy(config.screens[sc.cfgIdx].columns)
        s.weights = {}
      end
      if type(sc.columns) == "table" then s.columns = deepCopy(sc.columns) end
      if type(sc.weights) == "table" then s.weights = deepCopy(sc.weights) end
      if type(sc.enabled) == "table" then
        local en = {}
        for k, v in pairs(sc.enabled) do en[k] = v and true or false end
        s.enabled = en
      end
    end
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
  out.suggestions = config.suggestions
  for _, s in ipairs(screens) do
    out.screens[s.name] = { enabled = s.enabled, cfgIdx = s.cfgIdx,
      columns = s.columns, weights = s.weights }
  end
  local f = fs.open(FILE, "w"); if not f then return end
  f.write(textutils.serialize(out)); f.close()
end

return M

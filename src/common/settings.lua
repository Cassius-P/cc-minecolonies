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
  if type(t.screens) ~= "table" then return end

  for _, s in ipairs(screens) do
    local sc = t.screens[s.name]
    if type(sc) == "table" then
      if type(sc.cfgIdx) == "number" and config.screens[sc.cfgIdx] then
        s.cfgIdx = sc.cfgIdx
        s.layoutTree = deepCopy(config.screens[sc.cfgIdx].layout)
        s.geometry = nil  -- recompute defaults for the new layout
      end
      if type(sc.layout) == "table" then s.layoutTree = deepCopy(sc.layout) end
      if type(sc.geometry) == "table" then s.geometry = deepCopy(sc.geometry) end
      if type(sc.enabled) == "table" then
        local en = {}
        for k, v in pairs(sc.enabled) do en[k] = v and true or false end
        s.enabled = en
      end
    end
  end
end

function M.save(config, screens)
  local out = { theme = config.theme, screens = {} }
  for _, s in ipairs(screens) do
    out.screens[s.name] = { enabled = s.enabled, cfgIdx = s.cfgIdx,
      layout = s.layoutTree, geometry = s.geometry }
  end
  local f = fs.open(FILE, "w"); if not f then return end
  f.write(textutils.serialize(out)); f.close()
end

return M

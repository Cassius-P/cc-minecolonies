----------------------------------------------------------------------------
-- ui/terminal.lua -- the ADMIN VIEW: the UI on the Advanced Computer's own
-- screen (NOT the monitors). Assembles a Basalt TabControl from one module per
-- tab under ui/admin/ (status, monitors, peripherals, settings, dump, update).
--
-- Each view module exports { title, build(tab, ctx, api) -> updater(state, screens) }.
-- `api` is a shared table a view can register callbacks on (e.g. dump's
-- triggerDump / toggleAllDump for the global d / a keys).
----------------------------------------------------------------------------

local VIEWS = {
  require("ui.admin.status"),
  require("ui.admin.monitors"),
  require("ui.admin.peripherals"),
  require("ui.admin.settings"),
  require("ui.admin.dump"),
  require("ui.admin.update"),
}

local M = {}

-- build(mainFrame, ctx): ctx = { version, config, onUpdateButton, onMargin, onDump }.
function M.build(mainFrame, ctx)
  local tw, th = term.getSize()
  local tabs = mainFrame:addTabControl({
    x = 1, y = 1, width = tw, height = th,
    headerBackground = colors.gray, foreground = colors.white,
  })

  local api = {}
  local updaters = {}
  for _, v in ipairs(VIEWS) do
    local tab = tabs:newTab(v.title)
    updaters[#updaters + 1] = v.build(tab, ctx, api)
  end

  return {
    update = function(state, screens)
      for _, u in ipairs(updaters) do u(state, screens) end
    end,
    triggerDump   = function() if api.triggerDump then api.triggerDump() end end,
    toggleAllDump = function() if api.toggleAllDump then api.toggleAllDump() end end,
  }
end

return M

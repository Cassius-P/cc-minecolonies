----------------------------------------------------------------------------
-- ui/admin/monitors.lua -- admin view "Monitors" tab: connected monitors.
----------------------------------------------------------------------------

local diff = require("ui.admin.diff")

local M = { title = "Monitors" }

function M.build(tab, ctx)
  local tw, th = term.getSize()
  tab:addLabel({ x = 2, y = 1, width = tw - 2, foreground = colors.cyan })
    :setText("Monitors -- press 1-9 to change a monitor's screen")
  local tb = tab:addTextBox({ x = 2, y = 3, width = tw - 3, height = th - 4,
    editable = false, background = colors.black, foreground = colors.white })

  local set = diff.new()
  return function(_, screens)
    local ml = {}
    for i, s in ipairs(screens or {}) do
      ml[#ml + 1] = ("[%d] %s  %dx%d  -> screen %d"):format(i, s.name, s.W, s.H, s.cfgIdx or 1)
    end
    set(tb, table.concat(ml, "\n"))
  end
end

return M

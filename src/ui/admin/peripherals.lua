----------------------------------------------------------------------------
-- ui/admin/peripherals.lua -- admin view "Peripherals" tab: network map.
----------------------------------------------------------------------------

local diff  = require("ui.admin.diff")
local perif = require("common.peripherals")

local M = { title = "Peripherals" }

function M.build(tab, ctx)
  local tw, th = term.getSize()
  tab:addLabel({ x = 2, y = 1, width = tw - 2, foreground = colors.cyan })
    :setText("Network devices (name : type)")
  local tb = tab:addTextBox({ x = 2, y = 3, width = tw - 3, height = th - 4,
    editable = false, background = colors.black, foreground = colors.white })

  local set = diff.new()
  return function()
    local pl = {}
    for _, p in ipairs(perif.diagnostics()) do pl[#pl + 1] = ("%s : %s"):format(p.name, p.type) end
    set(tb, table.concat(pl, "\n"))
  end
end

return M

----------------------------------------------------------------------------
-- ui/admin/update.lua -- admin view "Update" tab: version + check/install.
----------------------------------------------------------------------------

local diff = require("ui.admin.diff")

local M = { title = "Update" }

function M.build(tab, ctx)
  local tw = select(1, term.getSize())
  local lVer = tab:addLabel({ x = 2, y = 1, width = tw - 2, foreground = colors.lightGray })
  local lUpd = tab:addLabel({ x = 2, y = 3, width = tw - 2 })
  local btn = tab:addButton({ x = 2, y = 5, width = 20, height = 1 })
    :onClick(function() if ctx.onUpdateButton then ctx.onUpdateButton() end end)
  tab:addLabel({ x = 2, y = 7, width = tw - 2, foreground = colors.gray })
    :setText("Check finds a new version; Install pulls it & reboots.")
  tab:addLabel({ x = 2, y = 8, width = tw - 2, foreground = colors.gray })
    :setText("Keys: u check   i install   (or 'update' in shell)")

  local set = diff.new()
  local btnBg
  local function btnStyle(bg, fg)
    if btnBg ~= bg then btn:setBackground(bg); btn:setForeground(fg); btnBg = bg end
  end
  return function(state)
    set(lVer, "Installed: v" .. ctx.version)
    local up = state.update
    if state.checking then
      set(lUpd, "Checking for updates...", colors.yellow); set(btn, "Checking..."); btnStyle(colors.gray, colors.white)
    elseif state.checkFailed and not (up and up.available) then
      set(lUpd, "Check failed - no connection", colors.red); set(btn, "Check for update"); btnStyle(colors.blue, colors.white)
    elseif up and up.available then
      set(lUpd, ("Update available: v%s -> v%s"):format(up.localv, up.remote), colors.orange)
      set(btn, "Install update"); btnStyle(colors.green, colors.black)
    elseif up then
      set(lUpd, ("Up to date (v%s)"):format(up.localv or ctx.version), colors.green)
      set(btn, "Check for update"); btnStyle(colors.blue, colors.white)
    else
      set(lUpd, "Not checked yet", colors.lightGray); set(btn, "Check for update"); btnStyle(colors.blue, colors.white)
    end
  end
end

return M

----------------------------------------------------------------------------
-- ui/admin/settings.lua -- admin view "Settings" tab: suggestion margins.
----------------------------------------------------------------------------

local diff = require("ui.admin.diff")

local M = { title = "Settings" }

local function marginHint(n)
  n = tonumber(n) or 1
  if n <= 0 then return "any gain" end
  return "gain >= " .. n
end

function M.build(tab, ctx)
  local tw = select(1, term.getSize())
  tab:addLabel({ x = 2, y = 1, width = tw - 2, foreground = colors.cyan })
    :setText("Worker suggestions -- how big a skill gain to suggest a move")

  tab:addLabel({ x = 2, y = 3, width = 16 }):setText("Replace worker"):setForeground(colors.white)
  local inReplace = tab:addInput({ x = 18, y = 3, width = 5, height = 1, placeholder = "1",
    background = colors.gray, foreground = colors.white })
  local lReplaceHint = tab:addLabel({ x = 24, y = 3, width = tw - 24, foreground = colors.lightGray })

  tab:addLabel({ x = 2, y = 5, width = 16 }):setText("Reassign job"):setForeground(colors.white)
  local inReassign = tab:addInput({ x = 18, y = 5, width = 5, height = 1, placeholder = "1",
    background = colors.gray, foreground = colors.white })
  local lReassignHint = tab:addLabel({ x = 24, y = 5, width = tw - 24, foreground = colors.lightGray })

  tab:addLabel({ x = 2, y = 8, width = tw - 2, foreground = colors.gray })
    :setText("Click a box, type a number (0-20).")
  tab:addLabel({ x = 2, y = 9, width = tw - 2, foreground = colors.gray })
    :setText("0 = suggest any gain   higher = only big upgrades")

  tab:addLabel({ x = 2, y = 11, width = 16 }):setText("Pocket channel"):setForeground(colors.white)
  local inChannel = tab:addInput({ x = 18, y = 11, width = 7, height = 1, placeholder = "10000",
    background = colors.gray, foreground = colors.white })
  tab:addLabel({ x = 2, y = 12, width = tw - 2, foreground = colors.gray })
    :setText("Modem channel shared with the pocket (10000-65535).")
  inChannel:setText(tostring(ctx.config.channel or 10000))
  inChannel:onChange("text", function(_, v) if ctx.onChannel then ctx.onChannel(v) end end)

  local sg = ctx.config.suggestions or {}
  inReplace:setText(tostring(sg.replaceMargin or 1))
  inReassign:setText(tostring(sg.reassignMargin or 1))
  inReplace:onChange("text", function(_, v) if ctx.onMargin then ctx.onMargin("replaceMargin", v) end end)
  inReassign:onChange("text", function(_, v) if ctx.onMargin then ctx.onMargin("reassignMargin", v) end end)

  local set = diff.new()
  return function()
    local s = ctx.config.suggestions or {}
    set(lReplaceHint, marginHint(s.replaceMargin), colors.lightGray)
    set(lReassignHint, marginHint(s.reassignMargin), colors.lightGray)
  end
end

return M

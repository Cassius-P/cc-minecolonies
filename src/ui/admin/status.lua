----------------------------------------------------------------------------
-- ui/admin/status.lua -- admin view "Status" tab: colony vitals.
----------------------------------------------------------------------------

local diff = require("ui.admin.diff")

local M = { title = "Status" }

-- build(tab, ctx, api) -> updater(state, screens)
function M.build(tab, ctx)
  local tw, th = term.getSize()
  local lTitle  = tab:addLabel({ x = 2, y = 1, width = tw - 2, foreground = colors.cyan })
  local lColony = tab:addLabel({ x = 2, y = 3, width = tw - 2 })
  local lPop    = tab:addLabel({ x = 2, y = 4, width = tw - 2 })
  local lThreat = tab:addLabel({ x = 2, y = 5, width = tw - 2 })
  local lWork   = tab:addLabel({ x = 2, y = 6, width = tw - 2 })
  local lBridge = tab:addLabel({ x = 2, y = 7, width = tw - 2 })
  local lFoot   = tab:addLabel({ x = 2, y = th - 2, width = tw - 2, foreground = colors.lightGray })
  tab:addLabel({ x = 2, y = th, width = tw - 2, foreground = colors.gray })
    :setText("r rescan  t theme  u check  i install  d dump  1-9 screen  q quit")

  local set = diff.new()
  return function(state)
    local d = state.data
    set(lTitle, "Colony Dashboard  v" .. ctx.version)
    if d then
      set(lColony, ("Colony: %s  #%s"):format(d.name, d.id), colors.white)
      set(lPop, ("Happy %.1f/10   Pop %d/%d   Idle %d"):format(d.happiness, d.pop, d.maxPop, d.idle),
        d.idle > 0 and colors.orange or colors.white)
      local threat = d.attack and "UNDER ATTACK" or (d.raid and "RAID INCOMING" or "Secure")
      set(lThreat, ("Threat: %s    Sites %d  Graves %d"):format(threat, d.sites, d.graves),
        (d.attack or d.raid) and colors.red or colors.lime)
      set(lWork, ("Workers to place: %d    Requests: %d [%s]"):format(#d.suggestions, #d.requests, d.reqMode),
        d.reqMode == "AUTO" and colors.lime or colors.lightGray)
      set(lBridge, ("Bridge: %s   Storage: %s"):format(d.bridgePresent and "yes" or "NO", d.storagePresent and "yes" or "NO"),
        (d.bridgePresent and d.storagePresent) and colors.white or colors.gray)
    else
      set(lColony, "scanning...", colors.gray)
    end
    set(lFoot, ("Theme %s   next scan %2ds   %s"):format(ctx.config.theme, state.countdown, state.msg or ""))
  end
end

return M

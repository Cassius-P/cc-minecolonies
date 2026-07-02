----------------------------------------------------------------------------
-- ui/terminal.lua -- Advanced Computer UI, built with native Basalt widgets.
--
-- A TabControl on the main (computer-term) frame aggregates the status,
-- monitor assignments, peripheral network map and update check into tabs.
-- build() creates the widgets once; update() refreshes their text each scan.
----------------------------------------------------------------------------

local perif = require("common.peripherals")

local M = {}

-- build(mainFrame, ctx): ctx = { version, config }. Returns { update(state, screens) }.
function M.build(mainFrame, ctx)
  local tw, th = term.getSize()
  local tabs = mainFrame:addTabControl({
    x = 1, y = 1, width = tw, height = th,
    headerBackground = colors.gray, foreground = colors.white,
  })
  local ui = {}

  -- Status ----------------------------------------------------------------
  local st = tabs:newTab("Status")
  st:addLabel({ x = 2, y = 1, width = tw - 2 }):setText("colony_dashboard v" .. ctx.version)
  ui.lColony = st:addLabel({ x = 2, y = 3, width = tw - 2 })
  ui.lPop    = st:addLabel({ x = 2, y = 4, width = tw - 2 })
  ui.lThreat = st:addLabel({ x = 2, y = 5, width = tw - 2 })
  ui.lWork   = st:addLabel({ x = 2, y = 6, width = tw - 2 })
  ui.lBridge = st:addLabel({ x = 2, y = 7, width = tw - 2 })
  ui.lFoot   = st:addLabel({ x = 2, y = th - 3, width = tw - 2 }):setForeground(colors.lightGray)
  st:addLabel({ x = 2, y = th - 1, width = tw - 2 })
    :setText("Keys: r rescan  t theme  1-9 screen  q quit"):setForeground(colors.lightGray)

  -- Monitors --------------------------------------------------------------
  local mt = tabs:newTab("Monitors")
  mt:addLabel({ x = 2, y = 1, width = tw - 2 })
    :setText("Press 1-9 to reassign a monitor's screen:"):setForeground(colors.cyan)
  ui.tbMon = mt:addTextBox({ x = 2, y = 3, width = tw - 3, height = th - 5,
    editable = false, background = colors.black, foreground = colors.white })

  -- Peripherals -----------------------------------------------------------
  local pt = tabs:newTab("Peripherals")
  pt:addLabel({ x = 2, y = 1, width = tw - 2 })
    :setText("Network devices (name : type):"):setForeground(colors.cyan)
  ui.tbPerif = pt:addTextBox({ x = 2, y = 3, width = tw - 3, height = th - 5,
    editable = false, background = colors.black, foreground = colors.white })

  -- Update ----------------------------------------------------------------
  local ut = tabs:newTab("Update")
  ui.lUpd = ut:addLabel({ x = 2, y = 2, width = tw - 2 })
  ut:addButton({ x = 2, y = 4, width = 22, height = 1 })
    :setText("Install / update now")
    :setBackground(colors.green):setForeground(colors.black)
    :onClick(function() if ctx.onUpdate then ctx.onUpdate() end end)
  ut:addLabel({ x = 2, y = 6, width = tw - 2 })
    :setText("Pulls the latest from GitHub and reboots."):setForeground(colors.lightGray)
  ut:addLabel({ x = 2, y = 7, width = tw - 2 })
    :setText("(or type 'update' at the shell)"):setForeground(colors.gray)

  return { update = function(state, screens) M._update(ui, ctx, state, screens) end }
end

function M._update(ui, ctx, state, screens)
  local d = state.data
  if d then
    ui.lColony:setText(("Colony: %s  #%s"):format(d.name, d.id))
    ui.lPop:setText(("Happy %.1f/10   Pop %d/%d   Idle %d"):format(d.happiness, d.pop, d.maxPop, d.idle))
      :setForeground(d.idle > 0 and colors.orange or colors.white)
    local threat = d.attack and "UNDER ATTACK" or (d.raid and "RAID INCOMING" or "Secure")
    ui.lThreat:setText(("Threat: %s    Sites %d  Graves %d"):format(threat, d.sites, d.graves))
      :setForeground((d.attack or d.raid) and colors.red or colors.lime)
    ui.lWork:setText(("Workers to place: %d    Requests: %d [%s]"):format(#d.suggestions, #d.requests, d.reqMode))
      :setForeground(d.reqMode == "AUTO" and colors.lime or colors.lightGray)
    ui.lBridge:setText(("Bridge: %s   Storage: %s"):format(d.bridgePresent and "yes" or "NO", d.storagePresent and "yes" or "NO"))
      :setForeground((d.bridgePresent and d.storagePresent) and colors.white or colors.gray)
  else
    ui.lColony:setText("scanning...")
  end
  ui.lFoot:setText(("Theme: %s   next scan: %ds   %s"):format(ctx.config.theme, state.countdown, state.msg or ""))

  local ml = {}
  for i, s in ipairs(screens) do
    ml[#ml + 1] = ("[%d] %s  %dx%d  -> screen %d"):format(i, s.name, s.W, s.H, s.cfgIdx or 1)
  end
  ui.tbMon:setText(table.concat(ml, "\n"))

  local pl = {}
  for _, p in ipairs(perif.diagnostics()) do pl[#pl + 1] = ("%s : %s"):format(p.name, p.type) end
  ui.tbPerif:setText(table.concat(pl, "\n"))

  local up = state.update
  if up and up.available then
    ui.lUpd:setText(("* Update available: v%s -> v%s"):format(up.localv, up.remote)):setForeground(colors.orange)
  elseif up then
    ui.lUpd:setText(("Up to date (v%s)"):format(up.remote or ctx.version)):setForeground(colors.green)
  else
    ui.lUpd:setText("Checking for updates..."):setForeground(colors.lightGray)
  end
end

return M

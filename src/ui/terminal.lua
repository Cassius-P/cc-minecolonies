----------------------------------------------------------------------------
-- ui/terminal.lua -- live status panel on the Advanced Computer screen.
--
-- Shows colony vitals, workers-to-place, request/auto-fulfill state, monitor
-- assignments, and a peripheral list (network names + types) so remote
-- peripherals on a wired modem can be identified and pinned in config.
----------------------------------------------------------------------------

local perif = require("common.peripherals")

local M = {}

-- render(win, ctx): ctx = { version, config, state, screens, data }
function M.render(win, ctx)
  local tw, th = win.getSize()
  win.setBackgroundColor(colors.black); win.setTextColor(colors.white); win.clear()
  local function line(y, txt, col)
    if y < 1 or y > th then return end
    win.setCursorPos(1, y); win.setTextColor(col or colors.white)
    win.setBackgroundColor(colors.black)
    win.write(tostring(txt):sub(1, tw))
  end

  local d = ctx.state.data
  line(1, "colony_dashboard v" .. ctx.version .. "  \183 running", colors.yellow)
  if d then
    line(2, ("Colony: %s  #%s"):format(d.name, d.id), colors.white)
    line(3, ("Happy %.1f/10   Pop %d/%d   Idle %d"):format(d.happiness, d.pop, d.maxPop, d.idle),
      d.idle > 0 and colors.orange or colors.white)
    local threat = d.attack and "UNDER ATTACK" or (d.raid and "RAID INCOMING" or "Secure")
    line(4, ("Threat: %s    Sites %d  Graves %d"):format(threat, d.sites, d.graves),
      (d.attack or d.raid) and colors.red or colors.lime)
    line(5, ("Workers to place: %d    Requests: %d [%s]"):format(#d.suggestions, #d.requests, d.reqMode),
      d.reqMode == "AUTO" and colors.lime or colors.lightGray)
    line(6, ("Bridge: %s   Storage: %s"):format(d.bridgePresent and "yes" or "NO", d.storagePresent and "yes" or "NO"),
      (d.bridgePresent and d.storagePresent) and colors.white or colors.gray)
  else
    line(2, "scanning...", colors.gray)
  end

  local up = ctx.state.update
  if up and up.available then
    line(7, ("* Update available: v%s -> v%s   (type 'update')"):format(up.localv, up.remote), colors.orange)
  elseif up then
    line(7, ("Up to date (v%s)"):format(up.remote or ctx.version), colors.green)
  end

  line(8, "Monitors (press number to reassign screen):", colors.cyan)
  local y = 9
  for i, s in ipairs(ctx.screens) do
    if y > th - 9 then break end
    line(y, ("[%d] %-12s %dx%d  -> screen %d"):format(i, s.name, s.W, s.H, s.cfgIdx or 1), colors.white)
    y = y + 1
  end

  -- Peripheral network map (useful for pinning remotes over a wired modem).
  line(y + 1, "Peripherals (name : type):", colors.cyan); y = y + 2
  for _, p in ipairs(perif.diagnostics()) do
    if y > th - 3 then break end
    line(y, ("  %s : %s"):format(p.name, p.type), colors.lightGray); y = y + 1
  end

  line(th - 2, ("Theme: %s     next scan: %ds"):format(ctx.config.theme, ctx.state.countdown), colors.lightGray)
  line(th - 1, "[r]escan  [t]heme  [1-9]reassign screen  [q]uit", colors.lightGray)
  line(th, ctx.state.msg or "", colors.gray)
end

return M

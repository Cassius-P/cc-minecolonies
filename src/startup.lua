----------------------------------------------------------------------------
-- startup.lua -- auto-launch the dashboard on boot with a Basalt splash.
--
-- Shows a Basalt splash for 2s (hold any key to cancel), then runs the
-- dashboard. Falls back to plain text if Basalt can't load, and keeps the
-- shell (no boot loop) if the dashboard errors.
----------------------------------------------------------------------------

package.path = "/?.lua;/?/init.lua;" .. package.path

local cancelled = false
local ok, basalt = pcall(require, "basalt")

if ok and basalt then
  local w, h = term.getSize()
  local main = basalt.getMainFrame()
  local function centered(y, text, color)
    local x = math.max(1, math.floor((w - #text) / 2) + 1)
    main:addLabel({ x = x, y = y, width = #text, foreground = color }):setText(text)
  end
  centered(math.floor(h / 2), "colony_dashboard starting...", colors.yellow)
  centered(math.floor(h / 2) + 2, "hold any key to cancel", colors.lightGray)
  basalt.schedule(function() sleep(2); basalt.stop() end)
  basalt.onEvent("key", function() cancelled = true; basalt.stop() end)
  basalt.onEvent("char", function() cancelled = true; basalt.stop() end)
  basalt.run()
else
  term.clear(); term.setCursorPos(1, 1)
  print("colony_dashboard starting...  (hold a key to cancel)")
  local timer = os.startTimer(2)
  while true do
    local ev, p = os.pullEvent()
    if ev == "timer" and p == timer then break end
    if ev == "key" or ev == "char" then cancelled = true; break end
  end
end

term.clear(); term.setCursorPos(1, 1)
if cancelled then
  print("Auto-launch cancelled. Run 'main' to start the dashboard.")
  return
end

local ran, err = pcall(function() shell.run("/main.lua") end)
if not ran then
  term.setTextColor(colors.red)
  print("Dashboard error: " .. tostring(err))
  term.setTextColor(colors.white)
  print("Fix and run 'main', or 'update' to pull a new version.")
end

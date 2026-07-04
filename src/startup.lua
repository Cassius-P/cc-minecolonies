----------------------------------------------------------------------------
-- startup.lua -- auto-launch the dashboard on boot.
--
-- Plain-text 2s cancel prompt (hold any key to cancel), then runs the
-- dashboard. Kept text-only on purpose: Basalt then initializes exactly ONCE
-- (inside the app), so boot no longer double-clears the screen. The app's own
-- Basalt loading overlay is the single "loading" screen. Keeps the shell (no
-- boot loop) if the dashboard errors.
----------------------------------------------------------------------------

package.path = "/?.lua;/?/init.lua;" .. package.path

term.clear(); term.setCursorPos(1, 1)
print("colony_dashboard starting...  (hold a key to cancel)")

local cancelled = false
local timer = os.startTimer(2)
while true do
  local ev, p = os.pullEvent()
  if ev == "timer" and p == timer then break end
  if ev == "key" or ev == "char" then cancelled = true; break end
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

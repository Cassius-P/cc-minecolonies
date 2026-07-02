----------------------------------------------------------------------------
-- startup.lua -- auto-launch the dashboard on boot.
--
-- Installed to /startup.lua so the Advanced Computer runs the dashboard
-- automatically. Hold any key within 2s to cancel and drop to the shell.
-- On a runtime error the message is printed and the shell is kept (no boot
-- loop).
----------------------------------------------------------------------------

package.path = "/?.lua;/?/init.lua;" .. package.path

term.clear(); term.setCursorPos(1, 1)
print("colony_dashboard starting...  (hold a key to cancel)")

local timer = os.startTimer(2)
local cancelled = false
while true do
  local ev, p = os.pullEvent()
  if ev == "timer" and p == timer then break end
  if ev == "key" or ev == "char" then cancelled = true; break end
end

if cancelled then
  print("Auto-launch cancelled. Run 'main' to start the dashboard.")
  return
end

local ok, err = pcall(function() shell.run("/main.lua") end)
if not ok then
  term.setTextColor(colors.red)
  print("Dashboard error: " .. tostring(err))
  term.setTextColor(colors.white)
  print("Fix and run 'main', or 'update' to pull a new version.")
end

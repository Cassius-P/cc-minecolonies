----------------------------------------------------------------------------
-- startup.lua -- auto-launch the dashboard on boot.
--
-- Just launches the app. The 2-second "hold a key to cancel" splash lives
-- INSIDE the app now (ui/app.lua), so Basalt initializes exactly once for the
-- whole boot -- splash -> loading -> content in a single session, no
-- double screen-clear. Keeps the shell (no boot loop) if the app errors.
----------------------------------------------------------------------------

package.path = "/?.lua;/?/init.lua;" .. package.path

local ran, err = pcall(function() shell.run("/main.lua") end)
if not ran then
  term.setTextColor(colors.red)
  print("Dashboard error: " .. tostring(err))
  term.setTextColor(colors.white)
  print("Fix and run 'main', or 'update' to pull a new version.")
end

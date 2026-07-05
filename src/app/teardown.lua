----------------------------------------------------------------------------
-- app/teardown.lua -- shutdown sequence after basalt.run() returns.
--
-- Restores monitor palettes, clears the screens + terminal, then branches on
-- why the app stopped: boot cancelled (drop to shell), install pending (hand off
-- to the updater in its own Basalt session, then reboot), or a normal quit.
----------------------------------------------------------------------------

local theme = require("ui.theme")

local M = {}

function M.run(state, screens)
  theme.restore(screens)
  for _, s in ipairs(screens) do
    s.mon.setBackgroundColor(colors.black); s.mon.clear(); s.mon.setCursorPos(1, 1)
  end
  term.setBackgroundColor(colors.black); term.setTextColor(colors.white)
  term.clear(); term.setCursorPos(1, 1)

  if state.cancelBoot then
    print("Auto-launch cancelled. Run 'main' to start the dashboard.")
    return
  end
  if state.pendingInstall then
    -- App Basalt is fully stopped now; the updater runs in its own single
    -- Basalt session (no nesting -> no flicker), then reboots.
    shell.run("/update.lua", "force")
    os.reboot()
    return
  end
  print("colony_dashboard stopped.")
end

return M

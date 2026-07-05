----------------------------------------------------------------------------
-- app/keys.lua -- global keyboard dispatch for the computer terminal.
--
-- Basalt native tab buttons are unreliable, so the computer's global keys are
-- the primary control path. register(basalt, rt) wires them; rt carries the
-- action callbacks so this module stays free of app internals:
--   rt = { state, rescan, redraw, cycleTheme, doCheck, doInstall, termUI, reassign }
--
-- During the boot splash ANY key cancels auto-launch (handled on "key"); once
-- booted, single chars drive q/r/t/u/i/d/a and 1-9 (monitor layout reassign).
----------------------------------------------------------------------------

local M = {}

function M.register(basalt, rt)
  local state = rt.state

  basalt.onEvent("key", function()
    if state.booting then state.cancelBooting(); basalt.stop() end
  end)

  basalt.onEvent("char", function(ch)
    if state.booting then return end   -- splash window: keys handled by the "key" cancel above
    -- Ignore global shortcuts while typing in an input field.
    local f = basalt.getFocus and basalt.getFocus()
    if f and f.get and (f.get("type") == "Input" or f.get("type") == "TextBox") then return end
    if ch == "q" then
      basalt.stop()
    elseif ch == "r" then
      rt.rescan(); rt.redraw()
    elseif ch == "t" then
      rt.cycleTheme(); rt.redraw()
    elseif ch == "u" then
      rt.doCheck()
    elseif ch == "i" then
      rt.doInstall()
    elseif ch == "d" then
      if rt.termUI and rt.termUI.triggerDump then rt.termUI.triggerDump() end
    elseif ch == "a" then
      if rt.termUI and rt.termUI.toggleAllDump then rt.termUI.toggleAllDump() end
    elseif type(ch) == "string" and ch:match("%d") then
      rt.reassign(tonumber(ch)); rt.redraw()
    end
  end)
end

return M

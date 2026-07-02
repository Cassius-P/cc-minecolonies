----------------------------------------------------------------------------
-- uninstall.lua -- remove the colony dashboard from this computer (Basalt UI).
--
-- Deletes every installed file/folder, the auto-launch startup, and the saved
-- settings/log. Uses Basalt when available, plain text otherwise. Offline.
----------------------------------------------------------------------------

package.path = "/?.lua;/?/init.lua;" .. package.path

local targets = {
  "/common", "/colony", "/storage", "/ui",       -- module folders
  "/basalt.lua", "/main.lua", "/startup.lua",     -- entry + dependency
  "/config.lua", "/version",                      -- config + version stamp
  "/install.lua", "/update.lua", "/uninstall.lua", -- installer scripts
  "/colony_dashboard.settings", "/colony_dashboard_log.txt", -- state + log
}

local function doDelete()
  local removed = 0
  for _, path in ipairs(targets) do
    if fs.exists(path) then fs.delete(path); removed = removed + 1 end
  end
  return removed
end

local ok, basalt = pcall(require, "basalt")

if ok and basalt then
  local w = select(1, term.getSize())
  local main = basalt.getMainFrame()
  main:addLabel({ x = 2, y = 2, width = w - 2, foreground = colors.yellow })
    :setText("Uninstall colony_dashboard?")
  main:addLabel({ x = 2, y = 3, width = w - 2, foreground = colors.white })
    :setText("Deletes all files, settings and boot launch.")
  local result = main:addLabel({ x = 2, y = 7, width = w - 2 })
  main:addButton({ x = 2, y = 5, width = 12, height = 1 })
    :setText("Uninstall"):setBackground(colors.red):setForeground(colors.white)
    :onClick(function()
      local n = doDelete()
      result:setText(("Removed %d item(s). Reboot to finish."):format(n)):setForeground(colors.lime)
    end)
  main:addButton({ x = 15, y = 5, width = 8, height = 1 })
    :setText("Close"):setBackground(colors.gray):setForeground(colors.white)
    :onClick(function() basalt.stop() end)
  basalt.run()
  term.clear(); term.setCursorPos(1, 1)
else
  term.setTextColor(colors.yellow); print("Uninstall colony_dashboard?")
  term.setTextColor(colors.white); print("Deletes all files, settings and boot launch.")
  write("Type 'y' to confirm: ")
  if read() ~= "y" then print("Cancelled."); return end
  print(("Removed %d item(s). Reboot to finish."):format(doDelete()))
end

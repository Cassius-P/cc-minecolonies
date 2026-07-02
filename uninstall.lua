----------------------------------------------------------------------------
-- uninstall.lua -- remove the colony dashboard from this computer.
--
-- Deletes every installed file/folder, the auto-launch startup, and the saved
-- settings/log. Works offline (no manifest fetch needed). Run: uninstall
----------------------------------------------------------------------------

local targets = {
  "/common", "/colony", "/storage", "/ui",       -- module folders
  "/basalt.lua", "/main.lua", "/startup.lua",     -- entry + dependency
  "/config.lua", "/version",                      -- config + version stamp
  "/install.lua", "/update.lua", "/uninstall.lua", -- installer scripts
  "/colony_dashboard.settings", "/colony_dashboard_log.txt", -- state + log
}

term.setTextColor(colors.yellow)
print("Uninstall colony_dashboard?")
term.setTextColor(colors.white)
print("This deletes all its files, settings and the boot auto-launch.")
write("Type 'y' to confirm: ")
local answer = read()
if answer ~= "y" and answer ~= "Y" then
  print("Cancelled. Nothing removed.")
  return
end

local removed = 0
for _, path in ipairs(targets) do
  if fs.exists(path) then
    fs.delete(path)
    removed = removed + 1
  end
end

term.setTextColor(colors.lime)
print(("Removed %d item(s). colony_dashboard uninstalled."):format(removed))
term.setTextColor(colors.white)
print("Reboot to clear the running dashboard.")

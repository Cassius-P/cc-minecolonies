----------------------------------------------------------------------------
-- update.lua -- check GitHub for a newer version, then install it in place.
--
--   update         check; install only if a newer version exists
--   update force   skip the check and reinstall regardless
--
-- The install runs on ONE Basalt screen (shared common/install_ui) with a
-- package-manager style log. Only files whose git blob sha differs from the
-- local copy are downloaded (common/installer diff), so an update is fast.
-- Config + settings are preserved; reboots to apply.
----------------------------------------------------------------------------

local REPO = { owner = "Cassius-P", repo = "cc-minecolonies", branch = "main" }

package.path = "/?.lua;/?/init.lua;" .. package.path
local force = (({ ... })[1] == "force")

local installer = require("common.installer")
local installUI = require("common.install_ui")

local function localVersion()
  if not fs.exists("/version") then return nil end
  local f = fs.open("/version", "r"); if not f then return nil end
  local v = f.readAll(); f.close(); return (v:gsub("%s+", ""))
end

term.clear(); term.setCursorPos(1, 1)
print("colony_dashboard update - checking...")

local ref = installer.resolveRef(REPO)
local manifest = installer.loadManifest(installer.fetch(REPO, ref, "manifest.lua"))
if not manifest then
  term.setTextColor(colors.red)
  print("Could not reach GitHub. Try again, or 'update force'.")
  term.setTextColor(colors.white)
  return
end

local lv, rv = localVersion(), tostring(manifest.version or "?")
if not force and lv and lv == rv then
  term.setTextColor(colors.lime)
  print(("Already up to date (v%s)."):format(lv))
  term.setTextColor(colors.white)
  return
end

local res = installUI.run({
  title = "colony_dashboard update",
  subtitle = ("v%s  ->  v%s"):format(lv or "?", rv),
  install = function(progress)
    return installer.install(REPO, ref, manifest, { preserveConfig = true, diff = true, progress = progress })
  end,
})

if res and #res.failed == 0 then
  term.setTextColor(colors.lime)
  print(("Updated to v%s. Rebooting..."):format(res.version or rv))
  term.setTextColor(colors.white)
  sleep(1.5)
  os.reboot()
else
  term.setTextColor(colors.red)
  print("Update finished with errors - not rebooting.")
  if res then for _, f in ipairs(res.failed) do print("  " .. f) end end
  term.setTextColor(colors.white)
end

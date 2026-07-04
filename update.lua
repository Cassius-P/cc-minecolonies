----------------------------------------------------------------------------
-- update.lua -- check GitHub for a newer version, then install it in place.
--
--   update         check; install only if a newer version exists
--   update force   skip the check and reinstall regardless
--
-- Runs entirely in ONE Basalt screen via the shared installer module -- no
-- second process, no nested Basalt, so nothing flickers. Config + settings are
-- preserved (installer keeps manifest.config targets); reboots to apply.
----------------------------------------------------------------------------

local REPO = { owner = "Cassius-P", repo = "cc-minecolonies", branch = "main" }

package.path = "/?.lua;/?/init.lua;" .. package.path
local force = (({ ... })[1] == "force")

local basalt    = require("basalt")
local installer = require("common.installer")

local function localVersion()
  if not fs.exists("/version") then return nil end
  local f = fs.open("/version", "r"); if not f then return nil end
  local v = f.readAll(); f.close(); return (v:gsub("%s+", ""))
end

local w = select(1, term.getSize())
local main = basalt.getMainFrame()
main:addLabel({ x = 2, y = 2, width = w - 2, foreground = colors.yellow })
  :setText("colony_dashboard update")
local status = main:addLabel({ x = 2, y = 4, width = w - 2, foreground = colors.white })
  :setText("Checking for updates...")
local barW = w - 4
local bar = main:addFrame({ x = 2, y = 6, width = barW, height = 1, backgroundColor = colors.gray })
bar.set("visible", false)
local fill = bar:addFrame({ x = 1, y = 1, width = 1, height = 1, backgroundColor = colors.lime })

basalt.schedule(function()
  local ref = installer.resolveRef(REPO)
  local manifest = installer.loadManifest(installer.fetch(REPO, ref, "manifest.lua"))
  if not manifest then
    status:setText("Could not reach GitHub. Try again, or 'update force'."):setForeground(colors.red)
    sleep(2.5); basalt.stop(); return
  end

  local lv, rv = localVersion(), tostring(manifest.version or "?")
  if not force and lv and lv == rv then
    status:setText(("Already up to date (v%s)."):format(lv)):setForeground(colors.lime)
    sleep(2); basalt.stop(); return
  end

  status:setText(("Updating v%s -> v%s"):format(lv or "?", rv)):setForeground(colors.orange)
  bar.set("visible", true)
  local res = installer.install(REPO, ref, manifest, {
    preserveConfig = true,
    progress = function(i, n, name)
      status:setText(("%d/%d  %s"):format(i, n, name))
      fill:setSize(math.max(1, math.floor(barW * i / n)), 1)
    end,
  })

  if #res.failed > 0 then
    status:setText(("Done with %d error(s) - not rebooting."):format(#res.failed))
      :setForeground(colors.red)
    sleep(3); basalt.stop(); return
  end
  status:setText(("Updated to v%s. Rebooting..."):format(res.version or rv)):setForeground(colors.lime)
  sleep(1.5)
  os.reboot()
end)

basalt.run()
term.clear(); term.setCursorPos(1, 1)

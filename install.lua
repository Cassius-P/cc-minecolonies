----------------------------------------------------------------------------
-- install.lua -- install / update the colony dashboard from GitHub.
--
--   Fresh install:          wget <raw>/install.lua install.lua  &&  install.lua
--   Update (keeps config):  install.lua update      (usually run via 'update')
--
-- Bootstraps Basalt + the shared installer module on a fresh computer, then
-- does all the work behind ONE Basalt screen (no plain-text flicker, no second
-- UI). Config targets are kept if already present.
----------------------------------------------------------------------------

-- >>> Point this at your public GitHub repo. <<<
local REPO = { owner = "Cassius-P", repo = "cc-minecolonies", branch = "main" }

package.path = "/?.lua;/?/init.lua;" .. package.path

-- Args: "update" (preserve config) and/or an explicit commit SHA to fetch from
-- (skips the API entirely -- used by the manual bootstrap when rate-limited).
local isUpdate, refArg = false, nil
for _, a in ipairs({ ... }) do
  if a == "update" then isUpdate = true
  elseif type(a) == "string" and #a >= 7 and #a <= 40 and a:match("^%x+$") then refArg = a end
end

-- Minimal inline fetch, used ONLY to bootstrap basalt + the installer module on
-- a fresh computer. Everything after that goes through the installer module.
local function ghSha()
  local h = http.get(("https://api.github.com/repos/%s/%s/commits/%s")
    :format(REPO.owner, REPO.repo, REPO.branch),
    { ["Accept"] = "application/vnd.github.sha", ["User-Agent"] = "cc-minecolonies" })
  if not h then return nil end
  local s = h.readAll(); h.close(); s = s:gsub("%s+", "")
  return (#s >= 7 and #s <= 64 and s:match("^%x+$")) and s or nil
end
local REF = refArg or ghSha() or REPO.branch
local function bootFetch(path)
  local suffix = (REF == REPO.branch) and ("?nocache=" .. (os.epoch and os.epoch("utc") or 0)) or ""
  local h = http.get(("https://raw.githubusercontent.com/%s/%s/%s/%s%s")
    :format(REPO.owner, REPO.repo, REF, path, suffix), { ["Cache-Control"] = "no-cache" })
  if not h then return nil end
  local body = h.readAll(); h.close(); return body
end
local function bootWrite(dst, body)
  local dir = fs.getDir(dst)
  if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local f = fs.open(dst, "w"); if not f then return false end
  f.write(body); f.close(); return true
end

-- Bootstrap: Basalt (if missing) + the installer module (always refresh, so it
-- can never go stale relative to the manifest it will act on).
if not fs.exists("/basalt.lua") then
  local b = bootFetch("vendor/basalt.lua"); if b then bootWrite("/basalt.lua", b) end
end
do
  local inst = bootFetch("src/common/installer.lua")
  if inst then bootWrite("/common/installer.lua", inst) end
end

local hasBasalt, basalt = pcall(require, "basalt")
local okI, installer = pcall(require, "common.installer")
if not okI then error("Could not load installer module (check http + repo)", 0) end

local manifest = installer.loadManifest(installer.fetch(REPO, REF, "manifest.lua"))
if not manifest then error("Could not fetch/parse manifest.lua (check http + repo)", 0) end

local function run(progress)
  return installer.install(REPO, REF, manifest, { preserveConfig = isUpdate, progress = progress })
end

local res
if hasBasalt then
  local w = select(1, term.getSize())
  local main = basalt.getMainFrame()
  main:addLabel({ x = 2, y = 2, width = w - 2, foreground = colors.yellow })
    :setText((isUpdate and "Updating" or "Installing") .. " colony_dashboard")
  local status = main:addLabel({ x = 2, y = 4, width = w - 2, foreground = colors.white })
  local barW = w - 4
  local bar = main:addFrame({ x = 2, y = 6, width = barW, height = 1, backgroundColor = colors.gray })
  local fill = bar:addFrame({ x = 1, y = 1, width = 1, height = 1, backgroundColor = colors.lime })
  local doneLbl = main:addLabel({ x = 2, y = 8, width = w - 2, foreground = colors.lightGray })
  basalt.schedule(function()
    res = run(function(i, n, name)
      status:setText(("%d/%d  %s"):format(i, n, name))
      fill:setSize(math.max(1, math.floor(barW * i / n)), 1)
    end)
    if #res.failed > 0 then
      status:setText(("Done with %d error(s)."):format(#res.failed)):setForeground(colors.red)
    else
      status:setText(("Done. Wrote %d, kept %d.  v%s"):format(res.wrote, res.kept, res.version or "?"))
        :setForeground(colors.lime)
    end
    doneLbl:setText(isUpdate and "Reboot to apply." or "Reboot to auto-launch.")
    sleep(2)
    basalt.stop()
  end)
  basalt.run()
  term.clear(); term.setCursorPos(1, 1)
  -- Success is fully reported in-frame (one screen). Only spill to text if
  -- something failed to write, so the user sees exactly which files.
  if res and #res.failed > 0 then
    term.setTextColor(colors.red); print("FAILED to write:")
    for _, f in ipairs(res.failed) do print("  " .. f) end
    term.setTextColor(colors.white)
    print(("(Wrote %d, kept %d, version %s)"):format(res.wrote, res.kept, res.version or "?"))
  end
else
  io.write(isUpdate and "Updating" or "Installing")
  res = run(function() io.write(".") end)
  print("")
  print(("Wrote %d, kept %d config file(s), version %s")
    :format(res.wrote, res.kept, res.version or "?"))
  if #res.failed > 0 then
    term.setTextColor(colors.red); print("FAILED to write:")
    for _, f in ipairs(res.failed) do print("  " .. f) end
    term.setTextColor(colors.white)
  else
    print(isUpdate and "Update complete. Reboot to apply." or "Install complete. Reboot to auto-launch.")
  end
end

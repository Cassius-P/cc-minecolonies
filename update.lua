----------------------------------------------------------------------------
-- update.lua -- check GitHub for a newer version, then install it.
--
--   update         check; install only if a newer version exists
--   update force   skip the check and reinstall regardless
--
-- Re-downloads install.lua (which carries the file manifest logic) and runs it
-- in update mode. Config and settings are preserved.
----------------------------------------------------------------------------

-- >>> Keep in sync with install.lua's REPO. <<<
local REPO = { owner = "Cassius-P", repo = "cc-minecolonies", branch = "main" }

local force = (({ ... })[1] == "force")

local function rawUrl(path)
  return string.format("https://raw.githubusercontent.com/%s/%s/%s/%s?nocache=%d",
    REPO.owner, REPO.repo, REPO.branch, path, os.epoch and os.epoch("utc") or 0)
end

local function localVersion()
  if not fs.exists("/version") then return nil end
  local f = fs.open("/version", "r"); if not f then return nil end
  local v = f.readAll(); f.close()
  return (v:gsub("%s+", ""))
end

local function remoteVersion()
  local h = http.get(rawUrl("manifest.lua"), { ["Cache-Control"] = "no-cache" })
  if not h then return nil end
  local body = h.readAll(); h.close()
  local ok, mf = pcall(function() return load(body, "manifest", "t", {})() end)
  if ok and type(mf) == "table" and mf.version then return tostring(mf.version) end
  return nil
end

-- Check step: skip the reinstall when already on the latest version.
if not force then
  local lv, rv = localVersion(), remoteVersion()
  if not rv then
    print("Could not reach GitHub to check. Try again, or 'update force'.")
    return
  end
  print(("Installed v%s, latest v%s"):format(lv or "?", rv))
  if lv and lv == rv then
    print("Already up to date.")
    return
  end
  print("New version found - updating...")
end

print("Fetching latest installer...")
if fs.exists("/install.lua") then fs.delete("/install.lua") end
local h, err = http.get(rawUrl("install.lua"), { ["Cache-Control"] = "no-cache" })
if not h then error("Could not fetch install.lua: " .. tostring(err), 0) end
local body = h.readAll(); h.close()

local f = fs.open("/install.lua", "w")
f.write(body); f.close()

shell.run("/install.lua", "update")

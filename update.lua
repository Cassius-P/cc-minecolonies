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

-- Resolve the latest commit SHA (1 API call), then fetch from SHA-pinned raw
-- (immutable: never CDN-stale, not rate-limited).
local function ghSha()
  local h = http.get(string.format("https://api.github.com/repos/%s/%s/commits/%s",
    REPO.owner, REPO.repo, REPO.branch),
    { ["Accept"] = "application/vnd.github.sha", ["User-Agent"] = "cc-minecolonies" })
  if not h then return nil end
  local s = h.readAll(); h.close(); s = s:gsub("%s+", "")
  return (#s >= 7 and #s <= 64 and s:match("^%x+$")) and s or nil
end

local REF = ghSha() or REPO.branch

local function fetch(path)
  local suffix = (REF == REPO.branch) and ("?nocache=" .. (os.epoch and os.epoch("utc") or 0)) or ""
  local h = http.get(string.format("https://raw.githubusercontent.com/%s/%s/%s/%s%s",
    REPO.owner, REPO.repo, REF, path, suffix), { ["Cache-Control"] = "no-cache" })
  if not h then return nil end
  local body = h.readAll(); h.close()
  return body
end

local function localVersion()
  if not fs.exists("/version") then return nil end
  local f = fs.open("/version", "r"); if not f then return nil end
  local v = f.readAll(); f.close()
  return (v:gsub("%s+", ""))
end

local function remoteVersion()
  local body = fetch("manifest.lua")
  if not body then return nil end
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
local body = fetch("install.lua")
if not body then error("Could not fetch install.lua", 0) end

local f = fs.open("/install.lua", "w")
f.write(body); f.close()

shell.run("/install.lua", "update")

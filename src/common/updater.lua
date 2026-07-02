----------------------------------------------------------------------------
-- common/updater.lua -- installed version + GitHub update check.
--
-- Single source of truth for the *installed* version is the /version stamp
-- written by install.lua (falls back to config.VERSION only when absent). The
-- update check compares that stamp with the version in the repo's manifest.lua,
-- fetched with cache-busting so a stale CDN copy doesn't mask a new release.
----------------------------------------------------------------------------

local M = {}

-- Installed version = /version stamp, else fallback (config.VERSION).
function M.installed(fallback)
  if fs.exists("/version") then
    local f = fs.open("/version", "r")
    if f then
      local v = f.readAll(); f.close()
      v = (v:gsub("%s+", ""))
      if v ~= "" then return v end
    end
  end
  return fallback or "?"
end

local function fetchRemoteVersion(repo)
  -- GitHub API returns current content; raw is CDN-cached ~5 min (query strings
  -- don't bust it), so it can report a stale version.
  local h = http.get(string.format("https://api.github.com/repos/%s/%s/contents/manifest.lua?ref=%s",
    repo.owner, repo.repo, repo.branch),
    { ["Accept"] = "application/vnd.github.raw", ["User-Agent"] = "cc-minecolonies" })
  if not h then
    h = http.get(string.format("https://raw.githubusercontent.com/%s/%s/%s/manifest.lua?nocache=%d",
      repo.owner, repo.repo, repo.branch, os.epoch and os.epoch("utc") or 0),
      { ["Cache-Control"] = "no-cache" })
  end
  if not h then return nil end
  local body = h.readAll(); h.close()
  local ok, mf = pcall(function() return load(body, "manifest", "t", {})() end)
  if ok and type(mf) == "table" and mf.version then return tostring(mf.version) end
  return nil
end

-- check(config) -> { available=bool, localv=string, remote=string } or nil.
function M.check(config)
  local repo = config and config.repo
  if type(repo) ~= "table" then return nil end
  local localv = M.installed(config.VERSION)
  local remote = fetchRemoteVersion(repo)
  if not remote then return nil end
  return { available = (localv ~= "?" and remote ~= localv), localv = localv, remote = remote }
end

return M

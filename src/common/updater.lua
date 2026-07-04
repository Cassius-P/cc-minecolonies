----------------------------------------------------------------------------
-- common/updater.lua -- installed version + GitHub update check.
--
-- Single source of truth for the *installed* version is the /version stamp
-- written by install.lua from manifest.version. The
-- update check compares that stamp with the version in the repo's manifest.lua,
-- fetched with cache-busting so a stale CDN copy doesn't mask a new release.
----------------------------------------------------------------------------

local M = {}

-- Installed version = /version stamp, else "?" (or an explicit fallback).
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

local function ghSha(repo)
  local h = http.get(string.format("https://api.github.com/repos/%s/%s/commits/%s",
    repo.owner, repo.repo, repo.branch),
    { ["Accept"] = "application/vnd.github.sha", ["User-Agent"] = "cc-minecolonies" })
  if not h then return nil end
  local s = h.readAll(); h.close(); s = s:gsub("%s+", "")
  return (#s >= 7 and #s <= 64 and s:match("^%x+$")) and s or nil
end

local function fetchRemoteVersion(repo)
  -- Resolve latest SHA (1 API call), read manifest from SHA-pinned raw
  -- (immutable -> always fresh). Fall back to branch raw if the API is down.
  local ref = ghSha(repo) or repo.branch
  local suffix = (ref == repo.branch) and ("?nocache=" .. (os.epoch and os.epoch("utc") or 0)) or ""
  local h = http.get(string.format("https://raw.githubusercontent.com/%s/%s/%s/manifest.lua%s",
    repo.owner, repo.repo, ref, suffix), { ["Cache-Control"] = "no-cache" })
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
  local localv = M.installed()
  local remote = fetchRemoteVersion(repo)
  if not remote then return nil end
  return { available = (localv ~= "?" and remote ~= localv), localv = localv, remote = remote }
end

return M

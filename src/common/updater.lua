----------------------------------------------------------------------------
-- common/updater.lua -- check GitHub for a newer version.
--
-- Compares the local /version stamp (written by install.lua) against the
-- version in the repo's manifest.lua. Network/parse failures return nil so the
-- indicator simply stays off when offline.
----------------------------------------------------------------------------

local M = {}

local function readLocal()
  if not fs.exists("/version") then return nil end
  local f = fs.open("/version", "r"); if not f then return nil end
  local v = f.readAll(); f.close()
  return (v:gsub("%s+", ""))
end

local function fetchRemoteVersion(repo)
  local url = string.format("https://raw.githubusercontent.com/%s/%s/%s/manifest.lua",
    repo.owner, repo.repo, repo.branch)
  local h = http.get(url)
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
  local localv = readLocal()
  local remote = fetchRemoteVersion(repo)
  if not remote then return nil end
  return { available = (localv ~= nil and remote ~= localv), localv = localv or "?", remote = remote }
end

return M

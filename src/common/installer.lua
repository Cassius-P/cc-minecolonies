----------------------------------------------------------------------------
-- common/installer.lua -- shared, UI-less install/update logic used by both
-- install.lua and update.lua so the two never diverge. Pure http + filesystem;
-- the entry scripts own the (single) Basalt UI and pass a progress callback.
----------------------------------------------------------------------------

local M = {}

-- Resolve the branch's latest commit SHA (1 API call). SHA-pinned raw is
-- immutable: never CDN-stale, not rate-limited.
local function ghSha(repo)
  local h = http.get(("https://api.github.com/repos/%s/%s/commits/%s")
    :format(repo.owner, repo.repo, repo.branch),
    { ["Accept"] = "application/vnd.github.sha", ["User-Agent"] = "cc-minecolonies" })
  if not h then return nil end
  local s = h.readAll(); h.close(); s = s:gsub("%s+", "")
  return (#s >= 7 and #s <= 64 and s:match("^%x+$")) and s or nil
end

-- explicit SHA > API SHA > branch name.
function M.resolveRef(repo, explicit)
  return explicit or ghSha(repo) or repo.branch
end

function M.fetch(repo, ref, path)
  local suffix = (ref == repo.branch) and ("?nocache=" .. (os.epoch and os.epoch("utc") or 0)) or ""
  local h = http.get(("https://raw.githubusercontent.com/%s/%s/%s/%s%s")
    :format(repo.owner, repo.repo, ref, path, suffix), { ["Cache-Control"] = "no-cache" })
  if not h then return nil end
  local body = h.readAll(); h.close()
  return body
end

function M.loadManifest(body)
  if not body then return nil end
  local ok, mf = pcall(function() return load(body, "manifest", "t", {})() end)
  if ok and type(mf) == "table" and mf.files then return mf end
  return nil
end

function M.writeFile(dst, body)
  local dir = fs.getDir(dst)
  if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local f = fs.open(dst, "w"); if not f then return false end
  f.write(body); f.close()
  return true
end

-- install(repo, ref, manifest, opts) -> { wrote, kept, failed, version }
-- opts = { preserveConfig = bool, progress = function(i, n, name) }
function M.install(repo, ref, manifest, opts)
  opts = opts or {}
  local preserve = {}
  if opts.preserveConfig then
    for _, dst in ipairs(manifest.config or {}) do preserve[dst] = true end
  end
  local wrote, kept, failed = 0, 0, {}
  local n = #manifest.files
  for i, e in ipairs(manifest.files) do
    if preserve[e.dst] and fs.exists(e.dst) then
      kept = kept + 1
    else
      local body = M.fetch(repo, ref, e.src)
      if body and M.writeFile(e.dst, body) then wrote = wrote + 1 else failed[#failed + 1] = e.dst end
    end
    if opts.progress then opts.progress(i, n, e.dst) end
  end
  for _, dst in ipairs(manifest.remove or {}) do if fs.exists(dst) then fs.delete(dst) end end
  M.writeFile("/version", tostring(manifest.version or "?"))
  return { wrote = wrote, kept = kept, failed = failed, version = manifest.version }
end

return M

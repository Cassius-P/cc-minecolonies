----------------------------------------------------------------------------
-- common/installer.lua -- shared, UI-less install/update logic used by both
-- install.lua and update.lua so the two never diverge. Pure http + filesystem;
-- the entry scripts own the (single) Basalt UI and pass a progress callback.
----------------------------------------------------------------------------

local sha1 = require("common.sha1")

local M = {}

-- git blob hash of a byte string: sha1("blob <len>\0" .. content). Matches the
-- `sha` GitHub reports per file, so an unchanged file can be detected without
-- downloading it.
function M.gitBlobSha(body)
  return sha1.hex("blob " .. #body .. "\0" .. body)
end

-- Fetch every blob's { sha, size } at `ref` in ONE git-tree API call.
-- Returns path -> { sha, size } or nil (API down, or a truncated huge tree ->
-- caller falls back to downloading everything).
function M.remoteBlobShas(repo, ref)
  local url = ("https://api.github.com/repos/%s/%s/git/trees/%s?recursive=1")
    :format(repo.owner, repo.repo, ref)
  local h = http.get(url, { ["User-Agent"] = "cc-minecolonies", ["Accept"] = "application/vnd.github+json" })
  if not h then return nil end
  local body = h.readAll(); h.close()
  local decode = textutils.unserializeJSON or textutils.unserialiseJSON
  local ok, data = pcall(decode, body)
  if not ok or type(data) ~= "table" or type(data.tree) ~= "table" or data.truncated then return nil end
  local map = {}
  for _, ent in ipairs(data.tree) do
    if ent.type == "blob" and ent.path and ent.sha then
      map[ent.path] = { sha = ent.sha, size = tonumber(ent.size) or -1 }
    end
  end
  return map
end

-- Pure-Lua sha1 is too slow to run over a large file (e.g. the ~300KB vendored
-- basalt.lua) on a CC computer, so files above this size are compared by size
-- only: a real content change to such a file virtually always changes its size.
M.HASH_MAX = 20000

-- Decide what to do with one manifest file. Pure: `localSha` is a thunk called
-- ONLY when a size match makes a content hash necessary (and the file is small
-- enough to hash cheaply). Returns "keep" (config preserved), "skip" (identical),
-- or "get" (download).
function M.decide(o)
  if o.preserve and o.exists then return "keep" end
  if not (o.diff and o.remote and o.exists) then return "get" end
  if o.localSize ~= o.remote.size then return "get" end
  if o.hashMax and o.remote.size > o.hashMax then return "skip" end   -- too big to hash: trust size
  if o.localSha() == o.remote.sha then return "skip" end
  return "get"
end

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

local function readAll(dst)
  local f = fs.open(dst, "r"); if not f then return nil end
  local b = f.readAll(); f.close(); return b
end

-- install(repo, ref, manifest, opts) -> { wrote, skipped, kept, removed, failed, version, diffed }
-- opts = { preserveConfig = bool, diff = bool, progress = function(i, n, name, action) }
--   action in "get" | "skip" | "keep" | "rm" | "fail".
-- With diff, one git-tree call yields every remote blob's sha+size; a file whose
-- local size AND git-blob sha already match is skipped (not re-downloaded).
function M.install(repo, ref, manifest, opts)
  opts = opts or {}
  local preserve = {}
  if opts.preserveConfig then
    for _, dst in ipairs(manifest.config or {}) do preserve[dst] = true end
  end
  local diff = opts.diff and true or false
  local remote = diff and M.remoteBlobShas(repo, ref) or nil
  if not remote then diff = false end   -- API down/truncated -> download everything

  local removes = {}
  for _, dst in ipairs(manifest.remove or {}) do if fs.exists(dst) then removes[#removes + 1] = dst end end
  local n = #manifest.files + #removes

  local wrote, skipped, kept, failed = 0, 0, 0, {}
  local idx = 0
  for _, e in ipairs(manifest.files) do
    idx = idx + 1
    local dst, exists = e.dst, fs.exists(e.dst)
    local action = M.decide({
      preserve = preserve[dst], diff = diff, remote = remote and remote[e.src], exists = exists,
      hashMax = M.HASH_MAX,
      localSize = exists and fs.getSize(dst) or -1,
      localSha = function() local b = readAll(dst); return b and M.gitBlobSha(b) or "" end,
    })
    if action == "keep" then kept = kept + 1
    elseif action == "skip" then skipped = skipped + 1
    else
      local body = M.fetch(repo, ref, e.src)
      if body and M.writeFile(dst, body) then wrote = wrote + 1 else action = "fail"; failed[#failed + 1] = dst end
    end
    if opts.progress then opts.progress(idx, n, dst, action) end
  end
  for _, dst in ipairs(removes) do
    idx = idx + 1
    fs.delete(dst)
    if opts.progress then opts.progress(idx, n, dst, "rm") end
  end
  M.writeFile("/version", tostring(manifest.version or "?"))
  return { wrote = wrote, skipped = skipped, kept = kept, removed = #removes,
    failed = failed, version = manifest.version, diffed = diff }
end

return M

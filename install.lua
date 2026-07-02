----------------------------------------------------------------------------
-- install.lua -- install / update the colony dashboard from GitHub.
--
--   Fresh install:   wget <raw>/install.lua install.lua  &&  install.lua
--   Update (keeps config): install.lua update    (or just run: update)
--
-- Downloads manifest.lua then every file it lists. Config targets are kept if
-- present, so local edits survive updates. Basalt is fetched first so progress
-- can be shown with a Basalt UI (falls back to plain text if it can't load).
----------------------------------------------------------------------------

-- >>> Point this at your public GitHub repo. <<<
local REPO = { owner = "Cassius-P", repo = "cc-minecolonies", branch = "main" }

-- Resolve the branch's latest commit SHA (1 API call), then fetch every file
-- from SHA-pinned raw URLs. SHA-pinned raw is immutable: never CDN-stale and not
-- rate-limited (unlike the API, which is 60 req/hr and was throttling installs).
local function ghSha()
  local h = http.get(string.format("https://api.github.com/repos/%s/%s/commits/%s",
    REPO.owner, REPO.repo, REPO.branch),
    { ["Accept"] = "application/vnd.github.sha", ["User-Agent"] = "cc-minecolonies" })
  if not h then return nil end
  local s = h.readAll(); h.close(); s = s:gsub("%s+", "")
  return (#s >= 7 and #s <= 64 and s:match("^%x+$")) and s or nil
end

local REF = refArg or ghSha() or REPO.branch  -- explicit SHA > API SHA > branch

local function fetch(path)
  local suffix = (REF == REPO.branch) and ("?nocache=" .. (os.epoch and os.epoch("utc") or 0)) or ""
  local h = http.get(string.format("https://raw.githubusercontent.com/%s/%s/%s/%s%s",
    REPO.owner, REPO.repo, REF, path, suffix), { ["Cache-Control"] = "no-cache" })
  if not h then return nil end
  local body = h.readAll(); h.close()
  return body
end

local function writeFile(dst, body)
  local dir = fs.getDir(dst)
  if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
  local f = fs.open(dst, "w")
  if not f then return false end
  f.write(body); f.close()
  return true
end

-- Args: "update" (preserve config) and/or an explicit commit SHA to fetch from
-- (skips the API entirely -- used by the manual bootstrap when rate-limited).
local isUpdate, refArg = false, nil
for _, a in ipairs({ ... }) do
  if a == "update" then isUpdate = true
  elseif type(a) == "string" and #a >= 7 and #a <= 40 and a:match("^%x+$") then refArg = a end
end

-- Manifest
local mtext = fetch("manifest.lua")
if not mtext then error("Could not fetch manifest.lua (check http + repo)", 0) end
local ok, manifest = pcall(function() return load(mtext, "manifest", "t", {})() end)
if not (ok and type(manifest) == "table" and manifest.files) then error("Malformed manifest.lua", 0) end

local preserve = {}
for _, dst in ipairs(manifest.config or {}) do preserve[dst] = true end

-- Fetch Basalt first so the installer itself can use a Basalt UI.
package.path = "/?.lua;/?/init.lua;" .. package.path
if not fs.exists("/basalt.lua") then
  local b = fetch("vendor/basalt.lua")
  if b then writeFile("/basalt.lua", b) end
end
local hasBasalt, basalt = pcall(require, "basalt")

-- The actual work (idempotent). progress(i, n, name) is optional.
local function installFiles(progress)
  local wrote, kept, failed = 0, 0, {}
  local n = #manifest.files
  for i, e in ipairs(manifest.files) do
    if preserve[e.dst] and fs.exists(e.dst) then
      kept = kept + 1
    else
      local body = fetch(e.src)
      if body and writeFile(e.dst, body) then wrote = wrote + 1 else failed[#failed + 1] = e.dst end
    end
    if progress then progress(i, n, e.dst) end
  end
  for _, dst in ipairs(manifest.remove or {}) do if fs.exists(dst) then fs.delete(dst) end end
  writeFile("/version", tostring(manifest.version or "?"))
  return wrote, kept, failed
end

local done, res = false, nil

if hasBasalt then
  pcall(function()
    local w = select(1, term.getSize())
    local main = basalt.getMainFrame()
    main:addLabel({ x = 2, y = 2, width = w - 2, foreground = colors.yellow })
      :setText((isUpdate and "Updating" or "Installing") .. " colony_dashboard")
    local status = main:addLabel({ x = 2, y = 4, width = w - 2, foreground = colors.white })
    local barW = w - 4
    local bar = main:addFrame({ x = 2, y = 6, width = barW, height = 1, backgroundColor = colors.gray })
    local fill = bar:addFrame({ x = 1, y = 1, width = 1, height = 1, backgroundColor = colors.lime })
    basalt.schedule(function()
      local wrote, kept, failed = installFiles(function(i, n, name)
        status:setText(("%d/%d  %s"):format(i, n, name))
        fill:setSize(math.max(1, math.floor(barW * i / n)), 1)
      end)
      res = { wrote = wrote, kept = kept, failed = failed }
      done = true
      status:setText(("Done. Wrote %d, kept %d. Reboot to %s.")
        :format(wrote, kept, isUpdate and "apply" or "auto-launch"))
        :setForeground(#failed > 0 and colors.red or colors.lime)
      sleep(1.5); basalt.stop()
    end)
    basalt.run()
    term.clear(); term.setCursorPos(1, 1)
  end)
end

if not done then
  io.write(isUpdate and "Updating" or "Installing")
  local wrote, kept, failed = installFiles(function() io.write(".") end)
  res = { wrote = wrote, kept = kept, failed = failed }
  print("")
end

print(("Wrote %d, kept %d config file(s), version %s"):format(res.wrote, res.kept, manifest.version or "?"))
if #res.failed > 0 then
  term.setTextColor(colors.red); print("FAILED:")
  for _, f in ipairs(res.failed) do print("  " .. f) end
  term.setTextColor(colors.white)
else
  print(isUpdate and "Update complete. Restart to apply." or "Install complete. Reboot to auto-launch.")
end

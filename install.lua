----------------------------------------------------------------------------
-- install.lua -- install / update the colony dashboard from GitHub.
--
--   Fresh install:   wget <raw>/install.lua install.lua  &&  install.lua
--   Update (keeps config): install.lua update    (or just run: update)
--
-- Downloads manifest.lua from the repo, then every file it lists, writing each
-- to its install target. Config targets are preserved if they already exist,
-- so local edits survive updates. Reboot afterwards to auto-launch.
----------------------------------------------------------------------------

-- >>> Point this at your public GitHub repo. <<<
local REPO = { owner = "Cassius-P", repo = "cc-minecolonies", branch = "main" }

local function rawUrl(path)
  return string.format("https://raw.githubusercontent.com/%s/%s/%s/%s",
    REPO.owner, REPO.repo, REPO.branch, path)
end

local function fetch(path)
  local h, err = http.get(rawUrl(path))
  if not h then return nil, err or "http error" end
  local body = h.readAll()
  h.close()
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

local mode = ({ ... })[1]      -- "update" preserves config; anything else = fresh
local isUpdate = (mode == "update")

print(("colony_dashboard %s from %s/%s@%s"):format(
  isUpdate and "update" or "install", REPO.owner, REPO.repo, REPO.branch))

-- 1. manifest
local mtext, merr = fetch("manifest.lua")
if not mtext then error("Could not fetch manifest.lua: " .. tostring(merr), 0) end
local ok, manifest = pcall(function() return load(mtext, "manifest", "t", {})() end)
if not (ok and type(manifest) == "table" and manifest.files) then
  error("Malformed manifest.lua", 0)
end

local preserve = {}
for _, dst in ipairs(manifest.config or {}) do preserve[dst] = true end

-- 2. files
local wrote, kept, failed = 0, 0, {}
for _, entry in ipairs(manifest.files) do
  if preserve[entry.dst] and fs.exists(entry.dst) then
    kept = kept + 1
  else
    local body, ferr = fetch(entry.src)
    if body and writeFile(entry.dst, body) then
      wrote = wrote + 1
      io.write(".")
    else
      failed[#failed + 1] = entry.dst .. " (" .. tostring(ferr) .. ")"
    end
  end
end
print("")

-- 3. removals (files dropped since a previous version)
for _, dst in ipairs(manifest.remove or {}) do
  if fs.exists(dst) then fs.delete(dst) end
end

-- 4. version stamp
writeFile("/version", tostring(manifest.version or "?"))

-- 5. summary
print(("Wrote %d, kept %d config file(s), version %s"):format(wrote, kept, manifest.version or "?"))
if #failed > 0 then
  term.setTextColor(colors.red)
  print("FAILED:")
  for _, f in ipairs(failed) do print("  " .. f) end
  term.setTextColor(colors.white)
else
  print(isUpdate and "Update complete. Restart to apply." or "Install complete. Reboot to auto-launch.")
end

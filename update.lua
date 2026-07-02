----------------------------------------------------------------------------
-- update.lua -- pull the latest dashboard from GitHub, preserving config.
--
-- Re-downloads install.lua (which carries the current file manifest logic) and
-- runs it in update mode. One downloader, no duplicated install logic.
----------------------------------------------------------------------------

-- >>> Keep in sync with install.lua's REPO. <<<
local REPO = { owner = "Cassius-P", repo = "cc-minecolonies", branch = "main" }

local url = string.format("https://raw.githubusercontent.com/%s/%s/%s/install.lua",
  REPO.owner, REPO.repo, REPO.branch)

print("Fetching latest installer...")
if fs.exists("/install.lua") then fs.delete("/install.lua") end

local h, err = http.get(url)
if not h then error("Could not fetch install.lua: " .. tostring(err), 0) end
local body = h.readAll(); h.close()

local f = fs.open("/install.lua", "w")
f.write(body); f.close()

shell.run("/install.lua", "update")

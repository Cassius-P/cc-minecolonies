----------------------------------------------------------------------------
-- ui/sections/jobskills.lua -- every job and its two wanted skills.
--
-- Lists all known jobs; the primary skill (counts double toward level-up) and
-- the secondary skill are colour-coded differently. Jobs whose building exists
-- in the colony (worker or not) are highlighted with a marker + bright name.
-- Hidden by default.
----------------------------------------------------------------------------

local draw   = require("ui.draw")
local theme  = require("ui.theme")
local util   = require("common.util")
local skills = require("colony.skills")
local C = theme.C
local cap = util.capitalize

local M = {}
M.title = "Job Skills"

local ALL  -- sorted list of every job key (cached)
local function allJobs()
  if ALL then return ALL end
  ALL = {}
  for k in pairs(skills.JOB_SKILLS) do ALL[#ALL + 1] = k end
  table.sort(ALL)
  return ALL
end

function M.draw(x, y, w, h, screen, d)
  local jobs = allJobs()
  local present = {}
  for _, jk in ipairs(d.jobTypes or {}) do present[jk] = true end

  local cx, cy, cw, ch = draw.card(x, y, w, h, string.format("JOB SKILLS (%d/%d)", #(d.jobTypes or {}), #jobs))
  screen.scroll = draw.scrollArrows("jobskills", x, y, w, #jobs, ch, screen.scroll)
  local off = screen.scroll.jobskills or 0
  for i = 1, ch do
    local jk = jobs[i + off]
    if not jk then break end
    local sk = skills.JOB_SKILLS[jk]
    local ry = cy + i - 1
    local here = present[jk]
    draw.put(cx, ry, (here and "\7 " or "  ") .. cap(jk), here and C.text or C.dim, C.card)
    if sk then
      local p, s = sk[1], sk[2]
      local seg = #p + 3 + #s
      local sx = cx + cw - seg
      if sx > cx + #cap(jk) then
        draw.put(sx, ry, p, C.good, C.card)          -- primary (double weight)
        draw.put(sx + #p, ry, " / ", C.dim, C.card)
        draw.put(sx + #p + 3, ry, s, C.accent2, C.card)  -- secondary
      end
    end
  end
end

return M

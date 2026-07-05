----------------------------------------------------------------------------
-- ui/sections/jobskills.lua -- every job and its two wanted skills, as a
-- 3-column table (Job | Primary | Secondary).
--
-- Primary (counts double toward level-up) and secondary skills are colour-coded
-- differently. Jobs whose building exists in the colony (worker or not) are
-- highlighted with a marker + bright name. Hidden by default.
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

local trunc = require("ui.format").trunc

function M.draw(x, y, w, h, screen, d)
  local jobs = allJobs()
  local present = {}
  for _, jk in ipairs(d.jobTypes or {}) do present[jk] = true end

  local cx, cy, cw, ch = draw.card(x, y, w, h, string.format("JOB SKILLS (%d/%d)", #(d.jobTypes or {}), #jobs))

  -- Three columns: Job | Primary | Secondary
  local jobW = math.max(6, math.floor(cw * 0.42))
  local colW = math.max(4, math.floor((cw - jobW) / 2))
  local pX = cx + jobW
  local sX = pX + colW

  -- Header row
  draw.put(cx, cy, "Job", C.dim, C.card)
  draw.put(pX, cy, "Primary", C.dim, C.card)
  draw.put(sX, cy, "Secondary", C.dim, C.card)

  local rows = ch - 1
  if rows < 1 then return end
  screen.scroll = draw.scrollArrows("jobskills", x, y, w, #jobs, rows, screen.scroll)
  local off = screen.scroll.jobskills or 0
  for i = 1, rows do
    local jk = jobs[i + off]
    if not jk then break end
    local sk = skills.JOB_SKILLS[jk]
    local ry = cy + i
    local here = present[jk]
    draw.put(cx, ry, trunc((here and "\7 " or "  ") .. cap(jk), jobW - 1), here and C.text or C.dim, C.card)
    if sk then
      draw.put(pX, ry, trunc(sk[1], colW - 1), C.good, C.card)      -- primary
      draw.put(sX, ry, trunc(sk[2], colW - 1), C.accent2, C.card)   -- secondary
    end
  end
end

return M

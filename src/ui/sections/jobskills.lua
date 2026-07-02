----------------------------------------------------------------------------
-- ui/sections/jobskills.lua -- the two skills each job in the colony wants
-- (primary counts double toward level-up). Hidden by default.
----------------------------------------------------------------------------

local draw   = require("ui.draw")
local theme  = require("ui.theme")
local util   = require("common.util")
local skills = require("colony.skills")
local C = theme.C
local cap = util.capitalize

local M = {}
M.title = "Job Skills"

function M.draw(x, y, w, h, screen, d)
  local jobs = d.jobTypes or {}
  local cx, cy, cw, ch = draw.card(x, y, w, h, string.format("JOB SKILLS (%d)", #jobs))
  screen.scroll = draw.scrollArrows("jobskills", x, y, w, #jobs, ch, screen.scroll)
  if #jobs == 0 then draw.put(cx, cy, "No jobs found.", C.dim, C.card); return end
  local off = screen.scroll.jobskills or 0
  for i = 1, ch do
    local jk = jobs[i + off]
    if not jk then break end
    local sk = skills.JOB_SKILLS[jk]
    local ry = cy + i - 1
    draw.put(cx, ry, cap(jk), C.accent2, C.card)
    if sk then
      local s = sk[1] .. " / " .. sk[2]
      draw.put(cx + cw - #s, ry, s, C.text, C.card)
    end
  end
end

return M

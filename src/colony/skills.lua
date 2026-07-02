----------------------------------------------------------------------------
-- colony/skills.lua -- job/skill knowledge + citizen scoring.
--
-- JOB_SKILLS maps the building `type` the colony_integrator reports to that
-- job's {primary, secondary} skills. Verified against minecolonies.com/wiki
-- (2026-07); the primary skill counts double toward level-up, so the
-- primary/secondary ORDER matters. Aliases resolve both building-type and
-- job-name forms.
----------------------------------------------------------------------------

local M = {}

M.REPLACE_MARGIN   = 3
M.PRIMARY_WEIGHT   = 1.0
M.SECONDARY_WEIGHT = 0.5
M.MAX_SUGGESTIONS  = 60

M.JOB_SKILLS = {
  builder      = { "Adaptability", "Athletics" },
  deliveryman  = { "Agility", "Adaptability" }, courier = { "Agility", "Adaptability" },
  farmer       = { "Stamina", "Athletics" },
  fisherman    = { "Focus", "Agility" },
  lumberjack   = { "Strength", "Focus" }, forester = { "Strength", "Focus" },
  miner        = { "Strength", "Stamina" },
  quarry       = { "Strength", "Stamina" }, quarrier = { "Strength", "Stamina" },
  smeltery     = { "Athletics", "Strength" }, smelter = { "Athletics", "Strength" },
  composter    = { "Stamina", "Athletics" },
  cook         = { "Adaptability", "Knowledge" }, restaurant = { "Adaptability", "Knowledge" },
  baker        = { "Knowledge", "Dexterity" }, bakery = { "Knowledge", "Dexterity" },
  cowboy       = { "Athletics", "Stamina" },
  shepherd     = { "Focus", "Strength" },
  swineherd    = { "Athletics", "Stamina" },        -- unverified (wiki 404); pig herder
  chickenherder = { "Adaptability", "Agility" }, chickenherd = { "Adaptability", "Agility" },
  rabbithutch  = { "Agility", "Athletics" }, rabbitherd = { "Agility", "Athletics" },
  beekeeper    = { "Dexterity", "Adaptability" }, apiary = { "Dexterity", "Adaptability" },
  knight       = { "Adaptability", "Stamina" },
  archer       = { "Agility", "Adaptability" },
  guardtower   = { "Adaptability", "Stamina" },     -- default knight; may be a ranger
  barracks     = { "Adaptability", "Stamina" },
  blacksmith   = { "Strength", "Focus" },
  stonemason   = { "Creativity", "Dexterity" },
  sawmill      = { "Knowledge", "Dexterity" }, carpenter = { "Knowledge", "Dexterity" },
  fletcher     = { "Dexterity", "Creativity" },
  glassblower  = { "Creativity", "Focus" },
  dyer         = { "Creativity", "Dexterity" },
  concretemixer = { "Stamina", "Dexterity" },
  sifter       = { "Focus", "Strength" },
  plantation   = { "Agility", "Dexterity" }, planter = { "Agility", "Dexterity" },
  crusher      = { "Stamina", "Strength" },
  enchanter    = { "Mana", "Knowledge" },
  university   = { "Knowledge", "Mana" }, researcher = { "Knowledge", "Mana" },
  hospital     = { "Mana", "Knowledge" }, healer = { "Mana", "Knowledge" },
  netherworker = { "Adaptability", "Strength" },
  mechanic     = { "Knowledge", "Agility" },
  druid        = { "Mana", "Focus" },
  florist      = { "Dexterity", "Agility" }, flowershop = { "Dexterity", "Agility" }, -- unverified
}

-- Buildings whose worker capacity scales with level (guards, couriers). The
-- API does not expose capacity, so it is configured here; default is 1.
local JOB_MAX_SLOTS = {
  deliveryman = function(l) return math.max(1, l or 1) end,
  courier     = function(l) return math.max(1, l or 1) end,
  guardtower  = function(l) return math.max(1, l or 1) end,
  barracks    = function(l) return math.max(1, l or 1) end,
  knight      = function(l) return math.max(1, l or 1) end,
  archer      = function(l) return math.max(1, l or 1) end,
}

function M.maxSlotsFor(t, level)
  local v = JOB_MAX_SLOTS[t]
  if type(v) == "function" then return v(level or 1) end
  if type(v) == "number" then return v end
  return 1
end

function M.skillLevel(c, name)
  local sk = c.skills; if not sk then return 0 end
  local v = sk[name]
  if type(v) == "table" then return v.level or 0 end
  if type(v) == "number" then return v end
  return 0
end

function M.scoreFor(c, p, s)
  return M.skillLevel(c, p) * M.PRIMARY_WEIGHT + M.skillLevel(c, s) * M.SECONDARY_WEIGHT
end

function M.isUnemployed(c)
  if c.isChild == "child" or c.isChild == true then return false end
  local w = c.work
  return not (type(w) == "table" and w.type)
end

return M

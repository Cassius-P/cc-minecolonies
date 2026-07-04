-- Characterization tests for colony/skills.lua (pure scoring + data).
local t      = require("helper")
local skills = require("colony.skills")

t.case("skillLevel handles table / number / missing")
local c = { skills = { Adaptability = { level = 10 }, Athletics = 4 } }
t.eq(skills.skillLevel(c, "Adaptability"), 10, "table {level=}")
t.eq(skills.skillLevel(c, "Athletics"), 4, "bare number")
t.eq(skills.skillLevel(c, "Focus"), 0, "missing skill")
t.eq(skills.skillLevel({}, "Focus"), 0, "no skills table")

t.case("scoreFor = primary*1.0 + secondary*0.5 (order matters)")
t.near(skills.scoreFor(c, "Adaptability", "Athletics"), 10 + 4 * 0.5)   -- 12
t.near(skills.scoreFor(c, "Athletics", "Adaptability"), 4 + 10 * 0.5)   -- 9
t.ne(skills.scoreFor(c, "Adaptability", "Athletics"),
     skills.scoreFor(c, "Athletics", "Adaptability"), "swap changes score")

t.case("maxSlotsFor: scaling jobs clamp 1..5, default 1")
t.eq(skills.maxSlotsFor("university", 3), 3)
t.eq(skills.maxSlotsFor("university", 9), 5, "clamp high")
t.eq(skills.maxSlotsFor("university", 0), 1, "clamp low")
t.eq(skills.maxSlotsFor("builder", 5), 1, "non-scaling default 1")
t.eq(skills.maxSlotsFor("builder"), 1, "nil level default 1")

t.case("isUnemployed")
t.truthy(skills.isUnemployed({ }), "no work -> idle")
t.truthy(skills.isUnemployed({ work = {} }), "work with no type -> idle")
t.falsy(skills.isUnemployed({ work = { type = "builder" } }), "has job")
t.falsy(skills.isUnemployed({ isChild = "child" }), "child not idle")
t.falsy(skills.isUnemployed({ isChild = true }), "child(bool) not idle")

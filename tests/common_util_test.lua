-- Characterization tests for common/util.lua (pure helpers).
local t    = require("helper")
local util = require("common.util")

t.case("jobKey strips namespace + trailing digits")
t.eq(util.jobKey("minecolonies:builder2"), "builder")
t.eq(util.jobKey("Guard_Tower"), "guardtower")
t.eq(util.jobKey("minecraft:oak_planks"), "oakplanks")

t.case("jobKey non-string -> nil")
t.eq(util.jobKey(123), nil)
t.eq(util.jobKey(nil), nil)

t.case("capitalize")
t.eq(util.capitalize("hi"), "Hi")
t.eq(util.capitalize(""), "")
t.eq(util.capitalize("Already"), "Already")

t.case("trimLead / lastWord")
t.eq(util.trimLead("   x y"), "x y")
t.eq(util.trimLead(nil), "")
t.eq(util.lastWord("a b c"), "c")

t.case("locStr")
t.eq(util.locStr({ x = 1, y = 2, z = 3 }), "1, 2, 3")
t.eq(util.locStr("nope"), "unknown")

t.case("deepCopy is independent")
local src = { a = 1, b = { c = 2 } }
local cp = util.deepCopy(src)
cp.b.c = 99
t.eq(src.b.c, 2, "original untouched")
t.eq(cp.b.c, 99)
t.eq(util.deepCopy(5), 5, "non-table passthrough")

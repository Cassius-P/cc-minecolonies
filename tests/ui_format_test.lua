-- Tests for ui/format.lua text helpers.
local t      = require("helper")
local format = require("ui.format")

t.case("trunc")
do
  t.eq(format.trunc("hello", 3), "hel")
  t.eq(format.trunc("hi", 5), "hi", "shorter than n -> unchanged")
  t.eq(format.trunc("hello", 5), "hello", "equal length -> unchanged")
  t.eq(format.trunc("hello", 0), "", "zero width -> empty")
  t.eq(format.trunc("hello", -2), "", "negative width -> empty (guarded)")
end

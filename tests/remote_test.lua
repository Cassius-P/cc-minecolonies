-- Tests for common/remote.lua pure helpers.
local t      = require("helper")
local remote = require("common.remote")

t.case("snapshot shape")
do
  local snap = remote.snapshot({ a = 1 }, "Home", 7)
  t.eq(snap.kind, remote.SNAPSHOT)
  t.eq(snap.name, "Home")
  t.eq(snap.id, 7)
  t.eq(snap.data.a, 1)
end

t.case("serializable")
do
  t.truthy(remote.serializable({ x = 1, y = "s", z = { 1, 2, { w = true } } }), "plain nested table")
  t.falsy(remote.serializable({ f = function() end }), "function is not serializable")
  t.falsy(remote.serializable({ nested = { bad = print } }), "nested function is not serializable")
  t.truthy(remote.serializable(42), "scalar")
end

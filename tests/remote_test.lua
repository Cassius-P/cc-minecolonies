-- Tests for common/remote.lua pure helpers.
local t      = require("helper")
local remote = require("common.remote")

t.case("snapshot shape")
do
  local snap = remote.snapshot({ a = 1 }, "Home", 7)
  t.eq(snap.proto, remote.PROTO)
  t.eq(snap.kind, remote.SNAPSHOT)
  t.eq(snap.name, "Home")
  t.eq(snap.id, 7)
  t.eq(snap.data.a, 1)
end

t.case("hello shape")
do
  local h = remote.hello()
  t.eq(h.proto, remote.PROTO)
  t.eq(h.kind, remote.HELLO)
end

t.case("validChannel")
do
  t.truthy(remote.validChannel(10000), "min")
  t.truthy(remote.validChannel(42731), "mid")
  t.truthy(remote.validChannel(65535), "max")
  t.falsy(remote.validChannel(9999), "below min")
  t.falsy(remote.validChannel(65536), "above max")
  t.falsy(remote.validChannel(12345.5), "non-integer")
  t.falsy(remote.validChannel("42731"), "string")
  t.falsy(remote.validChannel(nil), "nil")
end

t.case("channelOr")
do
  t.eq(remote.channelOr(42731), 42731, "valid passes through")
  t.eq(remote.channelOr(99999), remote.DEFAULT_CH, "out of range -> default")
  t.eq(remote.channelOr(nil), remote.DEFAULT_CH, "nil -> default")
end

t.case("isOurs")
do
  t.truthy(remote.isOurs({ proto = remote.PROTO, kind = remote.HELLO }))
  t.falsy(remote.isOurs({ proto = "other" }), "wrong proto")
  t.falsy(remote.isOurs("nope"), "not a table")
end

t.case("serializable")
do
  t.truthy(remote.serializable({ x = 1, y = "s", z = { 1, 2, { w = true } } }), "plain nested table")
  t.falsy(remote.serializable({ f = function() end }), "function is not serializable")
  t.falsy(remote.serializable({ nested = { bad = print } }), "nested function is not serializable")
  t.truthy(remote.serializable(42), "scalar")
end

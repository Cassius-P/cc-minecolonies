-- Tests for app/store.lua (pure state container).
local t     = require("helper")
local store = require("app.store")

local function newStore() return store.new({ refreshSeconds = 5, theme = "deepslate" }) end

t.case("initial state")
do
  local s = newStore()
  t.eq(s.countdown, 5)
  t.eq(s.theme, "deepslate")
  t.truthy(s.booting)
  t.falsy(s.quit)
  t.falsy(s.needScan)
end

t.case("setData / setScanError reset scan + countdown")
do
  local s = newStore()
  s.countdown = 1; s.needScan = true
  s.setData({ x = 1 }, "msg")
  t.eq(s.data.x, 1)
  t.eq(s.msg, "msg")
  t.falsy(s.needScan)
  t.eq(s.countdown, 5, "re-armed")

  s.needScan = true
  s.setScanError("boom")
  t.eq(s.msg, "boom")
  t.falsy(s.needScan)
  t.eq(s.countdown, 5)
end

t.case("markScan / tick")
do
  local s = newStore()
  s.markScan(); t.truthy(s.needScan)
  t.eq(s.tick(), 4)
  t.eq(s.tick(), 3)
end

t.case("update mutators")
do
  local s = newStore()
  s.setUpdate({ available = true })
  t.truthy(s.update.available); t.falsy(s.checkFailed)
  s.setUpdateFailed(); t.truthy(s.checkFailed)
  s.setChecking(true); t.truthy(s.checking)
  s.beginInstall(); t.truthy(s.pendingInstall)
end

t.case("dump mutators")
do
  local s = newStore()
  s.beginDump()
  t.truthy(s.dumping); t.eq(s.dumpLink, nil); t.eq(s.dumpError, nil)
  s.finishDump("http://x", nil)
  t.falsy(s.dumping); t.eq(s.dumpLink, "http://x")
  s.beginDump(); s.finishDump(nil, "err")
  t.eq(s.dumpError, "err")
end

t.case("boot + theme + quit")
do
  local s = newStore()
  s.endBoot(); t.falsy(s.booting)
  s.cancelBooting(); t.truthy(s.cancelBoot)
  s.setTheme("basalt"); t.eq(s.theme, "basalt")
  s.setQuit(); t.truthy(s.quit)
end

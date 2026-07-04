----------------------------------------------------------------------------
-- tests/stubs.lua -- fake CC:Tweaked globals so pure modules that reference
-- them at call time (e.g. requests.categorize -> colors.white) load and run
-- under plain luajit. Values mirror CC's real `colors` bit constants so any
-- assertion on a color/token int matches in-game.
----------------------------------------------------------------------------

if not _G.colors then
  -- CC standard order: white=1, orange=2, ... black=32768 (2^(i-1)).
  local names = {
    "white", "orange", "magenta", "lightBlue", "yellow", "lime", "pink", "gray",
    "lightGray", "cyan", "purple", "blue", "brown", "green", "red", "black",
  }
  local colors = {}
  for i, n in ipairs(names) do colors[n] = 2 ^ (i - 1) end
  _G.colors = colors
end

_G.sleep = _G.sleep or function() end

_G.os = _G.os or {}
_G.os.epoch = _G.os.epoch or function() return 0 end

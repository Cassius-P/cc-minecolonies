----------------------------------------------------------------------------
-- ui/loader.lua -- Basalt loading overlay shown on the computer + monitors at
-- startup (until the first scan) and while updating.
--
-- build() adds a high-z overlay frame to each given frame with a centered,
-- animated label. show()/hide() toggle them; tick() advances the dots.
----------------------------------------------------------------------------

local M = {}

function M.build(frames)
  local overlays = {}
  for _, fr in ipairs(frames) do
    local w = fr.get("width")
    local h = fr.get("height")
    local of = fr:addFrame({ x = 1, y = 1, width = w, height = h, backgroundColor = colors.black })
    of.set("z", 900); of.set("visible", false)
    local y = math.max(1, math.floor(h / 2))
    local lbl = of:addLabel({ x = 1, y = y, width = w, foreground = colors.white })
    overlays[#overlays + 1] = { of = of, lbl = lbl, w = w, y = y }
  end

  local dots, text = 0, "Loading"
  local function paint()
    local suffix = string.rep(".", dots % 4)
    for _, o in ipairs(overlays) do
      local s = text .. suffix
      local x = math.max(1, math.floor((o.w - #s) / 2) + 1)
      o.lbl:setPosition(x, o.y); o.lbl:setText(s)
    end
  end

  return {
    show = function(t) if t then text = t end
      for _, o in ipairs(overlays) do o.of.set("visible", true) end; paint() end,
    hide = function() for _, o in ipairs(overlays) do o.of.set("visible", false) end end,
    tick = function() dots = dots + 1; paint() end,
  }
end

return M

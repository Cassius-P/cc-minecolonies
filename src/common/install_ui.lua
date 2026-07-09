----------------------------------------------------------------------------
-- common/install_ui.lua -- apt/pacman-style install screen on ONE Basalt frame.
--
-- Fixed heading (top), a log that grows a line per file and auto-scrolls to the
-- newest, and a progress bar + status pinned to the bottom. Shared by install.lua
-- and update.lua so the two never diverge.
--
-- run(opts) -> res, where opts = {
--   title    = string,                       -- heading line 1
--   subtitle = string|nil,                    -- heading line 2 (e.g. v-> v)
--   install  = function(progress) -> res,     -- calls progress(i,n,name,action)
--   doneDelay = number|nil,                    -- seconds to hold the final frame
-- }
-- Returns the installer's `res` so the caller decides whether to reboot.
----------------------------------------------------------------------------

local M = {}

local ACTION = {
  get  = { "get ", colors.white },
  skip = { "skip", colors.gray },
  keep = { "keep", colors.lightGray },
  rm   = { "rm  ", colors.orange },
  fail = { "FAIL", colors.red },
}

function M.run(opts)
  local basalt = require("basalt")
  local W, H = term.getSize()
  local main = basalt.getMainFrame()
  main.set("background", colors.black)

  main:addLabel({ x = 2, y = 1, width = W - 2, background = colors.black, foreground = colors.yellow })
    :setText(opts.title or "colony_dashboard")
  if opts.subtitle then
    main:addLabel({ x = 2, y = 2, width = W - 2, background = colors.black, foreground = colors.orange })
      :setText(opts.subtitle)
  end

  -- Log region: rows 4 .. H-2. One reusable label per visible row; the tail of
  -- the line buffer is painted each refresh (so it always shows the newest).
  local top, bottom = 4, H - 2
  local rows = {}
  for y = top, bottom do
    rows[#rows + 1] = main:addLabel({ x = 2, y = y, width = W - 2,
      background = colors.black, foreground = colors.white }):setText("")
  end
  local nRows = #rows
  local log = {}
  local function repaint()
    local start = math.max(0, #log - nRows)
    for k = 1, nRows do
      local e = log[start + k]
      if e then rows[k]:setText(e.text):setForeground(e.color)
      else rows[k]:setText(""):setForeground(colors.white) end
    end
  end

  local barW = W - 4
  local barBg = main:addFrame({ x = 2, y = H - 1, width = barW, height = 1, background = colors.gray })
  local fill = barBg:addFrame({ x = 1, y = 1, width = 1, height = 1, background = colors.lime })
  local status = main:addLabel({ x = 2, y = H, width = W - 2, background = colors.black, foreground = colors.lightGray })

  local res
  basalt.schedule(function()
    res = opts.install(function(i, n, name, action)
      local a = ACTION[action] or ACTION.get
      log[#log + 1] = { text = a[1] .. " " .. tostring(name), color = a[2] }
      repaint()
      fill:setSize(math.max(1, math.floor(barW * i / math.max(1, n))), 1)
      status:setText(("%d/%d"):format(i, n))
    end) or {}

    local ok = #(res.failed or {}) == 0
    if ok then
      status:setText(("Done. %d written, %d unchanged%s.  v%s"):format(
        res.wrote or 0, res.skipped or 0,
        (res.removed and res.removed > 0) and (", " .. res.removed .. " removed") or "",
        res.version or "?")):setForeground(colors.lime)
    else
      status:setText(("Done with %d error(s)."):format(#res.failed)):setForeground(colors.red)
    end
    sleep(opts.doneDelay or 2)
    basalt.stop()
  end)
  basalt.run()
  term.clear(); term.setCursorPos(1, 1)
  return res
end

return M

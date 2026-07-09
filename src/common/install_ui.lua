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

  main:addLabel({ x = 2, y = 1, width = W - 2, background = colors.black, foreground = colors.yellow })
    :setText(opts.title or "colony_dashboard")
  main:addLabel({ x = 2, y = 2, width = W - 2, background = colors.black, foreground = colors.orange })
    :setText(opts.subtitle or "")

  -- Log region: rows 4 .. H-2. One reusable label per visible row; the tail of
  -- the line buffer is painted each refresh (so it always shows the newest).
  local rows = {}
  for y = 4, H - 2 do
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

  -- Native Basalt progress bar + a status line (both explicitly initialised so a
  -- default "Label" can never show through while work is in progress).
  local bar = main:addProgressBar({ x = 2, y = H - 1, width = W - 4, height = 1,
    progress = 0, progressColor = colors.lime, background = colors.gray, direction = "right" })
  local status = main:addLabel({ x = 2, y = H, width = W - 2,
    background = colors.black, foreground = colors.lightGray }):setText("Preparing...")

  local res
  basalt.schedule(function()
    local ok, err = pcall(function()
      res = opts.install(function(i, n, name, action)
        local a = ACTION[action] or ACTION.get
        log[#log + 1] = { text = a[1] .. " " .. tostring(name), color = a[2] }
        repaint()
        bar.set("progress", math.max(0, math.min(100, math.floor(100 * i / math.max(1, n) + 0.5))))
        status:setText(("%d/%d"):format(i, n)):setForeground(colors.lightGray)
        sleep(0)   -- yield so Basalt renders this file before the next one
      end)
    end)
    res = res or {}
    if not ok then
      res.failed = res.failed or {}
      res.failed[#res.failed + 1] = tostring(err)   -- so the caller does NOT reboot
      status:setText("Error: " .. tostring(err)):setForeground(colors.red)
    elseif #(res.failed or {}) == 0 then
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

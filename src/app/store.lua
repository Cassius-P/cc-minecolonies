----------------------------------------------------------------------------
-- app/store.lua -- explicit application/session state container.
--
-- Replaces the ad-hoc flat `state` grab-bag that ui/app.lua used to declare
-- inline and poke from a dozen places. The RETURNED table still exposes the
-- same flat field names the presentation reads (layout.render + the admin tabs
-- read state.data / state.countdown / state.dumping / ...), so those callers are
-- unchanged; what moves here is the SCHEMA (documented in one place) and the
-- MUTATION API (named methods), so nothing writes state fields by hand.
--
-- Fields (read by presentation):
--   data, msg, countdown, needScan         -- colony scan
--   update, checking, checkFailed, pendingInstall  -- update check/install
--   dumping, dumpLink, dumpError           -- data dump
--   booting, cancelBoot                    -- boot splash / cancel window
--   theme, quit                            -- misc
----------------------------------------------------------------------------

local M = {}

function M.new(config)
  -- Read live so the admin "polling" edit takes effect on the next re-arm.
  local function refresh() return config.refreshSeconds or 5 end

  local s = {
    data = nil, msg = "", countdown = refresh(), needScan = false,
    armAt = os.epoch("utc"),   -- start of the current scan interval (footer progress bar)
    update = nil, checking = false, checkFailed = false, pendingInstall = false,
    dumping = false, dumpLink = nil, dumpError = nil,
    booting = true, cancelBoot = false,
    theme = config.theme, quit = false,
  }

  -- Colony scan ----------------------------------------------------------
  -- Re-arm the interval: start the countdown/progress bar NOW. Called at scan
  -- START (so scan latency doesn't stall the bar at full) and each interval the
  -- scan is deferred (e.g. a modal is open) so the bar keeps cycling.
  function s.rearm() s.countdown, s.armAt = refresh(), os.epoch("utc") end
  function s.setData(data, msg) s.data, s.msg, s.needScan = data, msg, false end
  function s.setScanError(msg) s.msg, s.needScan = msg, false end
  function s.markScan() s.needScan = true end
  function s.tick() s.countdown = s.countdown - 1; return s.countdown end

  -- Update check / install ----------------------------------------------
  function s.setUpdate(info) s.update, s.checkFailed = info, false end
  function s.setUpdateFailed() s.checkFailed = true end
  function s.setChecking(v) s.checking = v end
  function s.beginInstall() s.pendingInstall = true end

  -- Data dump ------------------------------------------------------------
  function s.beginDump() s.dumping, s.dumpLink, s.dumpError = true, nil, nil end
  function s.finishDump(link, err) s.dumping, s.dumpLink, s.dumpError = false, link, err end

  -- Boot splash ----------------------------------------------------------
  function s.endBoot() s.booting = false end
  function s.cancelBooting() s.cancelBoot = true end

  -- Misc -----------------------------------------------------------------
  function s.setTheme(name) s.theme = name end
  function s.setQuit() s.quit = true end

  return s
end

return M

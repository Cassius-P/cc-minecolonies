----------------------------------------------------------------------------
-- config.lua -- default configuration for the colony dashboard.
--
-- This file is NEVER overwritten by the updater once it exists on the
-- computer, so local edits survive updates. Delete it (or run a fresh
-- install) to regenerate defaults.
----------------------------------------------------------------------------

local M = {}

M.VERSION = "3.36"

M.config = {
  theme          = "deepslate",   -- deepslate | smooth_stone | sandstone | basalt (GLOBAL)
  refreshSeconds = 5,

  -- Source repo for the "update available" check on the computer screen.
  -- Keep in sync with REPO in install.lua / update.lua.
  repo = { owner = "Cassius-P", repo = "cc-minecolonies", branch = "main" },

  -- Optional peripheral overrides. Leave nil to auto-discover across the
  -- wired-modem network. Set a network name to pin a specific remote (see the
  -- computer terminal's peripheral list, or `peripheral.getNames()`).
  peripherals = {
    colony  = nil,   -- e.g. "colonyIntegrator_0"
    bridge  = nil,   -- e.g. "meBridge_1"  (ME/RS bridge)
    storage = nil,   -- e.g. "minecraft:barrel_3" (export target inventory)
    -- monitors: nil = use every monitor found. Otherwise a list of network
    -- names, bound to screens[] in order.
    monitors = nil,
  },

  -- One entry per monitor (bound in detection order, or pin with `monitor=`).
  -- screens[1] must stand alone for single-monitor setups.
  --
  -- Layout is TWO columns, each an ordered list of sections. Column width is
  -- shared by the number of NON-EMPTY columns (an empty column disappears and
  -- the other takes full width); row height in a column is shared by the
  -- number of enabled sections in it. Every section lives in one column so it
  -- has a home when enabled; `enabled` controls what is shown. Rearrange live
  -- on the monitor with EDIT (tap-move), or edit here.
  screens = {
    { -- monitor 1: full overview (self-sufficient)
      -- monitor = "monitor_0",
      enabled = { status = true, workforce = true, workers = true,
        orders = true, requests = true, legend = true },
      columns = {
        { "status", "workforce", "orders", "legend", "jobskills" },
        { "workers", "requests" },
      },
    },
    { -- monitor 2 (if present): logistics focus (overview sections disabled)
      enabled = { status = false, workforce = false, workers = false,
        orders = true, requests = true, legend = true },
      columns = {
        { "requests", "orders", "legend" },
        { "status", "workforce", "workers", "jobskills" },
      },
    },
  },

  -- Suggestion thresholds (skill-gap needed before a move is suggested).
  -- Higher = fewer, only-big-win suggestions; 0 = suggest every improvement.
  -- Adjustable live on the computer's Settings tab.
  suggestions = {
    replaceMargin  = 1,   -- idle citizen must beat a full-hut worker by this much
    reassignMargin = 1,   -- employed citizen must improve by this much to move jobs
  },

  autofulfill = {
    enabled          = true,
    pauseUnderAttack = true,
    minHappiness     = 0,          -- 0 = no happiness gate
    craftMissing     = true,
    equipment        = true,
    equipmentLevel   = "Iron",     -- "Iron" | "Diamond" | "Iron and Diamond"
    skipItems        = { "minecraft:enchanted_book" },
  },

  logToFile = false,               -- write warnings to colony_dashboard_log.txt
}

return M

----------------------------------------------------------------------------
-- config.lua -- default configuration for the colony dashboard.
--
-- This file is NEVER overwritten by the updater once it exists on the
-- computer, so local edits survive updates. Delete it (or run a fresh
-- install) to regenerate defaults.
----------------------------------------------------------------------------

local M = {}

M.VERSION = "3.0"

M.config = {
  theme          = "deepslate",   -- deepslate | smooth_stone | sandstone | basalt (GLOBAL)
  refreshSeconds = 5,

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
  screens = {
    { -- monitor 1: full overview (self-sufficient)
      -- monitor = "monitor_0",
      enabled = { status = true, workforce = true, workers = true,
        orders = true, requests = true, legend = true },
      layout = {
        dir = "row",
        { dir = "col", flex = 38, min = 20,
          { section = "status",    flex = 8, min = 7, max = 9 },
          { section = "workforce", flex = 7, min = 6, max = 8 },
          { section = "orders",    flex = 10, min = 4 },
          { section = "legend",    flex = 9, min = 4 },
        },
        { dir = "col", flex = 62, min = 24,
          { section = "workers",  flex = 50, min = 6 },
          { section = "requests", flex = 50, min = 6 },
        },
      },
    },
    { -- monitor 2 (if present): logistics focus
      enabled = { requests = true, orders = true, legend = true },
      layout = {
        dir = "col",
        { section = "requests", flex = 70, min = 6 },
        { section = "orders",   flex = 22, min = 4 },
        { section = "legend",   flex = 8,  min = 3 },
      },
    },
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

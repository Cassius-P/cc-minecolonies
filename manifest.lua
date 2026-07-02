----------------------------------------------------------------------------
-- manifest.lua -- source of truth for install/update.
--
-- `files` maps a repo path (src) to its install target on the computer (dst).
-- install.lua downloads each src from raw.githubusercontent and writes it to
-- dst. `config` targets are never overwritten if they already exist, so local
-- edits survive updates. `remove` lists targets to delete on update (files
-- dropped since a previous version).
----------------------------------------------------------------------------

return {
  version = "3.10",

  files = {
    -- entry + config + vendored dependency
    { src = "src/startup.lua", dst = "/startup.lua" },
    { src = "src/main.lua",    dst = "/main.lua" },
    { src = "src/config.lua",  dst = "/config.lua" },
    { src = "vendor/basalt.lua", dst = "/basalt.lua" },
    -- self-updating installer/updater
    { src = "install.lua",   dst = "/install.lua" },
    { src = "update.lua",    dst = "/update.lua" },
    { src = "uninstall.lua", dst = "/uninstall.lua" },
    -- common
    { src = "src/common/util.lua",        dst = "/common/util.lua" },
    { src = "src/common/log.lua",         dst = "/common/log.lua" },
    { src = "src/common/peripherals.lua", dst = "/common/peripherals.lua" },
    { src = "src/common/settings.lua",    dst = "/common/settings.lua" },
    { src = "src/common/updater.lua",     dst = "/common/updater.lua" },
    -- colony
    { src = "src/colony/skills.lua",   dst = "/colony/skills.lua" },
    { src = "src/colony/advisor.lua",  dst = "/colony/advisor.lua" },
    { src = "src/colony/requests.lua", dst = "/colony/requests.lua" },
    { src = "src/colony/api.lua",      dst = "/colony/api.lua" },
    -- storage
    { src = "src/storage/fulfill.lua", dst = "/storage/fulfill.lua" },
    -- ui
    { src = "src/ui/theme.lua",    dst = "/ui/theme.lua" },
    { src = "src/ui/draw.lua",     dst = "/ui/draw.lua" },
    { src = "src/ui/layout.lua",   dst = "/ui/layout.lua" },
    { src = "src/ui/terminal.lua", dst = "/ui/terminal.lua" },
    { src = "src/ui/app.lua",      dst = "/ui/app.lua" },
    { src = "src/ui/loader.lua",   dst = "/ui/loader.lua" },
    -- ui sections
    { src = "src/ui/sections/status.lua",    dst = "/ui/sections/status.lua" },
    { src = "src/ui/sections/workforce.lua", dst = "/ui/sections/workforce.lua" },
    { src = "src/ui/sections/workers.lua",   dst = "/ui/sections/workers.lua" },
    { src = "src/ui/sections/orders.lua",    dst = "/ui/sections/orders.lua" },
    { src = "src/ui/sections/requests.lua",  dst = "/ui/sections/requests.lua" },
    { src = "src/ui/sections/legend.lua",    dst = "/ui/sections/legend.lua" },
    { src = "src/ui/sections/jobskills.lua", dst = "/ui/sections/jobskills.lua" },
  },

  -- Targets never clobbered on update (user config / local edits survive).
  config = { "/config.lua" },

  -- Targets to delete on update (removed in a later version).
  remove = {},
}

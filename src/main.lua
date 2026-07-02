----------------------------------------------------------------------------
-- main.lua -- dashboard entry point.
--
-- Installed to the computer root (/main.lua). Puts the install root on
-- package.path so the modular requires resolve, then starts the app.
----------------------------------------------------------------------------

package.path = "/?.lua;/?/init.lua;" .. package.path

local config = require("config")
local app    = require("ui.app")

app.start(config)

----------------------------------------------------------------------------
-- ui/terminal.lua -- the ADMIN VIEW: the UI on the Advanced Computer's own
-- screen (NOT the monitors). Native Basalt widgets in a TabControl:
-- Status / Monitors / Peripherals / Settings / Update.
--
-- build() creates widgets once; update() refreshes them each tick but only
-- writes a widget when its value actually changed (diffing) -- this keeps the
-- screen from re-rendering every second, which was making the Settings inputs
-- lag while typing.
----------------------------------------------------------------------------

local perif = require("common.peripherals")

local M = {}

-- Only setText/setForeground when the value changed (avoids constant re-render).
local function set(ui, key, el, text, fg)
  local c = ui._cache[key]
  if not c then c = {}; ui._cache[key] = c end
  if c.t ~= text then el:setText(text); c.t = text end
  if fg and c.f ~= fg then el:setForeground(fg); c.f = fg end
end

-- build(mainFrame, ctx): ctx = { version, config, onUpdateButton, onMargin }.
function M.build(mainFrame, ctx)
  local tw, th = term.getSize()
  local tabs = mainFrame:addTabControl({
    x = 1, y = 1, width = tw, height = th,
    headerBackground = colors.gray, foreground = colors.white,
  })
  local ui = { _cache = {} }

  ------------------------------------------------------------------ Status
  local st = tabs:newTab("Status")
  ui.lTitle  = st:addLabel({ x = 2, y = 1, width = tw - 2, foreground = colors.cyan })
  ui.lColony = st:addLabel({ x = 2, y = 3, width = tw - 2 })
  ui.lPop    = st:addLabel({ x = 2, y = 4, width = tw - 2 })
  ui.lThreat = st:addLabel({ x = 2, y = 5, width = tw - 2 })
  ui.lWork   = st:addLabel({ x = 2, y = 6, width = tw - 2 })
  ui.lBridge = st:addLabel({ x = 2, y = 7, width = tw - 2 })
  ui.lFoot   = st:addLabel({ x = 2, y = th - 2, width = tw - 2, foreground = colors.lightGray })
  st:addLabel({ x = 2, y = th, width = tw - 2 })
    :setText("r rescan  t theme  u check  i install  1-9 screen  q quit")
    :setForeground(colors.gray)

  ------------------------------------------------------------------ Monitors
  local mt = tabs:newTab("Monitors")
  mt:addLabel({ x = 2, y = 1, width = tw - 2 })
    :setText("Monitors -- press 1-9 to change a monitor's screen"):setForeground(colors.cyan)
  ui.tbMon = mt:addTextBox({ x = 2, y = 3, width = tw - 3, height = th - 4,
    editable = false, background = colors.black, foreground = colors.white })

  ------------------------------------------------------------------ Peripherals
  local pt = tabs:newTab("Peripherals")
  pt:addLabel({ x = 2, y = 1, width = tw - 2 })
    :setText("Network devices (name : type)"):setForeground(colors.cyan)
  ui.tbPerif = pt:addTextBox({ x = 2, y = 3, width = tw - 3, height = th - 4,
    editable = false, background = colors.black, foreground = colors.white })

  ------------------------------------------------------------------ Settings
  local se = tabs:newTab("Settings")
  se:addLabel({ x = 2, y = 1, width = tw - 2, foreground = colors.cyan })
    :setText("Worker suggestions -- how big a skill gain to suggest a move")
  se:addLabel({ x = 2, y = 3, width = 16 }):setText("Replace worker"):setForeground(colors.white)
  ui.inReplace = se:addInput({ x = 18, y = 3, width = 5, height = 1, placeholder = "1",
    background = colors.gray, foreground = colors.white })
  ui.lReplaceHint = se:addLabel({ x = 24, y = 3, width = tw - 24, foreground = colors.lightGray })

  se:addLabel({ x = 2, y = 5, width = 16 }):setText("Reassign job"):setForeground(colors.white)
  ui.inReassign = se:addInput({ x = 18, y = 5, width = 5, height = 1, placeholder = "1",
    background = colors.gray, foreground = colors.white })
  ui.lReassignHint = se:addLabel({ x = 24, y = 5, width = tw - 24, foreground = colors.lightGray })

  se:addLabel({ x = 2, y = 8, width = tw - 2, foreground = colors.gray })
    :setText("Click a box, type a number (0-20).")
  se:addLabel({ x = 2, y = 9, width = tw - 2, foreground = colors.gray })
    :setText("0 = suggest any gain   higher = only big upgrades")

  local sg = ctx.config.suggestions or {}
  ui.inReplace:setText(tostring(sg.replaceMargin or 1))
  ui.inReassign:setText(tostring(sg.reassignMargin or 1))
  ui.inReplace:onChange("text", function(_, v) if ctx.onMargin then ctx.onMargin("replaceMargin", v) end end)
  ui.inReassign:onChange("text", function(_, v) if ctx.onMargin then ctx.onMargin("reassignMargin", v) end end)

  ------------------------------------------------------------------ Dump
  local dm = tabs:newTab("Dump")
  dm:addLabel({ x = 2, y = 1, width = tw - 2, foreground = colors.cyan })
    :setText("Dump colony data -> paste.rs (JSON)")
  local defs = {
    { "colony", "Colony info" }, { "citizens", "Citizens" }, { "buildings", "Buildings" },
    { "workOrders", "Work orders" }, { "requests", "Requests" }, { "visitors", "Visitors" },
  }
  ui.dumpCbs = {}
  for i, dinfo in ipairs(defs) do
    local cb = dm:addCheckBox({ x = 2, y = 2 + i, checked = true, text = " " .. dinfo[2] })
    ui.dumpCbs[#ui.dumpCbs + 1] = { key = dinfo[1], cb = cb }
  end
  local by = 2 + #defs + 2
  ui.dumpBtn = dm:addButton({ x = 2, y = by, width = 16, height = 1 })
    :setText("Create dump"):setBackground(colors.blue):setForeground(colors.white)
    :onClick(function() if ctx.onDump then ctx.onDump(M.dumpSelection(ui)) end end)
  dm:addLabel({ x = 20, y = by, width = tw - 20, foreground = colors.gray }):setText("or press 'd'")
  ui.lDump = dm:addLabel({ x = 2, y = by + 2, width = tw - 2 })

  ------------------------------------------------------------------ Update
  local ut = tabs:newTab("Update")
  ui.lVer = ut:addLabel({ x = 2, y = 1, width = tw - 2, foreground = colors.lightGray })
  ui.lUpd = ut:addLabel({ x = 2, y = 3, width = tw - 2 })
  ui.updBtn = ut:addButton({ x = 2, y = 5, width = 20, height = 1 })
    :onClick(function() if ctx.onUpdateButton then ctx.onUpdateButton() end end)
  ut:addLabel({ x = 2, y = 7, width = tw - 2 })
    :setText("Check finds a new version; Install pulls it & reboots.")
    :setForeground(colors.gray)
  ut:addLabel({ x = 2, y = 8, width = tw - 2 })
    :setText("Keys: u check   i install   (or 'update' in shell)"):setForeground(colors.gray)

  return {
    update = function(state, screens) M._update(ui, ctx, state, screens) end,
    triggerDump = function() if ctx.onDump then ctx.onDump(M.dumpSelection(ui)) end end,
  }
end

function M.dumpSelection(ui)
  local sel = {}
  for _, e in ipairs(ui.dumpCbs) do sel[e.key] = e.cb.get("checked") and true or false end
  return sel
end

local function marginHint(n)
  n = tonumber(n) or 1
  if n <= 0 then return "any gain" end
  return "gain >= " .. n
end

function M._update(ui, ctx, state, screens)
  local d = state.data
  set(ui, "title", ui.lTitle, "Colony Dashboard  v" .. ctx.version)
  if d then
    set(ui, "colony", ui.lColony, ("Colony: %s  #%s"):format(d.name, d.id), colors.white)
    set(ui, "pop", ui.lPop, ("Happy %.1f/10   Pop %d/%d   Idle %d"):format(d.happiness, d.pop, d.maxPop, d.idle),
      d.idle > 0 and colors.orange or colors.white)
    local threat = d.attack and "UNDER ATTACK" or (d.raid and "RAID INCOMING" or "Secure")
    set(ui, "threat", ui.lThreat, ("Threat: %s    Sites %d  Graves %d"):format(threat, d.sites, d.graves),
      (d.attack or d.raid) and colors.red or colors.lime)
    set(ui, "work", ui.lWork, ("Workers to place: %d    Requests: %d [%s]"):format(#d.suggestions, #d.requests, d.reqMode),
      d.reqMode == "AUTO" and colors.lime or colors.lightGray)
    set(ui, "bridge", ui.lBridge, ("Bridge: %s   Storage: %s"):format(d.bridgePresent and "yes" or "NO", d.storagePresent and "yes" or "NO"),
      (d.bridgePresent and d.storagePresent) and colors.white or colors.gray)
  else
    set(ui, "colony", ui.lColony, "scanning...", colors.gray)
  end
  set(ui, "foot", ui.lFoot, ("Theme %s   next scan %2ds   %s"):format(ctx.config.theme, state.countdown, state.msg or ""))

  local ml = {}
  for i, s in ipairs(screens) do
    ml[#ml + 1] = ("[%d] %s  %dx%d  -> screen %d"):format(i, s.name, s.W, s.H, s.cfgIdx or 1)
  end
  set(ui, "mon", ui.tbMon, table.concat(ml, "\n"))

  local pl = {}
  for _, p in ipairs(perif.diagnostics()) do pl[#pl + 1] = ("%s : %s"):format(p.name, p.type) end
  set(ui, "perif", ui.tbPerif, table.concat(pl, "\n"))

  -- Settings hints reflect the live config (inputs themselves are not rewritten).
  local sg = ctx.config.suggestions or {}
  set(ui, "rHint", ui.lReplaceHint, marginHint(sg.replaceMargin), colors.lightGray)
  set(ui, "aHint", ui.lReassignHint, marginHint(sg.reassignMargin), colors.lightGray)

  -- Dump tab status
  if state.dumping then
    set(ui, "dump", ui.lDump, "Dumping...", colors.yellow)
  elseif state.dumpError then
    set(ui, "dump", ui.lDump, "Failed: " .. tostring(state.dumpError):sub(1, 40), colors.red)
  elseif state.dumpLink then
    set(ui, "dump", ui.lDump, state.dumpLink, colors.lime)
  else
    set(ui, "dump", ui.lDump, "", colors.white)
  end

  -- Update tab
  set(ui, "ver", ui.lVer, "Installed: v" .. ctx.version)
  local up = state.update
  if state.checking then
    set(ui, "upd", ui.lUpd, "Checking for updates...", colors.yellow)
    set(ui, "updBtnT", ui.updBtn, "Checking...")
    if ui._cache.updBtnBg ~= colors.gray then ui.updBtn:setBackground(colors.gray); ui.updBtn:setForeground(colors.white); ui._cache.updBtnBg = colors.gray end
  elseif state.checkFailed and not (up and up.available) then
    set(ui, "upd", ui.lUpd, "Check failed - no connection", colors.red)
    set(ui, "updBtnT", ui.updBtn, "Check for update")
    if ui._cache.updBtnBg ~= colors.blue then ui.updBtn:setBackground(colors.blue); ui.updBtn:setForeground(colors.white); ui._cache.updBtnBg = colors.blue end
  elseif up and up.available then
    set(ui, "upd", ui.lUpd, ("Update available: v%s -> v%s"):format(up.localv, up.remote), colors.orange)
    set(ui, "updBtnT", ui.updBtn, "Install update")
    if ui._cache.updBtnBg ~= colors.green then ui.updBtn:setBackground(colors.green); ui.updBtn:setForeground(colors.black); ui._cache.updBtnBg = colors.green end
  elseif up then
    set(ui, "upd", ui.lUpd, ("Up to date (v%s)"):format(up.localv or ctx.version), colors.green)
    set(ui, "updBtnT", ui.updBtn, "Check for update")
    if ui._cache.updBtnBg ~= colors.blue then ui.updBtn:setBackground(colors.blue); ui.updBtn:setForeground(colors.white); ui._cache.updBtnBg = colors.blue end
  else
    set(ui, "upd", ui.lUpd, "Not checked yet", colors.lightGray)
    set(ui, "updBtnT", ui.updBtn, "Check for update")
    if ui._cache.updBtnBg ~= colors.blue then ui.updBtn:setBackground(colors.blue); ui.updBtn:setForeground(colors.white); ui._cache.updBtnBg = colors.blue end
  end
end

return M

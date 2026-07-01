--[[
  colony_advisor.lua  --  MineColonies citizen-job advisor dashboard (CC:Tweaked)

  Peripherals (Advanced Peripherals):
    * colony_integrator  (adjacent, or via wired modem)
    * monitor            (advanced/touch; 3x3+ recommended)

  Dashboard layout (relevance-sized):
    +--------------------------------------------------------------+
    | HEADER  colony name / id / refresh countdown                 |
    +----------------------+---------------------------------------+
    | COLONY STATUS (fixed)| SUGGESTIONS (largest: ~60% x full)    |
    | WORKFORCE     (fixed)|   scrollable, [DO] per row            |
    | WORK ORDERS   (flex) |                                       |
    | OPEN REQUESTS (flex) |                                       |
    +----------------------+---------------------------------------+
    | FOOTER  [RESCAN] [QUIT]  status message                      |
    +--------------------------------------------------------------+

  Color scheme: "deepslate" palette from MikaylaFischler/cc-mek-scada
  (graphics/themes.lua), applied to the monitor via setPaletteColour.
  colors.brown is repurposed as the dark card color (SCADA-style trick).

  Suggestion kinds:
    "Assign X -> Job"          open worker slot
    "Replace Y with X @ Job"   slot full, stronger idle citizen exists

  Touch to interact. Keyboard: q quits.

  READ-ONLY API: colony_integrator cannot assign/hire from Lua. [DO] shows
  exact manual steps + coords and marks the suggestion handled. Wire a real
  assign into tryApiAssign() if a future AP version exposes one.
--]]

-------------------------------------------------------------------------------
-- CONFIG
-------------------------------------------------------------------------------

local REFRESH_SECONDS  = 30
local MAX_ROWS         = 60
local REPLACE_MARGIN   = 3
local PRIMARY_WEIGHT   = 1.0
local SECONDARY_WEIGHT = 0.5
local HAPPINESS_MAX    = 10

local JOB_SKILLS = {
  builder     = { "Knowledge",   "Adaptability" },
  deliveryman = { "Agility",     "Adaptability" },
  courier     = { "Agility",     "Adaptability" },
  farmer      = { "Stamina",     "Athletics"    },
  fisherman   = { "Focus",       "Agility"      },
  lumberjack  = { "Strength",    "Focus"        },
  miner       = { "Strength",    "Stamina"      },
  smelter     = { "Athletics",   "Strength"     },
  composter   = { "Stamina",     "Athletics"    },
  cook        = { "Adaptability","Knowledge"    },
  baker       = { "Knowledge",   "Dexterity"    },
  cowboy      = { "Athletics",   "Stamina"      },
  shepherd    = { "Athletics",   "Stamina"      },
  swineherd   = { "Athletics",   "Stamina"      },
  chickenherd = { "Adaptability","Athletics"    },
  rabbitherd  = { "Agility",     "Athletics"    },
  beekeeper   = { "Dexterity",   "Adaptability" },
  guard       = { "Adaptability","Strength"     },
  knight      = { "Adaptability","Strength"     },
  archer      = { "Agility",     "Adaptability" },
  blacksmith  = { "Knowledge",   "Strength"     },
  stonemason  = { "Knowledge",   "Dexterity"    },
  sawmill     = { "Knowledge",   "Dexterity"    },
  carpenter   = { "Knowledge",   "Dexterity"    },
  fletcher    = { "Dexterity",   "Creativity"   },
  glassblower = { "Creativity",  "Dexterity"    },
  dyer        = { "Creativity",  "Dexterity"    },
  concretemixer = { "Creativity","Dexterity"    },
  sifter      = { "Focus",       "Strength"     },
  florist     = { "Dexterity",   "Agility"      },
  crusher     = { "Strength",    "Stamina"      },
  enchanter   = { "Mana",        "Knowledge"    },
  university  = { "Knowledge",   "Mana"         },
  researcher  = { "Knowledge",   "Mana"         },
  healer      = { "Mana",        "Knowledge"    },
  netherworker   = { "Adaptability","Strength"  },
  planter        = { "Agility",  "Dexterity"    },
}

-- Worker-slot capacity per building type (API exposes no per-hut max).
local JOB_MAX_SLOTS = {
  deliveryman = function(lvl) return math.max(1, lvl or 1) end,
  courier     = function(lvl) return math.max(1, lvl or 1) end,
  guard       = function(lvl) return math.max(1, lvl or 1) end,
  knight      = function(lvl) return math.max(1, lvl or 1) end,
  archer      = function(lvl) return math.max(1, lvl or 1) end,
}
local function maxSlotsFor(bType, level)
  local v = JOB_MAX_SLOTS[bType]
  if type(v) == "function" then return v(level or 1) end
  if type(v) == "number"   then return v end
  return 1
end

-------------------------------------------------------------------------------
-- THEME: cc-mek-scada "deepslate" (graphics/themes.lua)
-------------------------------------------------------------------------------

local PALETTE = {
  [colors.red]       = 0xeb6a6c,
  [colors.orange]    = 0xf2b86c,
  [colors.yellow]    = 0xd9cf81,
  [colors.lime]      = 0x80ff80,
  [colors.green]     = 0x70e19b,
  [colors.cyan]      = 0x7ccdd0,
  [colors.lightBlue] = 0x99ceef,
  [colors.blue]      = 0x60bcff,
  [colors.purple]    = 0xc38aea,
  [colors.pink]      = 0xff7fb8,
  [colors.magenta]   = 0xf980dd,
  [colors.white]     = 0xd9d9d9,
  [colors.lightGray] = 0x949494,
  [colors.gray]      = 0x575757,
  [colors.black]     = 0x262626,
  [colors.brown]     = 0x333333,   -- repurposed: dark card body
}

local C = {
  screen    = colors.black,
  card      = colors.brown,       -- panel body (dark, remapped)
  cardTitle = colors.gray,        -- SCADA header: white on gray
  titleText = colors.white,
  text      = colors.white,
  dim       = colors.lightGray,
  accent    = colors.blue,
  accent2   = colors.cyan,
  good      = colors.green,
  warn      = colors.orange,
  bad       = colors.red,
  note      = colors.yellow,
  btn       = colors.orange,
  btnText   = colors.black,
  btnOk     = colors.green,
  btnBad    = colors.red,
}

-------------------------------------------------------------------------------
-- PERIPHERALS
-------------------------------------------------------------------------------

local colony = peripheral.find("colony_integrator")
if not colony then error("No colony_integrator found (place adjacent or via wired modem)", 0) end
if not colony.isInColony() then error("Integrator is not inside a colony", 0) end

local mon = peripheral.find("monitor")
if not mon then error("No monitor found", 0) end
mon.setTextScale(0.5)

local function applyPalette()
  for c, hex in pairs(PALETTE) do mon.setPaletteColour(c, hex) end
end
local function restorePalette()
  for i = 0, 15 do
    local c = 2 ^ i
    mon.setPaletteColour(c, term.nativePaletteColour(c))
  end
end
applyPalette()

-------------------------------------------------------------------------------
-- DATA HELPERS
-------------------------------------------------------------------------------

local function jobKey(s)
  if type(s) ~= "string" then return nil end
  s = s:lower()
  local seg = s:match("([%w_]+)$") or s
  return (seg:gsub("[^%a]", ""))
end

local function skillLevel(c, name)
  local sk = c.skills; if not sk then return 0 end
  local v = sk[name]
  if type(v) == "table" then return v.level or 0 end
  if type(v) == "number" then return v end
  return 0
end

local function scoreFor(c, primary, secondary)
  return skillLevel(c, primary) * PRIMARY_WEIGHT
       + skillLevel(c, secondary) * SECONDARY_WEIGHT
end

local function isUnemployed(c)
  if c.isChild == "child" or c.isChild == true then return false end
  local w = c.work
  return not (type(w) == "table" and w.type)
end

local function locStr(loc)
  if type(loc) == "table" then
    return string.format("%s, %s, %s", tostring(loc.x), tostring(loc.y), tostring(loc.z))
  end
  return "unknown"
end

-------------------------------------------------------------------------------
-- CORE: suggestions
-------------------------------------------------------------------------------

local function computeSuggestions(citizens, buildings)
  local byId = {}
  for _, c in ipairs(citizens) do byId[c.id] = c end

  local idle = {}
  for _, c in ipairs(citizens) do if isUnemployed(c) then idle[#idle+1] = c end end

  local function bestIdleFor(pr, se)
    local best, bestScore = nil, -1
    for _, c in ipairs(idle) do
      local s = scoreFor(c, pr, se)
      if s > bestScore then best, bestScore = c, s end
    end
    return best, bestScore
  end

  local out = {}
  for _, b in ipairs(buildings) do
    local jk = b.type or jobKey(b.name)
    if jk and JOB_SKILLS[jk] and b.built ~= false then
      local pr, se = JOB_SKILLS[jk][1], JOB_SKILLS[jk][2]
      local workers  = (type(b.citizens) == "table") and b.citizens or {}
      local nWorkers = #workers
      local maxSlots = maxSlotsFor(jk, b.level)
      local cand, candScore = bestIdleFor(pr, se)

      if cand then
        if nWorkers < maxSlots then
          out[#out+1] = {
            kind = "assign", job = jk,
            building = { name = jk, location = b.location, level = b.level },
            candidate = { name = cand.name, id = cand.id, score = candScore },
            gain = candScore,
          }
        else
          local weakest, weakScore = nil, math.huge
          for _, w in ipairs(workers) do
            local full = byId[w.id]
            local s = full and scoreFor(full, pr, se) or 0
            if s < weakScore then weakest, weakScore = w, s end
          end
          if weakest and (candScore - weakScore) >= REPLACE_MARGIN then
            out[#out+1] = {
              kind = "replace", job = jk,
              building = { name = jk, location = b.location, level = b.level },
              candidate = { name = cand.name, id = cand.id, score = candScore },
              target    = { name = weakest.name, id = weakest.id, score = weakScore },
              gain = candScore - weakScore,
            }
          end
        end
      end
    end
  end

  table.sort(out, function(a, b) return a.gain > b.gain end)
  while #out > MAX_ROWS do table.remove(out) end
  return out
end

local function gatherData()
  local function g(fn, default)
    local ok, v = pcall(fn); if ok and v ~= nil then return v else return default end
  end
  local citizens  = g(function() return colony.getCitizens()   end, {})
  local buildings = g(function() return colony.getBuildings()  end, {})
  local requests  = g(function() return colony.getRequests()   end, {})
  local orders    = g(function() return colony.getWorkOrders() end, {})
  local visitors  = g(function() return colony.getVisitors()   end, {})

  local employed, idle = 0, 0
  for _, c in ipairs(citizens) do
    if isUnemployed(c) then idle = idle + 1 else employed = employed + 1 end
  end

  return {
    name      = g(colony.getColonyName, "?"),
    id        = g(colony.getColonyID, "?"),
    happiness = g(colony.getHappiness, 0),
    pop       = g(colony.amountOfCitizens, #citizens),
    maxPop    = g(colony.maxOfCitizens, 0),
    attack    = g(colony.isUnderAttack, false),
    raid      = g(colony.isUnderRaid, false),
    sites     = g(colony.amountOfConstructionSites, 0),
    graves    = g(colony.amountOfGraves, 0),
    total     = #citizens,
    employed  = employed,
    idle      = idle,
    buildings = #buildings,
    visitors  = type(visitors) == "table" and #visitors or 0,
    requests  = type(requests) == "table" and requests or {},
    orders    = type(orders)   == "table" and orders   or {},
    suggestions = computeSuggestions(citizens, buildings),
  }
end

-------------------------------------------------------------------------------
-- DRAW PRIMITIVES
-------------------------------------------------------------------------------

local W, H = mon.getSize()
local buttons = {}

local function clearButtons() buttons = {} end
local function addButton(x1, y1, x2, y2, action)
  buttons[#buttons+1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, action = action }
end
local function hit(x, y)
  for i = #buttons, 1, -1 do
    local b = buttons[i]
    if x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2 then return b.action end
  end
end

local function put(x, y, text, fg, bg)
  if y < 1 or y > H then return end
  text = tostring(text)
  if x < 1 then text = text:sub(2 - x); x = 1 end
  local room = W - x + 1
  if room <= 0 then return end
  if #text > room then text = text:sub(1, room) end
  mon.setCursorPos(x, y)
  mon.setTextColor(fg or C.text)
  mon.setBackgroundColor(bg or C.screen)
  mon.write(text)
end

local function fillRect(x, y, w, h, bg)
  if w <= 0 or h <= 0 then return end
  mon.setBackgroundColor(bg)
  local line = string.rep(" ", w)
  for yy = y, y + h - 1 do
    if yy >= 1 and yy <= H then mon.setCursorPos(x, yy); mon.write(line) end
  end
end

-- SCADA-style card: gray title strip, dark body. Returns inner x,y,w,h.
local function card(x, y, w, h, title)
  fillRect(x, y, w, h, C.card)
  fillRect(x, y, w, 1, C.cardTitle)
  put(x + 1, y, title, C.titleText, C.cardTitle)
  return x + 1, y + 1, w - 2, h - 2
end

local function hbar(x, y, w, frac, fillColor, label)
  frac = math.max(0, math.min(1, frac or 0))
  local filled = math.floor(w * frac + 0.5)
  fillRect(x, y, w, 1, C.screen)
  if filled > 0 then fillRect(x, y, filled, 1, fillColor) end
  if label then
    -- label overlays the bar, readable on both halves
    for i = 1, #label do
      local lx = x + i - 1
      if lx > x + w - 1 then break end
      local onFill = (i <= filled)
      put(lx, y, label:sub(i, i), onFill and colors.black or C.dim,
          onFill and fillColor or C.screen)
    end
  end
end

local function button(x, y, label, bg, fg, action)
  local lbl = " " .. label .. " "
  put(x, y, lbl, fg or C.btnText, bg or C.btn)
  addButton(x, y, x + #lbl - 1, y, action)
  return x + #lbl
end

-------------------------------------------------------------------------------
-- APPLY (read-only => manual steps)
-------------------------------------------------------------------------------

local function tryApiAssign(_)
  return false, "API read-only; hire manually."
end

-------------------------------------------------------------------------------
-- SECTIONS
-------------------------------------------------------------------------------

local state = { data = nil, msg = "", scroll = 0, modal = nil,
                needScan = false, quit = false, countdown = REFRESH_SECONDS }

local function drawHeader(d)
  fillRect(1, 1, W, 1, C.cardTitle)
  put(2, 1, "MINECOLONIES ADVISOR", C.titleText, C.cardTitle)
  local right = string.format("%s #%s  %02ds", tostring(d.name), tostring(d.id), state.countdown)
  put(W - #right - 1, 1, right, C.dim, C.cardTitle)
end

local function drawStatus(d, x, y, w, h)
  local cx, cy, cw = card(x, y, w, h, "COLONY STATUS")
  local row = cy

  local hc = d.happiness >= 7 and C.good or (d.happiness >= 4 and C.warn or C.bad)
  put(cx, row, "Happiness", C.dim, C.card); row = row + 1
  hbar(cx, row, cw, d.happiness / HAPPINESS_MAX, hc,
       string.format(" %.1f / %d", d.happiness, HAPPINESS_MAX))
  row = row + 1

  put(cx, row, "Population", C.dim, C.card); row = row + 1
  hbar(cx, row, cw, d.maxPop > 0 and d.pop / d.maxPop or 0, C.accent,
       string.format(" %d / %d", d.pop, d.maxPop))
  row = row + 1

  local threat = d.attack and "UNDER ATTACK" or (d.raid and "RAID INCOMING" or "SECURE")
  local tc = (d.attack or d.raid) and C.bad or C.good
  put(cx, row, "Threat", C.dim, C.card)
  put(cx + cw - #threat, row, threat, tc, C.card); row = row + 1

  local sg = string.format("%d sites  %d graves", d.sites, d.graves)
  put(cx, row, "Constr.", C.dim, C.card)
  put(cx + cw - #sg, row, sg, d.graves > 0 and C.warn or C.text, C.card)
end

local function drawWorkforce(d, x, y, w, h)
  local cx, cy, cw = card(x, y, w, h, "WORKFORCE")
  local function stat(row, label, val, col)
    put(cx, cy + row, label, C.dim, C.card)
    local s = tostring(val)
    put(cx + cw - #s, cy + row, s, col or C.text, C.card)
  end
  stat(0, "Citizens",  d.total,     C.text)
  stat(1, "Employed",  d.employed,  C.good)
  stat(2, "Idle",      d.idle,      d.idle > 0 and C.warn or C.dim)
  stat(3, "Visitors",  d.visitors,  C.accent2)
  stat(4, "Buildings", d.buildings, C.text)
end

local function drawOrders(d, x, y, w, h)
  local list = d.orders
  local cx, cy, cw, ch = card(x, y, w, h, string.format("WORK ORDERS (%d)", #list))
  if #list == 0 then put(cx, cy, "None queued.", C.dim, C.card); return end
  for i = 1, math.min(ch, #list) do
    local o = list[i]
    local kind = tostring(o.workOrderType or o.type or "?"):sub(1, 7)
    local target = jobKey(o.buildingName or o.structureName or o.name or "?") or "?"
    local lvl = o.targetLevel and ("L" .. o.targetLevel) or ""
    local claimed = o.isClaimed and "\7" or " "
    put(cx, cy + i - 1, string.format("%s%-7s %s %s", claimed, kind, target, lvl),
        o.isClaimed and C.text or C.dim, C.card)
  end
  if #list > ch then put(cx, cy + ch - 1, ("+%d more..."):format(#list - ch + 1), C.note, C.card) end
end

local function drawRequests(d, x, y, w, h)
  local list = d.requests
  local cx, cy, cw, ch = card(x, y, w, h, string.format("OPEN REQUESTS (%d)", #list))
  if #list == 0 then put(cx, cy, "None open.", C.dim, C.card); return end
  for i = 1, math.min(ch, #list) do
    local r = list[i]
    local count = r.count and (r.count .. "x ") or ""
    local name  = tostring(r.name or "?")
    local who   = r.target and (" \16 " .. tostring(r.target)) or ""
    put(cx, cy + i - 1, count .. name .. who, C.note, C.card)
  end
  if #list > ch then put(cx, cy + ch - 1, ("+%d more..."):format(#list - ch + 1), C.note, C.card) end
end

local function drawSuggestions(d, x, y, w, h)
  local list = d.suggestions
  local cx, cy, cw, ch = card(x, y, w, h, string.format("SUGGESTIONS (%d)", #list))

  if #list > ch then
    put(x + w - 7, y, " \24 ", C.btnText, C.btnOk)
    addButton(x + w - 7, y, x + w - 5, y, function()
      state.scroll = math.max(0, state.scroll - 1) end)
    put(x + w - 4, y, " \25 ", C.btnText, C.btnOk)
    addButton(x + w - 4, y, x + w - 2, y, function()
      state.scroll = math.min(#list - ch, state.scroll + 1) end)
  end

  if #list == 0 then
    put(cx, cy, "All jobs optimally staffed.", C.good, C.card)
    return
  end

  local maxScroll = math.max(0, #list - ch)
  if state.scroll > maxScroll then state.scroll = maxScroll end

  for i = 1, ch do
    local idx = i + state.scroll
    local s = list[idx]
    if not s then break end
    local ry = cy + i - 1
    button(cx, ry, "DO", C.btn, C.btnText, function() state.modal = s; state.msg = "" end)
    local tx = cx + 5
    if s.kind == "assign" then
      put(tx, ry, string.format("Assign %s \26 %s (+%d)", s.candidate.name, s.job, s.gain),
          C.good, C.card)
    else
      put(tx, ry, string.format("Swap %s\26%s @%s (+%d)",
          s.target.name, s.candidate.name, s.job, s.gain), C.warn, C.card)
    end
  end
end

local function drawFooter()
  fillRect(1, H, W, 1, C.cardTitle)
  local x = 2
  x = button(x, H, "RESCAN", C.btnOk, C.btnText, function() state.needScan = true end) + 1
  x = button(x, H, "QUIT", C.btnBad, colors.black, function() state.quit = true end) + 2
  if state.msg ~= "" then put(x, H, state.msg, C.dim, C.cardTitle) end
end

local function drawModal(s)
  local mw = math.min(W - 4, 46)
  local mh = math.min(H - 4, 13)
  local mx = math.floor((W - mw) / 2) + 1
  local my = math.floor((H - mh) / 2) + 1

  local cx, cy = card(mx, my, mw, mh, "APPLY SUGGESTION")
  local row = cy
  local ok, apiMsg = tryApiAssign(s)

  local lines
  if s.kind == "assign" then
    lines = {
      { "Job:      " .. s.job, C.text },
      { "Building: " .. locStr(s.building.location), C.text },
      { "Hire:     " .. s.candidate.name .. " (" .. s.candidate.score .. ")", C.good },
      { "", C.text },
      { "Manual steps:", C.accent2 },
      { " 1. Go to " .. locStr(s.building.location), C.dim },
      { " 2. Open hut GUI \26 Hire/Fire", C.dim },
      { " 3. Slot in " .. s.candidate.name, C.dim },
    }
  else
    lines = {
      { "Job:      " .. s.job, C.text },
      { "Building: " .. locStr(s.building.location), C.text },
      { "Fire:     " .. s.target.name .. " (" .. s.target.score .. ")", C.bad },
      { "Hire:     " .. s.candidate.name .. " (" .. s.candidate.score .. ")", C.good },
      { "Manual steps:", C.accent2 },
      { " 1. Go to " .. locStr(s.building.location), C.dim },
      { " 2. Open GUI \26 Hire/Fire", C.dim },
      { " 3. Fire " .. s.target.name .. ", hire " .. s.candidate.name, C.dim },
    }
  end

  for _, ln in ipairs(lines) do
    if row > my + mh - 3 then break end
    put(cx, row, ln[1], ln[2], C.card)
    row = row + 1
  end
  put(cx, my + mh - 2, ok and "API applied." or apiMsg, C.dim, C.card)

  local bx = cx
  bx = button(bx, my + mh - 1, "HANDLED", C.btnOk, C.btnText, function()
    for i, x in ipairs(state.data.suggestions) do
      if x == s then table.remove(state.data.suggestions, i); break end
    end
    state.modal = nil
  end) + 1
  button(bx, my + mh - 1, "BACK", colors.lightGray, colors.black, function() state.modal = nil end)
end

-------------------------------------------------------------------------------
-- LAYOUT (relevance-sized)
-------------------------------------------------------------------------------

local function layout()
  local d = state.data
  local topY, botY = 2, H - 1
  local ch = botY - topY + 1

  if W >= 54 then
    -- Two columns. Suggestions = most relevant -> ~60% width, full height.
    local leftW  = math.max(22, math.floor(W * 0.38))
    local rightX = leftW + 2
    local rightW = W - leftW - 1

    -- Left stack: fixed compact cards, then flex split.
    local statusH, workH = 7, 8
    local rest = ch - statusH - workH - 2          -- 2 gap rows
    local y = topY

    drawStatus(d, 1, y, leftW, statusH);   y = y + statusH + 1
    drawWorkforce(d, 1, y, leftW, workH);  y = y + workH + 1

    if rest >= 9 then
      -- Orders slightly favored over requests (build progress > shopping list).
      local ordersH = math.max(4, math.floor((rest - 1) * 0.55))
      local reqH    = rest - 1 - ordersH
      drawOrders(d, 1, y, leftW, ordersH); y = y + ordersH + 1
      if reqH >= 3 then drawRequests(d, 1, y, leftW, botY - y + 1) end
    elseif rest >= 4 then
      drawOrders(d, 1, y, leftW, botY - y + 1)
    end

    drawSuggestions(d, rightX, topY, rightW, ch)
  else
    -- Narrow: stack. Suggestions get ~55% of the space.
    local statusH = 7
    local sugH = math.max(6, math.floor((ch - statusH - 2) * 0.55))
    local y = topY
    drawStatus(d, 1, y, W, statusH); y = y + statusH + 1
    drawSuggestions(d, 1, y, W, sugH); y = y + sugH + 1
    if botY - y + 1 >= 4 then drawRequests(d, 1, y, W, botY - y + 1) end
  end
end

local function redraw()
  mon.setBackgroundColor(C.screen); mon.clear()
  clearButtons()
  if not state.data then put(2, 2, "Scanning...", C.dim); return end
  drawHeader(state.data)
  layout()
  drawFooter()
  if state.modal then
    clearButtons()          -- modal captures all clicks
    drawModal(state.modal)
  end
end

-------------------------------------------------------------------------------
-- MAIN LOOP
-------------------------------------------------------------------------------

local function rescan()
  local ok, res = pcall(gatherData)
  if ok then
    state.data = res
    state.msg = string.format("%d suggestion(s)", #res.suggestions)
  else
    state.msg = "Scan error: " .. tostring(res)
  end
  state.needScan = false
  state.countdown = REFRESH_SECONDS
end

rescan()
redraw()

local tick = os.startTimer(1)
while true do
  local ev = { os.pullEvent() }
  local e = ev[1]

  if e == "monitor_touch" then
    local action = hit(ev[3], ev[4])
    if action then action() end
    if state.quit then break end
    if state.needScan then rescan() end
    redraw()

  elseif e == "timer" and ev[2] == tick then
    state.countdown = state.countdown - 1
    if state.countdown <= 0 and not state.modal then rescan() end
    redraw()
    tick = os.startTimer(1)

  elseif e == "char" and ev[2] == "q" then
    break

  elseif e == "monitor_resize" or e == "term_resize" then
    W, H = mon.getSize(); redraw()
  end
end

restorePalette()
mon.setBackgroundColor(colors.black); mon.clear(); mon.setCursorPos(1, 1)
term.clear(); term.setCursorPos(1, 1)
print("colony_advisor stopped.")

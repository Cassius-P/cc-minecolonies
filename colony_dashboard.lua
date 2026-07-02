--[[============================================================================
  colony_dashboard.lua  --  configurable MineColonies dashboard (CC:Tweaked)

  Peripherals (Advanced Peripherals):
    * colony_integrator            REQUIRED (adjacent or via wired modem)
    * monitor                      REQUIRED (advanced/touch)
    * meBridge / rsBridge          OPTIONAL (enables request auto-fulfill)
    * any inventory (warehouse)    OPTIONAL (export target for auto-fulfill)

  ---------------------------------------------------------------------------
  CONFIGURING THE DASHBOARD  (edit the CONFIG block below)
  ---------------------------------------------------------------------------
  * CONFIG.theme        one of THEME_ORDER (cc-mek-scada palettes)
  * CONFIG.enabled      per-section on/off (also toggleable at runtime)
  * CONFIG.layout       a flexbox-like tree. Two node kinds:

      container = { dir = "row" | "col", flex=, min=, max=, <children...> }
      leaf      = { section = "<id>", flex=, min=, max= }

    - dir="row" lays children left-to-right; dir="col" top-to-bottom.
    - flex  = weight for sharing the parent's MAIN axis (default 1).
    - min/max = clamp on the MAIN axis, in cells (rows for col, cols for row).
    - the CROSS axis always fills the parent.
    - Disabled sections drop out and their space is redistributed.

    Move a section  -> reorder it among its siblings.
    Resize          -> change its flex / min / max.
    Enable/disable  -> CONFIG.enabled[id] = true|false (or the SECTIONS button).

  Available section ids: status, workforce, suggestions, orders, requests, legend

  ---------------------------------------------------------------------------
  REQUEST AUTO-FULFILL (CCxM logic, folded into the "requests" section)
  ---------------------------------------------------------------------------
  When a storage bridge + inventory are present AND CONFIG.autofulfill.enabled,
  colony requests are exported from the ME/RS system to the warehouse and
  missing craftable items are queued. Guarded by constraints:

    autofulfill.pauseUnderAttack   skip while raided/attacked
    autofulfill.minHappiness       skip below this colony happiness
    autofulfill.craftMissing       queue crafts when stock is short
    autofulfill.equipment          craft tools/armor (level = equipmentLevel)
    autofulfill.skipItems          never craft/send these

  Row colors: red missing/uncraftable, yellow stuck/partial, blue crafting,
  green fully exported, lightBlue domum ornamentum, gray skipped.

  Touch: buttons on the monitor. Keyboard: q quits.
  colony_integrator is read-only: job suggestions are applied MANUALLY (the
  [DO] card shows the exact steps). tryApiAssign() is the hook if AP adds one.
============================================================================]]

----------------------------------------------------------------------------
--* CONFIG
----------------------------------------------------------------------------

local CONFIG = {
  theme = "deepslate",          -- deepslate | smooth_stone | sandstone | basalt
  refreshSeconds = 5,

  enabled = {
    status      = true,
    workforce   = true,
    suggestions = true,
    orders      = true,
    requests    = true,
    legend      = true,
  },

  -- Flexbox layout tree (see header docs).
  layout = {
    dir = "row",
    { dir = "col", flex = 38, min = 20,
      { section = "status",    flex = 8, min = 7, max = 9 },
      { section = "workforce", flex = 7, min = 6, max = 8 },
      { section = "orders",    flex = 10, min = 4 },
      { section = "legend",    flex = 9, min = 4 },
    },
    { dir = "col", flex = 62, min = 24,
      { section = "suggestions", flex = 50, min = 6 },
      { section = "requests",    flex = 50, min = 6 },
    },
  },

  autofulfill = {
    enabled        = true,
    pauseUnderAttack = true,
    minHappiness   = 0,          -- 0 = no happiness gate
    craftMissing   = true,
    equipment      = true,
    equipmentLevel = "Iron",     -- "Iron" | "Diamond" | "Iron and Diamond"
    skipItems      = { "minecraft:enchanted_book" },
  },

  logToFile = false,             -- write auto-fulfill warnings to a log file
}

-- Job scoring: primary/secondary skills per building type.
local JOB_SKILLS = {
  builder = { "Knowledge", "Adaptability" }, deliveryman = { "Agility", "Adaptability" },
  courier = { "Agility", "Adaptability" }, farmer = { "Stamina", "Athletics" },
  fisherman = { "Focus", "Agility" }, lumberjack = { "Strength", "Focus" },
  miner = { "Strength", "Stamina" }, smelter = { "Athletics", "Strength" },
  composter = { "Stamina", "Athletics" }, cook = { "Adaptability", "Knowledge" },
  baker = { "Knowledge", "Dexterity" }, cowboy = { "Athletics", "Stamina" },
  shepherd = { "Athletics", "Stamina" }, swineherd = { "Athletics", "Stamina" },
  chickenherd = { "Adaptability", "Athletics" }, rabbitherd = { "Agility", "Athletics" },
  beekeeper = { "Dexterity", "Adaptability" }, guard = { "Adaptability", "Strength" },
  knight = { "Adaptability", "Strength" }, archer = { "Agility", "Adaptability" },
  blacksmith = { "Knowledge", "Strength" }, stonemason = { "Knowledge", "Dexterity" },
  sawmill = { "Knowledge", "Dexterity" }, carpenter = { "Knowledge", "Dexterity" },
  fletcher = { "Dexterity", "Creativity" }, glassblower = { "Creativity", "Dexterity" },
  dyer = { "Creativity", "Dexterity" }, concretemixer = { "Creativity", "Dexterity" },
  sifter = { "Focus", "Strength" }, florist = { "Dexterity", "Agility" },
  crusher = { "Strength", "Stamina" }, enchanter = { "Mana", "Knowledge" },
  university = { "Knowledge", "Mana" }, researcher = { "Knowledge", "Mana" },
  healer = { "Mana", "Knowledge" }, netherworker = { "Adaptability", "Strength" },
  planter = { "Agility", "Dexterity" },
}
local JOB_MAX_SLOTS = {
  deliveryman = function(l) return math.max(1, l or 1) end,
  courier = function(l) return math.max(1, l or 1) end,
  guard = function(l) return math.max(1, l or 1) end,
  knight = function(l) return math.max(1, l or 1) end,
  archer = function(l) return math.max(1, l or 1) end,
}
local function maxSlotsFor(t, level)
  local v = JOB_MAX_SLOTS[t]
  if type(v) == "function" then return v(level or 1) end
  if type(v) == "number" then return v end
  return 1
end

local REPLACE_MARGIN, PRIMARY_WEIGHT, SECONDARY_WEIGHT, HAPPINESS_MAX = 3, 1.0, 0.5, 10
local MAX_SUGGESTIONS = 60

----------------------------------------------------------------------------
--* THEMES (cc-mek-scada: graphics/themes.lua). brown slot = card body.
----------------------------------------------------------------------------

local THEME_ORDER = { "deepslate", "smooth_stone", "sandstone", "basalt" }

local THEMES = {
  deepslate = {
    palette = {
      [colors.red] = 0xeb6a6c, [colors.orange] = 0xf2b86c, [colors.yellow] = 0xd9cf81,
      [colors.lime] = 0x80ff80, [colors.green] = 0x70e19b, [colors.cyan] = 0x7ccdd0,
      [colors.lightBlue] = 0x99ceef, [colors.blue] = 0x60bcff, [colors.purple] = 0xc38aea,
      [colors.pink] = 0xff7fb8, [colors.magenta] = 0xf980dd, [colors.white] = 0xd9d9d9,
      [colors.lightGray] = 0x949494, [colors.gray] = 0x575757, [colors.black] = 0x262626,
      [colors.brown] = 0x333333,
    },
    sem = {
      screen = colors.black, card = colors.brown, cardTitle = colors.gray, titleText = colors.white,
      text = colors.white, dim = colors.lightGray, accent = colors.blue, accent2 = colors.cyan,
      good = colors.green, warn = colors.orange, bad = colors.red, note = colors.yellow,
      btn = colors.orange, btnText = colors.black, btnOk = colors.green, btnBad = colors.red,
    },
  },
  smooth_stone = {
    palette = {
      [colors.red] = 0xdf4949, [colors.orange] = 0xffb659, [colors.yellow] = 0xfffc79,
      [colors.lime] = 0x80ff80, [colors.green] = 0x4aee8a, [colors.cyan] = 0x34bac8,
      [colors.lightBlue] = 0x6cc0f2, [colors.blue] = 0x0096ff, [colors.purple] = 0xb156ee,
      [colors.pink] = 0xf26ba2, [colors.magenta] = 0xf9488a, [colors.white] = 0xf0f0f0,
      [colors.lightGray] = 0xcacaca, [colors.gray] = 0x575757, [colors.black] = 0x191919,
      [colors.brown] = 0xe6e6e6,
    },
    sem = {
      screen = colors.lightGray, card = colors.brown, cardTitle = colors.gray, titleText = colors.white,
      text = colors.black, dim = colors.gray, accent = colors.blue, accent2 = colors.cyan,
      good = colors.green, warn = colors.orange, bad = colors.red, note = colors.orange,
      btn = colors.orange, btnText = colors.black, btnOk = colors.green, btnBad = colors.red,
    },
  },
  sandstone = {
    palette = {
      [colors.red] = 0xdf4949, [colors.orange] = 0xffb659, [colors.yellow] = 0xf9fb53,
      [colors.lime] = 0x6be551, [colors.green] = 0x16665a, [colors.cyan] = 0x6cc0f2,
      [colors.lightBlue] = 0x6cc0f2, [colors.blue] = 0x0096ff, [colors.purple] = 0x85862c,
      [colors.pink] = 0x672223, [colors.magenta] = 0xe3bc2a, [colors.white] = 0xf0f0f0,
      [colors.lightGray] = 0xb1b8b3, [colors.gray] = 0x575757, [colors.black] = 0x191919,
      [colors.brown] = 0xdcd9ca,
    },
    sem = {
      screen = colors.lightGray, card = colors.brown, cardTitle = colors.gray, titleText = colors.white,
      text = colors.black, dim = colors.gray, accent = colors.blue, accent2 = colors.lightBlue,
      good = colors.lime, warn = colors.orange, bad = colors.red, note = colors.orange,
      btn = colors.orange, btnText = colors.black, btnOk = colors.lime, btnBad = colors.red,
    },
  },
  basalt = {
    palette = {
      [colors.red] = 0xf18486, [colors.orange] = 0xffb659, [colors.yellow] = 0xefe37c,
      [colors.lime] = 0x7ae175, [colors.green] = 0x436b41, [colors.cyan] = 0x7dc6f2,
      [colors.lightBlue] = 0x7dc6f2, [colors.blue] = 0x56aae6, [colors.purple] = 0x757040,
      [colors.pink] = 0x512d2d, [colors.magenta] = 0xe9cd68, [colors.white] = 0xbfbfbf,
      [colors.lightGray] = 0x848794, [colors.gray] = 0x5c5f68, [colors.black] = 0x333333,
      [colors.brown] = 0x4d4e52,
    },
    sem = {
      screen = colors.black, card = colors.brown, cardTitle = colors.gray, titleText = colors.white,
      text = colors.white, dim = colors.lightGray, accent = colors.blue, accent2 = colors.lightBlue,
      good = colors.lime, warn = colors.orange, bad = colors.red, note = colors.yellow,
      btn = colors.orange, btnText = colors.black, btnOk = colors.lime, btnBad = colors.red,
    },
  },
}

local C = {}   -- active semantic colors, filled by applyTheme

----------------------------------------------------------------------------
--* PERIPHERALS
----------------------------------------------------------------------------

local monitor = peripheral.find("monitor")
if not monitor then error("No monitor found", 0) end
local colony = peripheral.find("colony_integrator")
if not colony then error("No colony_integrator found (adjacent or via wired modem)", 0) end
if not colony.isInColony() then error("Integrator is not inside a colony", 0) end
monitor.setTextScale(0.5)

local bridge, storage    -- refreshed each scan (optional)

local function findStorageBridge()
  return peripheral.find("meBridge") or peripheral.find("me_bridge")
      or peripheral.find("rsBridge") or peripheral.find("rs_bridge")
end
local function findStorage()
  for _, side in pairs(peripheral.getNames()) do
    if peripheral.hasType(side, "inventory") then return side end
  end
  return nil
end

----------------------------------------------------------------------------
--* LOG (minimal, off by default)
----------------------------------------------------------------------------

local function logToFile(msg, level)
  if not CONFIG.logToFile then return end
  pcall(function()
    local f = fs.open("colony_dashboard_log.txt", "a")
    if f then f.writeLine(string.format("[%s] %s", level or "INFO", tostring(msg))); f.close() end
  end)
end
local function safeCall(fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then logToFile(err or "error", "ERROR") end
  return ok
end

----------------------------------------------------------------------------
--* THEME APPLY
----------------------------------------------------------------------------

local function applyTheme(name)
  local t = THEMES[name] or THEMES.deepslate
  CONFIG.theme = THEMES[name] and name or "deepslate"
  for c, hex in pairs(t.palette) do monitor.setPaletteColour(c, hex) end
  for k, v in pairs(t.sem) do C[k] = v end
end
local function restorePalette()
  for i = 0, 15 do
    local c = 2 ^ i
    monitor.setPaletteColour(c, term.nativePaletteColour(c))
  end
end

----------------------------------------------------------------------------
--* DRAW PRIMITIVES
----------------------------------------------------------------------------

local W, H = monitor.getSize()
local buttons = {}

local function clearButtons() buttons = {} end
local function addButton(x1, y1, x2, y2, action)
  buttons[#buttons + 1] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, action = action }
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
  monitor.setCursorPos(x, y)
  monitor.setTextColor(fg or C.text)
  monitor.setBackgroundColor(bg or C.screen)
  monitor.write(text)
end

local function fillRect(x, y, w, h, bg)
  if w <= 0 or h <= 0 then return end
  monitor.setBackgroundColor(bg)
  local line = string.rep(" ", w)
  for yy = y, y + h - 1 do
    if yy >= 1 and yy <= H then monitor.setCursorPos(x, yy); monitor.write(line) end
  end
end

-- SCADA card: gray title strip, dark/light body. Returns inner x,y,w,h.
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
    for i = 1, #label do
      local lx = x + i - 1
      if lx > x + w - 1 then break end
      local on = (i <= filled)
      put(lx, y, label:sub(i, i), on and colors.black or C.dim, on and fillColor or C.screen)
    end
  end
end

local function button(x, y, label, bg, fg, action)
  local lbl = " " .. label .. " "
  put(x, y, lbl, fg or C.btnText, bg or C.btn)
  addButton(x, y, x + #lbl - 1, y, action)
  return x + #lbl
end

-- Scroll buttons drawn on the far right of a card title bar.
local function scrollArrows(id, x, y, w, count, visible, scroll)
  local maxOff = math.max(0, count - visible)
  if count <= visible then return scroll end
  if scroll > maxOff then scroll = maxOff end
  put(x + w - 7, y, " \24 ", C.btnText, C.btnOk)
  addButton(x + w - 7, y, x + w - 5, y, function() scroll[id] = math.max(0, (scroll[id] or 0) - 1) end)
  put(x + w - 4, y, " \25 ", C.btnText, C.btnOk)
  addButton(x + w - 4, y, x + w - 2, y, function() scroll[id] = math.min(maxOff, (scroll[id] or 0) + 1) end)
  return scroll
end

----------------------------------------------------------------------------
--* DATA HELPERS
----------------------------------------------------------------------------

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
local function scoreFor(c, p, s) return skillLevel(c, p) * PRIMARY_WEIGHT + skillLevel(c, s) * SECONDARY_WEIGHT end
local function isUnemployed(c)
  if c.isChild == "child" or c.isChild == true then return false end
  local w = c.work
  return not (type(w) == "table" and w.type)
end
local function locStr(loc)
  if type(loc) == "table" then return string.format("%s, %s, %s", tostring(loc.x), tostring(loc.y), tostring(loc.z)) end
  return "unknown"
end
local function trimLead(str) return str and str:match("^%s*(.*)$") or "" end
local function lastWord(str) return string.match(str or "", "%S+$") end

----------------------------------------------------------------------------
--* SUGGESTIONS
----------------------------------------------------------------------------

local function computeSuggestions(citizens, buildings)
  local byId, idle = {}, {}
  for _, c in ipairs(citizens) do byId[c.id] = c end
  for _, c in ipairs(citizens) do if isUnemployed(c) then idle[#idle + 1] = c end end

  local function bestIdleFor(p, s)
    local best, bs = nil, -1
    for _, c in ipairs(idle) do
      local sc = scoreFor(c, p, s)
      if sc > bs then best, bs = c, sc end
    end
    return best, bs
  end

  local out = {}
  for _, b in ipairs(buildings) do
    local jk = b.type or jobKey(b.name)
    if jk and JOB_SKILLS[jk] and b.built ~= false then
      local pr, se = JOB_SKILLS[jk][1], JOB_SKILLS[jk][2]
      local workers = (type(b.citizens) == "table") and b.citizens or {}
      local cand, cs = bestIdleFor(pr, se)
      if cand then
        if #workers < maxSlotsFor(jk, b.level) then
          out[#out + 1] = { kind = "assign", job = jk,
            building = { location = b.location },
            candidate = { name = cand.name, id = cand.id, score = cs }, gain = cs }
        else
          local weak, ws = nil, math.huge
          for _, w in ipairs(workers) do
            local full = byId[w.id]
            local s = full and scoreFor(full, pr, se) or 0
            if s < ws then weak, ws = w, s end
          end
          if weak and (cs - ws) >= REPLACE_MARGIN then
            out[#out + 1] = { kind = "replace", job = jk,
              building = { location = b.location },
              candidate = { name = cand.name, id = cand.id, score = cs },
              target = { name = weak.name, id = weak.id, score = ws }, gain = cs - ws }
          end
        end
      end
    end
  end
  table.sort(out, function(a, b) return a.gain > b.gain end)
  while #out > MAX_SUGGESTIONS do table.remove(out) end
  return out
end

----------------------------------------------------------------------------
--* REQUESTS + CCxM AUTO-FULFILL
----------------------------------------------------------------------------

local function isEquipment(desc)
  local kw = { "Sword ", "Bow ", "Pickaxe ", "Axe ", "Shovel ", "Hoe ", "Shears ",
    "Helmet ", "Chestplate ", "Leggings ", "Boots ", "Shield" }
  for _, k in ipairs(kw) do if string.find(desc, k) then return true end end
  return false
end

local function categorizeRequests()
  local equipment, builder, others = {}, {}, {}
  for _, req in ipairs(colony.getRequests() or {}) do
    if req.items and req.items[1] then
      local name = req.name
      local target = req.target or ""
      local desc = req.desc or ""
      local count = req.count
      local item_displayName = trimLead(req.items[1].displayName)
      local item_name = req.items[1].name
      local isEq = isEquipment(desc)
      local base = {
        name = name, target = target, count = count,
        item_displayName = item_displayName, item_name = item_name, desc = desc,
        provided = 0, isCraftable = false, equipment = isEq,
        displayColor = colors.white, level = "",
      }
      if isEq then
        local levelTable = {
          ["and with maximal level: Leather"] = "Leather", ["and with maximal level: Stone"] = "Stone",
          ["and with maximal level: Chain"] = "Chain", ["and with maximal level: Gold"] = "Gold",
          ["and with maximal level: Iron"] = "Iron", ["and with maximal level: Diamond"] = "Diamond",
          ["with maximal level: Wood or Gold"] = "Wood or Gold",
        }
        local level = "Any Level"
        for pat, mapped in pairs(levelTable) do if string.find(desc, pat) then level = mapped; break end end
        base.name = level .. " " .. name
        base.level = level
        equipment[#equipment + 1] = base
      elseif string.find(target, "Builder") then
        builder[#builder + 1] = base
      else
        others[#others + 1] = base
      end
    else
      logToFile("Skipping request with no items: " .. (req.name or "unknown"))
    end
  end
  return equipment, builder, others
end

local function equipmentCraft(name, level, item_name)
  local want = CONFIG.autofulfill.equipmentLevel
  if item_name == "minecraft:bow" then return item_name, true end
  if (level == "Iron" or level == "Iron and Diamond" or level == "Any Level")
      and (want == "Iron" or want == "Iron and Diamond") then
    if level == "Any Level" then level = "Iron" end
    return string.lower("minecraft:" .. level .. "_" .. lastWord(name)), true
  elseif (level == "Diamond" or level == "Iron and Diamond" or level == "Any Level") and want == "Diamond" then
    if level == "Any Level" then level = "Diamond" end
    return string.lower("minecraft:" .. level .. "_" .. lastWord(name)), true
  end
  return item_name, false
end

local quantityField = nil
local function detectQuantityField(itemName)
  local ok, data = pcall(function() return bridge.getItem({ name = itemName }) end)
  if ok and data then
    if type(data.amount) == "number" then return "amount" end
    if type(data.count) == "number" then return "count" end
  end
  return nil
end

local function handleRequests(list)
  local af = CONFIG.autofulfill
  local skip = {}
  for _, n in ipairs(af.skipItems or {}) do skip[n] = true end

  for _, item in ipairs(list) do
    local stored, crafting, eqOk = 0, false, true
    if skip[item.item_name] then
      item.displayColor = colors.gray
      goto continue
    end
    if item.equipment then item.item_name, eqOk = equipmentCraft(item.name, item.level, item.item_name) end
    if not quantityField then quantityField = detectQuantityField(item.item_name) end

    local gotItem = pcall(function()
      local d = bridge.getItem({ name = item.item_name })
      stored = d[quantityField] or 0
      item.isCraftable = d.isCraftable
    end)
    if not gotItem then
      logToFile(item.item_displayName .. " not in system or craftable.")
      item.displayColor = colors.red
      if string.sub(item.item_name, 1, 17) == "domum_ornamentum:" then item.displayColor = colors.lightBlue end
      goto continue
    end

    if stored ~= 0 then
      local exported = pcall(function()
        item.provided = bridge.exportItemToPeripheral({ name = item.item_name, count = item.count }, storage)
      end) or pcall(function()
        item.provided = bridge.exportItem({ name = item.item_name, count = item.count }, storage)
      end)
      if not exported then item.displayColor = colors.yellow end
      if item.provided == item.count then
        item.displayColor = colors.green
        if string.sub(item.item_name, 1, 17) == "domum_ornamentum:" then item.displayColor = colors.lightBlue end
      else
        item.displayColor = colors.yellow
      end
    end

    if not af.equipment and item.equipment then goto continue end
    if not af.craftMissing then goto continue end

    if (item.provided < item.count) and item.isCraftable and eqOk then
      safeCall(function() crafting = bridge.isItemCrafting({ name = item.item_name }) end)
      if crafting then item.displayColor = colors.blue; goto continue end
    end

    if not crafting and item.isCraftable and (item.provided < item.count) then
      local ok = safeCall(function()
        return bridge.craftItem({ name = item.item_name, count = item.count - item.provided })
      end)
      if not ok then
        item.displayColor = colors.yellow
        goto continue
      end
      item.displayColor = colors.blue
    end

    ::continue::
  end
end

----------------------------------------------------------------------------
--* GATHER DATA
----------------------------------------------------------------------------

local function gatherData()
  local function g(fn, d) local ok, v = pcall(fn); if ok and v ~= nil then return v else return d end end
  local citizens  = g(function() return colony.getCitizens() end, {})
  local buildings = g(function() return colony.getBuildings() end, {})
  local orders    = g(function() return colony.getWorkOrders() end, {})
  local visitors  = g(function() return colony.getVisitors() end, {})

  local employed, idle = 0, 0
  for _, c in ipairs(citizens) do if isUnemployed(c) then idle = idle + 1 else employed = employed + 1 end end

  local d = {
    name = g(colony.getColonyName, "?"), id = g(colony.getColonyID, "?"),
    happiness = g(colony.getHappiness, 0),
    pop = g(colony.amountOfCitizens, #citizens), maxPop = g(colony.maxOfCitizens, 0),
    attack = g(colony.isUnderAttack, false), raid = g(colony.isUnderRaid, false),
    sites = g(colony.amountOfConstructionSites, 0), graves = g(colony.amountOfGraves, 0),
    total = #citizens, employed = employed, idle = idle, buildings = #buildings,
    visitors = type(visitors) == "table" and #visitors or 0,
    orders = type(orders) == "table" and orders or {},
    suggestions = computeSuggestions(citizens, buildings),
  }

  -- Requests + optional auto-fulfill (CCxM).
  bridge = findStorageBridge()
  storage = findStorage()
  local eq, bd, ot = {}, {}, {}
  pcall(function() eq, bd, ot = categorizeRequests() end)

  local af = CONFIG.autofulfill
  local mode, canAuto = "MANUAL", false
  if af.enabled and bridge and storage then
    canAuto = true
    if af.pauseUnderAttack and (d.attack or d.raid) then canAuto, mode = false, "PAUSED raid" end
    if canAuto and af.minHappiness > 0 and d.happiness < af.minHappiness then canAuto, mode = false, "PAUSED low happy" end
    if canAuto then
      handleRequests(eq); handleRequests(bd); handleRequests(ot)
      mode = "AUTO"
    end
  elseif not (bridge and storage) then
    mode = "no bridge"
  end

  local all = {}
  for _, l in ipairs({ bd, eq, ot }) do for _, it in ipairs(l) do all[#all + 1] = it end end
  d.requests = all
  d.reqMode = mode
  return d
end

----------------------------------------------------------------------------
--* STATE
----------------------------------------------------------------------------

local state = {
  data = nil, msg = "", countdown = CONFIG.refreshSeconds,
  quit = false, needScan = false, modal = nil,
  scroll = {},            -- per-section scroll offsets
  themeIdx = 1,
}
for i, n in ipairs(THEME_ORDER) do if n == CONFIG.theme then state.themeIdx = i end end

----------------------------------------------------------------------------
--* SECTIONS
----------------------------------------------------------------------------

local function secStatus(x, y, w, h)
  local d = state.data
  local cx, cy, cw = card(x, y, w, h, "COLONY STATUS")
  local row = cy
  local hc = d.happiness >= 7 and C.good or (d.happiness >= 4 and C.warn or C.bad)
  put(cx, row, "Happiness", C.dim, C.card); row = row + 1
  hbar(cx, row, cw, d.happiness / HAPPINESS_MAX, hc, string.format(" %.1f / %d", d.happiness, HAPPINESS_MAX)); row = row + 1
  put(cx, row, "Population", C.dim, C.card); row = row + 1
  hbar(cx, row, cw, d.maxPop > 0 and d.pop / d.maxPop or 0, C.accent, string.format(" %d / %d", d.pop, d.maxPop)); row = row + 1
  local threat = d.attack and "UNDER ATTACK" or (d.raid and "RAID INCOMING" or "SECURE")
  put(cx, row, "Threat", C.dim, C.card)
  put(cx + cw - #threat, row, threat, (d.attack or d.raid) and C.bad or C.good, C.card); row = row + 1
  local sg = string.format("%d sites  %d graves", d.sites, d.graves)
  put(cx, row, "Constr.", C.dim, C.card)
  put(cx + cw - #sg, row, sg, d.graves > 0 and C.warn or C.text, C.card)
end

local function secWorkforce(x, y, w, h)
  local d = state.data
  local cx, cy, cw = card(x, y, w, h, "WORKFORCE")
  local function stat(r, label, val, col)
    put(cx, cy + r, label, C.dim, C.card)
    local s = tostring(val)
    put(cx + cw - #s, cy + r, s, col or C.text, C.card)
  end
  stat(0, "Citizens", d.total, C.text)
  stat(1, "Employed", d.employed, C.good)
  stat(2, "Idle", d.idle, d.idle > 0 and C.warn or C.dim)
  stat(3, "Visitors", d.visitors, C.accent2)
  stat(4, "Buildings", d.buildings, C.text)
end

local function secSuggestions(x, y, w, h)
  local d = state.data
  local list = d.suggestions
  local cx, cy, cw, ch = card(x, y, w, h, string.format("SUGGESTIONS (%d)", #list))
  state.scroll = scrollArrows("suggestions", x, y, w, #list, ch, state.scroll)
  if #list == 0 then put(cx, cy, "All jobs optimally staffed.", C.good, C.card); return end
  local off = state.scroll.suggestions or 0
  for i = 1, ch do
    local s = list[i + off]
    if not s then break end
    local ry = cy + i - 1
    button(cx, ry, "DO", C.btn, C.btnText, function() state.modal = { kind = "apply", sug = s } end)
    local tx = cx + 5
    if s.kind == "assign" then
      put(tx, ry, string.format("Assign %s \26 %s (+%d)", s.candidate.name, s.job, s.gain), C.good, C.card)
    else
      put(tx, ry, string.format("Swap %s\26%s @%s (+%d)", s.target.name, s.candidate.name, s.job, s.gain), C.warn, C.card)
    end
  end
end

local function secOrders(x, y, w, h)
  local d = state.data
  local list = d.orders
  local cx, cy, cw, ch = card(x, y, w, h, string.format("WORK ORDERS (%d)", #list))
  state.scroll = scrollArrows("orders", x, y, w, #list, ch, state.scroll)
  if #list == 0 then put(cx, cy, "None queued.", C.dim, C.card); return end
  local off = state.scroll.orders or 0
  for i = 1, ch do
    local o = list[i + off]
    if not o then break end
    local kind = tostring(o.workOrderType or o.type or "?"):sub(1, 7)
    local tgt = jobKey(o.buildingName or o.structureName or o.name or "?") or "?"
    local lvl = o.targetLevel and ("L" .. o.targetLevel) or ""
    local claimed = o.isClaimed and "\7" or " "
    put(cx, cy + i - 1, string.format("%s%-7s %s %s", claimed, kind, tgt, lvl), o.isClaimed and C.text or C.dim, C.card)
  end
end

local function secRequests(x, y, w, h)
  local d = state.data
  local list = d.requests
  local modeCol = (d.reqMode == "AUTO") and C.good
      or (d.reqMode:find("PAUSED") and C.warn) or C.dim
  local cx, cy, cw, ch = card(x, y, w, h, string.format("OPEN REQUESTS (%d) %s", #list, d.reqMode))
  -- recolor the mode word
  put(x + 1 + #string.format("OPEN REQUESTS (%d) ", #list), y, d.reqMode, modeCol, C.cardTitle)
  state.scroll = scrollArrows("requests", x, y, w, #list, ch, state.scroll)
  if #list == 0 then put(cx, cy, "No open requests.", C.good, C.card); return end
  local off = state.scroll.requests or 0
  for i = 1, ch do
    local it = list[i + off]
    if not it then break end
    local ry = cy + i - 1
    local qty = (it.provided and it.provided > 0) and (it.provided .. "/" .. it.count) or tostring(it.count)
    local tgt = tostring(it.target or "")
    local left = qty .. " " .. it.name
    local room = cw - #tgt - 1
    put(cx, ry, left:sub(1, math.max(0, room)), it.displayColor or C.text, C.card)
    if #tgt > 0 then put(cx + cw - #tgt, ry, tgt, C.dim, C.card) end
  end
end

local function secLegend(x, y, w, h)
  local cx, cy = card(x, y, w, h, "LEGEND")
  local entries = {
    { colors.red, "missing / uncraftable" }, { colors.yellow, "stuck / partial" },
    { colors.blue, "crafting" }, { colors.green, "fully exported" },
    { colors.lightBlue, "domum ornamentum" }, { colors.gray, "skipped" },
  }
  for i, e in ipairs(entries) do
    if cy + i - 1 > y + h - 2 then break end
    put(cx, cy + i - 1, "\7 ", e[1], C.card)
    put(cx + 2, cy + i - 1, e[2], C.dim, C.card)
  end
end

local SECTIONS = {
  status      = { title = "Colony Status", draw = secStatus },
  workforce   = { title = "Workforce",     draw = secWorkforce },
  suggestions = { title = "Suggestions",   draw = secSuggestions },
  orders      = { title = "Work Orders",   draw = secOrders },
  requests    = { title = "Open Requests", draw = secRequests },
  legend      = { title = "Legend",        draw = secLegend },
}
local SECTION_ORDER = { "status", "workforce", "suggestions", "orders", "requests", "legend" }

----------------------------------------------------------------------------
--* LAYOUT ENGINE (flexbox-like)
----------------------------------------------------------------------------

local GAP = 1

local function isEnabled(id) return CONFIG.enabled[id] ~= false end

local function countVisible(node)
  if node.section then return isEnabled(node.section) and 1 or 0 end
  local n = 0
  for _, ch in ipairs(node) do n = n + countVisible(ch) end
  return n
end

local function layoutNode(node, x, y, w, h)
  if w <= 0 or h <= 0 then return end
  if node.section then
    if not isEnabled(node.section) then return end
    local sec = SECTIONS[node.section]
    if sec then sec.draw(x, y, w, h) end
    return
  end

  local horizontal = (node.dir == "row")
  local vis = {}
  for _, ch in ipairs(node) do if countVisible(ch) > 0 then vis[#vis + 1] = ch end end
  local n = #vis
  if n == 0 then return end

  local main = horizontal and w or h
  local avail = main - GAP * (n - 1)
  if avail < n then avail = math.max(n, main) end

  local sizes = {}
  local remaining, remFlex = avail, 0
  for _, ch in ipairs(vis) do remFlex = remFlex + (ch.flex or 1) end
  for i, ch in ipairs(vis) do
    local flex = ch.flex or 1
    local raw = (remFlex > 0) and math.floor(remaining * flex / remFlex + 0.5) or 0
    local mn, mx = ch.min or 1, ch.max or math.huge
    if raw < mn then raw = mn end
    if raw > mx then raw = mx end
    if raw > remaining then raw = math.max(0, remaining) end
    sizes[i] = raw
    remaining = remaining - raw
    remFlex = remFlex - flex
  end
  -- hand any leftover to the last child (fills rounding gaps)
  if remaining > 0 and n > 0 then sizes[n] = sizes[n] + remaining end

  local pos = horizontal and x or y
  for i, ch in ipairs(vis) do
    local s = sizes[i]
    if s > 0 then
      if horizontal then layoutNode(ch, pos, y, s, h) else layoutNode(ch, x, pos, w, s) end
      pos = pos + s + GAP
    end
  end
end

----------------------------------------------------------------------------
--* HEADER / FOOTER / OVERLAYS
----------------------------------------------------------------------------

local function drawFooter()
  local d = state.data
  fillRect(1, H, W, 1, C.cardTitle)
  local x = 2
  x = button(x, H, "REFRESH", C.btnOk, C.btnText, function() state.needScan = true end) + 1
  x = button(x, H, "THEME", C.accent, colors.black, function()
    state.themeIdx = (state.themeIdx % #THEME_ORDER) + 1
    applyTheme(THEME_ORDER[state.themeIdx])
  end) + 1
  x = button(x, H, "SECTIONS", C.btn, C.btnText, function() state.modal = { kind = "sections" } end) + 2
  -- colony/theme/countdown live on the right of the footer (header removed)
  local right = string.format("%s #%s  %s  %02ds", tostring(d.name), tostring(d.id), CONFIG.theme, state.countdown)
  put(W - #right - 1, H, right, C.dim, C.cardTitle)
  if state.msg ~= "" and x < W - #right - 2 then put(x, H, state.msg, C.dim, C.cardTitle) end
end

local function tryApiAssign(_) return false, "API read-only; hire manually." end

local function drawApplyModal(s)
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
      { "Job:      " .. s.job, C.text }, { "Building: " .. locStr(s.building.location), C.text },
      { "Hire:     " .. s.candidate.name .. " (" .. s.candidate.score .. ")", C.good },
      { "", C.text }, { "Manual steps:", C.accent2 },
      { " 1. Go to " .. locStr(s.building.location), C.dim },
      { " 2. Open hut GUI \26 Hire/Fire", C.dim }, { " 3. Slot in " .. s.candidate.name, C.dim },
    }
  else
    lines = {
      { "Job:      " .. s.job, C.text }, { "Building: " .. locStr(s.building.location), C.text },
      { "Fire:     " .. s.target.name .. " (" .. s.target.score .. ")", C.bad },
      { "Hire:     " .. s.candidate.name .. " (" .. s.candidate.score .. ")", C.good },
      { "Manual steps:", C.accent2 }, { " 1. Go to " .. locStr(s.building.location), C.dim },
      { " 2. Open GUI \26 Hire/Fire", C.dim },
      { " 3. Fire " .. s.target.name .. ", hire " .. s.candidate.name, C.dim },
    }
  end
  for _, ln in ipairs(lines) do
    if row > my + mh - 3 then break end
    put(cx, row, ln[1], ln[2], C.card); row = row + 1
  end
  put(cx, my + mh - 2, ok and "API applied." or apiMsg, C.dim, C.card)
  local bx = cx
  bx = button(bx, my + mh - 1, "HANDLED", C.btnOk, C.btnText, function()
    for i, x in ipairs(state.data.suggestions) do if x == s then table.remove(state.data.suggestions, i); break end end
    state.modal = nil
  end) + 1
  button(bx, my + mh - 1, "BACK", colors.lightGray, colors.black, function() state.modal = nil end)
end

local function drawSectionsModal()
  local mw = math.min(W - 4, 34)
  local mh = math.min(H - 4, #SECTION_ORDER + 4)
  local mx = math.floor((W - mw) / 2) + 1
  local my = math.floor((H - mh) / 2) + 1
  local cx, cy = card(mx, my, mw, mh, "SECTIONS")
  put(cx, cy, "Tap to toggle visibility:", C.dim, C.card)
  for i, id in ipairs(SECTION_ORDER) do
    local ry = cy + i
    if ry > my + mh - 2 then break end
    local on = isEnabled(id)
    local box = on and "[x]" or "[ ]"
    put(cx, ry, box, on and C.good or C.dim, C.card)
    put(cx + 4, ry, SECTIONS[id].title, on and C.text or C.dim, C.card)
    addButton(cx, ry, cx + mw - 3, ry, function() CONFIG.enabled[id] = not on end)
  end
  button(cx, my + mh - 1, "CLOSE", C.btnOk, C.btnText, function() state.modal = nil end)
end

----------------------------------------------------------------------------
--* REDRAW
----------------------------------------------------------------------------

local function redraw()
  W, H = monitor.getSize()
  monitor.setBackgroundColor(C.screen)
  monitor.clear()
  clearButtons()
  if not state.data then put(2, 2, "Scanning...", C.dim); return end
  layoutNode(CONFIG.layout, 1, 1, W, H - 1)
  drawFooter()
  if state.modal then
    clearButtons() -- overlay captures all clicks
    if state.modal.kind == "apply" then drawApplyModal(state.modal.sug)
    elseif state.modal.kind == "sections" then drawSectionsModal() end
  end
end

----------------------------------------------------------------------------
--* MAIN LOOP
----------------------------------------------------------------------------

local function rescan()
  local ok, res = pcall(gatherData)
  if ok then
    state.data = res
    state.msg = string.format("%d sugg  %d req", #res.suggestions, #res.requests)
  else
    state.msg = "Scan error: " .. tostring(res)
  end
  state.needScan = false
  state.countdown = CONFIG.refreshSeconds
end

applyTheme(CONFIG.theme)
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
    redraw()
  end
end

restorePalette()
monitor.setBackgroundColor(colors.black); monitor.clear(); monitor.setCursorPos(1, 1)
term.clear(); term.setCursorPos(1, 1)
print("colony_dashboard stopped.")

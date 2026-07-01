---@diagnostic disable: undefined-global
--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++--

--**                ULTIMATE CC X MINECOLONIES PROGRAM                  **--
--**        UI reworked to the SCADA-style card system (deepslate)     **--

--++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++--

----------------------------------------------------------------------------
--* VARIABLES
----------------------------------------------------------------------------

-- Refresh interval in seconds (countdown shown in the header). Default: 15
local refreshInterval = 15

-- If true, Advanced Computer will show all Log information. Default: false
local bShowInGameLog = false

local bDisableLog = false

-- Name of the log file e.g. "logFileName"_log.txt
local logFileName = "CCxM"

----------------------------------------------------------------------------
--* LOG  (FATAL ERROR WARN_ INFO_ DEBUG TRACE)
----------------------------------------------------------------------------

-- Keeps track of the revisions
local VERSION = 1.15

function logToFile(message, level, bPrint)
    if not bDisableLog then
        level = level or "INFO_"
        bPrint = bPrint or bShowInGameLog

        local logFolder = logFileName .. "_logs"
        local logFilePath = logFolder .. "/" .. logFileName .. "_log_latest.txt"

        if not fs.exists(logFolder) then
            local success, err = pcall(function() fs.makeDir(logFolder) end)
            if not success then
                print(string.format("Failed to create log folder: %s", err))
                return
            end
        end

        local success, err = pcall(function()
            local logFile = fs.open(logFilePath, "a")
            if logFile then
                logFile.writeLine(string.format("[%s] [%s] %s", os.date("%Y-%m-%d %H:%M:%S"), level, message))
                logFile.close()
            else
                error("Unable to open log file.")
            end
        end)

        if not success then
            print(string.format("Error writing to log file: %s", err))
            return
        end

        if bPrint then
            if level == "ERROR" or level == "FATAL" then
                print("")
            end

            print(string.format("%s", message))

            if level == "ERROR" or level == "FATAL" then
                print("")
            end
        end

        free = fs.getFreeSpace("/")

        logCounter = (logCounter or 0) + 1
        if logCounter >= 250 or free < 80000 then
            rotateLogs(logFolder, logFilePath)
            logCounter = 0
        end
    end
end

function rotateLogs(logFolder, logFilePath)
    local maxLogs = 2

    local timestamp = os.date("%Y-%m-%d_%H-%M-%S")
    local archivedLog = string.format("%s/log_%s.txt", logFolder, timestamp)

    local success, err = pcall(function()
        if fs.exists(logFilePath) then
            fs.move(logFilePath, archivedLog)
        end
    end)

    if not success then
        print(string.format("Failed to rotate log file: %s", err))
        return
    end

    local logs = fs.list(logFolder)
    table.sort(logs)

    local logCount = #logs
    while logCount > maxLogs do
        local oldestLog = logFolder .. "/" .. logs[1]
        local deleteSuccess, deleteErr = pcall(function() fs.delete(oldestLog) end)
        if not deleteSuccess then
            print(string.format("Failed to delete old log file: %s", deleteErr))
            break
        end
        table.remove(logs, 1)
        logCount = logCount - 1
    end
end

----------------------------------------------------------------------------
--* ERROR-HANDLING FUNCTION
----------------------------------------------------------------------------

function safeCall(func, ...)
    local success, result = pcall(func, ...)
    if not success then
        logToFile((result or "Unknown error"), "ERROR")
        return false
    end
    return true
end

----------------------------------------------------------------------------
--* DEBUG FUNCTIONS
----------------------------------------------------------------------------

function debugDiskSpace()
    local free = fs.getFreeSpace("/")
    print("Free disk space:", free, "bytes")

    for _, f in ipairs(fs.list("/")) do
        local path = "/" .. f
        if not fs.isDir(path) then
            print(path, fs.getSize(path))
        end
    end
end

function debugPrintTableToLog(t, logFile, indent)
    indent = indent or 0
    local prefix = string.rep("  ", indent)

    for key, value in pairs(t) do
        if type(value) == "table" then
            logFile:write(prefix .. tostring(key) .. ":\n")
            debugPrintTableToLog(value, logFile, indent + 1)
        else
            logFile:write(prefix .. tostring(key) .. ": " .. tostring(value) .. "\n")
        end
    end
end

function debugTableTest()
    local logFile = io.open("M_log.txt", "w")
    if not logFile then
        error("Could not open log file for writing")
    end

    local success, result = pcall(function()
        local requests = peripheral.find("colony_integrator").getRequests()
        debugPrintTableToLog(requests, logFile)
    end)

    if not success then
        logFile:write("Error: " .. tostring(result) .. "\n")
    end

    logFile:close()

    print(result or "Table logged successfully")
end

----------------------------------------------------------------------------
--* GENERIC HELPER FUNCTIONS
----------------------------------------------------------------------------

function trimLeadingWhitespace(str)
    return str:match("^%s*(.*)$")
end

function getLastWord(str)
    return string.match(str, "%S+$")
end

function tableToString(tbl, indent)
    indent = indent or 0
    local toString = string.rep("  ", indent) .. "{\n"
    for key, value in pairs(tbl) do
        local formattedKey = type(key) == "string" and string.format("%q", key) or tostring(key)
        if type(value) == "table" then
            toString = toString ..
                string.rep("  ", indent + 1) ..
                "[" .. formattedKey .. "] = " .. tableToString(value, indent + 1) .. ",\n"
        else
            local formattedValue = type(value) == "string" and string.format("%q", value) or tostring(value)
            toString = toString ..
                string.rep("  ", indent + 1) .. "[" .. formattedKey .. "] = " .. formattedValue .. ",\n"
        end
    end
    return toString .. string.rep("  ", indent) .. "}"
end

function writeToLogFile(fileName, equipment_list, builder_list, others_list)
    local file = io.open(fileName, "w")

    if not file then
        error("Could not open file for writing: " .. fileName)
    end

    file:write("Equipment List:\n")
    file:write(tableToString(equipment_list) .. "\n\n")

    file:write("Builder List:\n")
    file:write(tableToString(builder_list) .. "\n\n")

    file:write("Others List:\n")
    file:write(tableToString(others_list) .. "\n\n")

    file:close()
end

----------------------------------------------------------------------------
--* CHECK REQUIREMENTS
----------------------------------------------------------------------------

local monitor = peripheral.find("monitor")
local colony
local bridge
local storage

function getPeripheral(type)
    local peripheral = peripheral.find(type)
    if not peripheral then
        return nil
    end

    return peripheral
end

function updatePeripheralMonitor()
    monitor = getPeripheral("monitor")

    if monitor then
        return true
    else
        return false
    end
end

function checkMonitorSize()
    monitor.setTextScale(0.5)
    local width, height = monitor.getSize()

    if width < 79 or height < 38 then
        logToFile("Use more Monitors! (min 4x3)", "WARN_")

        return false
    end

    return true
end

function updatePeripheralColonyIntegrator()
    colony = getPeripheral("colonyIntegrator") or getPeripheral("colony_integrator")

    if colony then
        return true
    else
        return false
    end
end

function getStorageBridge()
    local meBridge = getPeripheral("meBridge") or getPeripheral("me_bridge")
    local rsBridge = getPeripheral("rsBridge") or getPeripheral("rs_bridge")

    if meBridge then
        return meBridge
    elseif rsBridge then
        return rsBridge
    else
        logToFile("Neither ME Storage Bridge nor RS Storage Bridge found.", "WARN_")

        return nil
    end
end

function updatePeripheralStorageBridge()
    bridge = getStorageBridge()

    if bridge then
        return true
    else
        return false
    end
end

function autodetectStorage()
    for _, side in pairs(peripheral.getNames()) do
        if peripheral.hasType(side, "inventory") then
            return side
        end
    end
    logToFile("No storage container detected!", "WARN_")

    return nil
end

function updatePeripheralStorage()
    storage = autodetectStorage()

    if storage then
        return true
    else
        return false
    end
end

----------------------------------------------------------------------------
--* THEME: cc-mek-scada "deepslate" palette (same UI system as the advisor)
----------------------------------------------------------------------------

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
    [colors.brown]     = 0x333333, -- repurposed: dark card body
}

local C = {
    screen    = colors.black,
    card      = colors.brown,
    cardTitle = colors.gray,
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

function applyPalette()
    if not monitor then return end
    for c, hex in pairs(PALETTE) do monitor.setPaletteColour(c, hex) end
end

function restorePalette()
    if not monitor then return end
    for i = 0, 15 do
        local c = 2 ^ i
        monitor.setPaletteColour(c, term.nativePaletteColour(c))
    end
end

----------------------------------------------------------------------------
--* DRAW PRIMITIVES (advisor UI system)
----------------------------------------------------------------------------

local W, H = 79, 38
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

-- SCADA-style card: gray title strip, dark body. Returns inner x,y,w,h.
local function card(x, y, w, h, title)
    fillRect(x, y, w, h, C.card)
    fillRect(x, y, w, 1, C.cardTitle)
    put(x + 1, y, title, C.titleText, C.cardTitle)
    return x + 1, y + 1, w - 2, h - 2
end

local function button(x, y, label, bg, fg, action)
    local lbl = " " .. label .. " "
    put(x, y, lbl, fg or C.btnText, bg or C.btn)
    addButton(x, y, x + #lbl - 1, y, action)
    return x + #lbl
end

----------------------------------------------------------------------------
--* ART
----------------------------------------------------------------------------

local artUltimateCCxM_Logo = [[
 _   _ _ _   _                 _
| | | | | |_(_)_ __ ___   __ _| |_ ___
| | | | | __| | '_ ` _ \ / _` | __/ _ \
| |_| | | |_| | | | | | | (_| | ||  __/
 \____|_____|_|_| |_|___|_____|\__\___|
 / ___/ ___|__  __|  \/  (_)_ __   ___
| |  | |    \ \/ /| |\/| | | '_ \ / _ \
| |__| |___  >  < | |  | | | | | |  __/
 \____\____|/_/\_\|_|  |_|_|_| |_|\___|
 / ___|___ | | ___  _ __ (_) ___  ___
| |   / _ \| |/ _ \| '_ \| |/ _ \/ __|
| |__| (_) | | (_) | | | | |  __/\__ \
 \____\___/|_|\___/|_| |_|_|\___||___/
]]

----------------------------------------------------------------------------
--* MONITOR OR TERMINAL OUTPUT
----------------------------------------------------------------------------

function resetDefault(screen)
    screen.setTextColor(colors.white)
    screen.setBackgroundColor(colors.black)
    screen.setCursorPos(1, 1)
    screen.clear()
end

function drawLoadingBar(screen, x, y, width, progress, bgColor, barColor)
    screen.setBackgroundColor(bgColor or colors.gray)
    screen.setTextColor(colors.white)
    screen.setCursorPos(x, y)

    screen.write(string.rep(" ", width))

    local filledWidth = math.floor(progress * width)
    screen.setCursorPos(x, y)
    screen.setBackgroundColor(barColor or colors.green)
    screen.write(string.rep(" ", filledWidth))
end

----------------------------------------------------------------------------
--* MONITOR LOADING (kept feature)
----------------------------------------------------------------------------

function monitorDisplayArt(asciiArt, monitor_)
    monitor_.clear()

    local x, y = 1, 2

    for line in asciiArt:gmatch("[^\n]+") do
        monitor_.setCursorPos(x, y)
        monitor_.write(line)
        y = y + 1
    end
end

function monitorLoadingAnimation()
    resetDefault(monitor)

    monitor.setTextScale(1)

    local width, height = monitor.getSize()

    local barWidth = math.floor(width * 0.9)
    local barX = math.floor((width - barWidth) / 2 + 1)
    local barHeight = 17

    monitor.setTextColor(colors.orange)
    monitor.setCursorPos(1, 1)

    monitorDisplayArt(artUltimateCCxM_Logo, monitor)

    local barSpeed = 30
    for i = 0, barSpeed do
        local progress = i / barSpeed
        drawLoadingBar(monitor, barX, barHeight, barWidth, progress, colors.gray, colors.orange)
        sleep(0.1)
    end

    resetDefault(monitor)

    monitor.setTextScale(0.5)
end

----------------------------------------------------------------------------
--* TERMINAL OUTPUT (kept feature: requirements screen + log header)
----------------------------------------------------------------------------
local termWidth, termHeight = term.getSize()
local needTermDrawRequirements = true
local needTermDrawRequirements_executed = false

function termDisplayArt(asciiArt)
    term.clear()

    local x, y = 6, 2

    for line in asciiArt:gmatch("[^\n]+") do
        term.setCursorPos(x, y)
        term.write(line)
        y = y + 1
    end
end

function termLoadingAnimation()
    resetDefault(term)

    local width, height = term.getSize()

    local barWidth = math.floor(width * 0.8)
    local barX = math.floor((width - barWidth) / 2 + 1)
    local barHeight = math.floor(height * 0.9)

    term.setTextColor(colors.orange)
    term.setCursorPos(1, 1)

    termDisplayArt(artUltimateCCxM_Logo)

    local barSpeed = 25
    for i = 0, barSpeed do
        local progress = i / barSpeed
        drawLoadingBar(term, barX, barHeight, barWidth, progress, colors.gray, colors.orange)
        sleep(0.1)
    end

    resetDefault(term)
end

function termDrawProgramReq_helper(y, isRequirementMet)
    if isRequirementMet then
        term.setTextColor(colors.green)
        term.setCursorPos(49, y)
        term.write("[O]")
    else
        term.setTextColor(colors.red)
        term.setCursorPos(49, y)
        term.write("[X]")
    end

    term.setTextColor(colors.white)
end

function termDrawProgramReq_Header()
    local text_Divider = "-------------------------------------------------------"
    term.setCursorPos(math.floor((termWidth - #text_Divider) / 2) + 1, 4)

    term.write(text_Divider)

    local text_Requirements = "\187 Program Requirements \171"
    term.setCursorPos(math.floor((termWidth - #text_Requirements) / 2) + 1, 2)

    textutils.slowWrite(text_Requirements, 16)
end

function termDrawCheckRequirements()
    if not needTermDrawRequirements_executed then
        term.clear()
    end

    local text_Monitor_1 = "\16 Monitor attached"
    term.setCursorPos(2, 6)
    term.write(text_Monitor_1)

    local text_Monitor_2 = "\16 Monitor size (min 4x3)"
    term.setCursorPos(2, 8)
    term.write(text_Monitor_2)

    local text_Colony_1 = "\16 Colony Integrator attached"
    term.setCursorPos(2, 10)
    term.write(text_Colony_1)

    local text_Colony_2 = "\16 Colony Integrator in a colony"
    term.setCursorPos(2, 12)
    term.write(text_Colony_2)

    local text_StoargeBridge = "\16 ME or RS Bridge attached"
    term.setCursorPos(2, 14)
    term.write(text_StoargeBridge)

    local text_Stoarge = "\16 Storage/Warehouse attached"
    term.setCursorPos(2, 16)
    term.write(text_Stoarge)

    if updatePeripheralMonitor() then
        termDrawProgramReq_helper(6, true)

        if checkMonitorSize() then
            termDrawProgramReq_helper(8, true)
        else
            termDrawProgramReq_helper(8, false)
        end
    else
        termDrawProgramReq_helper(6, false)
        termDrawProgramReq_helper(8, false)
    end

    if updatePeripheralColonyIntegrator() then
        termDrawProgramReq_helper(10, true)

        if colony.isInColony() then
            termDrawProgramReq_helper(12, true)
        else
            termDrawProgramReq_helper(12, false)
        end
    else
        termDrawProgramReq_helper(10, false)
        termDrawProgramReq_helper(12, false)
    end

    if updatePeripheralStorageBridge() then
        termDrawProgramReq_helper(14, true)
    else
        termDrawProgramReq_helper(14, false)
    end

    if updatePeripheralStorage() then
        termDrawProgramReq_helper(16, true)
    else
        termDrawProgramReq_helper(16, false)
    end

    if not needTermDrawRequirements_executed then
        termDrawProgramReq_Header()
        needTermDrawRequirements_executed = true
    end

    if updatePeripheralMonitor() and updatePeripheralColonyIntegrator() and updatePeripheralStorageBridge() and updatePeripheralStorage() then
        if checkMonitorSize() and colony.isInColony() then
            termDrawProgramReq_helper(6, true)
            termDrawProgramReq_helper(8, true)
            termDrawProgramReq_helper(10, true)
            termDrawProgramReq_helper(12, true)
            termDrawProgramReq_helper(14, true)
            termDrawProgramReq_helper(16, true)

            needTermDrawRequirements = false
            needTermDrawRequirements_executed = false

            local text_RequirementsFullfilled = "Requirements fullfilled"
            term.setCursorPos(math.floor((termWidth - #text_RequirementsFullfilled) / 2), 19)
            term.setTextColor(colors.green)
            sleep(0.5)
            textutils.slowWrite(text_RequirementsFullfilled, 16)
            textutils.slowWrite(" . . .", 5)
            sleep(1)

            term.setTextColor(colors.white)
            term.clear()
            term.setCursorPos(1, 1)

            return true
        end
    end

    return true
end

function termShowLog()
    term.setCursorPos(1, 1)
    term.clearLine()
    term.setCursorPos(1, 2)
    term.clearLine()
    term.setCursorPos(1, 3)
    term.clearLine()

    local text_Divider = "-------------------------------------------------------"
    term.setCursorPos(math.floor((termWidth - #text_Divider) / 2) + 1, 4)
    term.write(text_Divider)

    local text_Requirements = "\187 MineColonies Logs \171   v" .. VERSION
    term.setCursorPos(math.floor((termWidth - #text_Requirements) / 2) + 1, 2)
    textutils.slowWrite(text_Requirements, 16)
end

----------------------------------------------------------------------------
--* MINECOLONIES
----------------------------------------------------------------------------

local function isEquipment(desc)
    local equipmentKeywords = { "Sword ", "Bow ", "Pickaxe ", "Axe ", "Shovel ", "Hoe ", "Shears ", "Helmet ",
        "Chestplate ", "Leggings ", "Boots ", "Shield" }

    for _, keyword in ipairs(equipmentKeywords) do
        if string.find(desc, keyword) then
            return true
        end
    end
    return false
end

function colonyCategorizeRequests()
    local equipment_list = {}
    local builder_list = {}
    local others_list = {}

    for _, req in ipairs(colony.getRequests()) do
        -- Skip requests with no item data (Kotawolf fix)
        if not req.items or not req.items[1] then
            logToFile("Skipping request with no items: " .. (req.name or "unknown"), "INFO_")
            goto continue
        end

        local name = req.name
        local target = req.target or ""
        local desc = req.desc or ""
        local count = req.count
        local item_displayName = trimLeadingWhitespace(req.items[1].displayName)
        local item_name = req.items[1].name
        local itemIsEquipment = isEquipment(desc)

        -- Equipment Categorization
        if itemIsEquipment then
            local levelTable = {
                ["and with maximal level: Leather"] = "Leather",
                ["and with maximal level: Stone"] = "Stone",
                ["and with maximal level: Chain"] = "Chain",
                ["and with maximal level: Gold"] = "Gold",
                ["and with maximal level: Iron"] = "Iron",
                ["and with maximal level: Diamond"] = "Diamond",

                ["with maximal level: Wood or Gold"] = "Wood or Gold"
            }

            local level = "Any Level"

            for pattern, mappedLevel in pairs(levelTable) do
                if string.find(desc, pattern) then
                    level = mappedLevel
                    break
                end
            end

            local new_name = level .. " " .. name

            table.insert(equipment_list, {
                name = new_name,
                target = target,
                count = count,
                item_displayName = item_displayName,
                item_name = item_name,
                desc = desc,
                provided = 0,
                isCraftable = false,
                equipment = itemIsEquipment,
                displayColor = colors.white,
                level = level
            })

            -- Builder Categorization
        elseif string.find(target, "Builder") then
            table.insert(builder_list, {
                name = name,
                target = target,
                count = count,
                item_displayName = item_displayName,
                item_name = item_name,
                desc = desc,
                provided = 0,
                isCraftable = false,
                equipment = itemIsEquipment,
                displayColor = colors.white,
                level = ""
            })

            -- Non-Builder Categorization
        else
            table.insert(others_list, {
                name = name,
                target = target,
                count = count,
                item_displayName = item_displayName,
                item_name = item_name,
                desc = desc,
                provided = 0,
                isCraftable = false,
                equipment = itemIsEquipment,
                displayColor = colors.white,
                level = ""
            })
        end

        ::continue::
    end

    return equipment_list, builder_list, others_list
end

----------------------------------------------------------------------------
--* STORAGE SYSTEM REQUEST AND SEND
----------------------------------------------------------------------------

-- Color code: red = not available
--          yellow = stuck
--            blue = crafting
--           green = fully exported

-- Try or skip equipment craft
local b_craftEquipment = true

-- Choose "Iron" or "Diamond" or "Iron and Diamond"
local craftEquipmentOfLevel = "Iron"

function equipmentCraft(name, level, item_name)
    if (item_name == "minecraft:bow") then
        return item_name, true
    end

    if (level == "Iron" or level == "Iron and Diamond" or level == "Any Level") and (craftEquipmentOfLevel == "Iron" or craftEquipmentOfLevel == "Iron and Diamond") then
        if level == "Any Level" then
            level = "Iron"
        end

        item_name = string.lower("minecraft:" .. level .. "_" .. getLastWord(name))

        return item_name, true
    elseif (level == "Diamond" or level == "Iron and Diamond" or level == "Any Level") and craftEquipmentOfLevel == "Diamond" then
        if level == "Any Level" then
            level = "Diamond"
        end

        item_name = string.lower("minecraft:" .. level .. "_" .. getLastWord(name))
        return item_name, true
    end

    return item_name, false
end

local item_quantity_field = nil

local function detectQuantityField(itemName)
    local success, itemData = pcall(function()
        return bridge.getItem({ name = itemName })
    end)

    if success and itemData then
        if type(itemData.amount) == "number" then
            return "amount"
        elseif type(itemData.count) == "number" then
            return "count"
        end
    end

    return nil
end

function storageSystemHandleRequests(request_list)
    -- Add items that should not be crafted or send to the Warehouse
    local skip_items = {
        "minecraft:enchanted_book",
    }
    local skip_set = {}
    for _, name in ipairs(skip_items) do
        skip_set[name] = true
    end

    for _, item in ipairs(request_list) do
        local itemStored = 0
        local b_CurrentlyCrafting = false
        local b_equipmentCraft = true

        if skip_set[item.item_name] then
            item.displayColor = colors.gray
            goto continue
        end

        if item.equipment then
            item.item_name, b_equipmentCraft = equipmentCraft(item.name, item.level, item.item_name)
        end

        -- Detect field once
        if not item_quantity_field then
            item_quantity_field = detectQuantityField(item.item_name)
        end

        --getItem() to see if item in system (if not, error), count and if craftable
        b_functionGetItem = pcall(function()
            local itemData = bridge.getItem({ name = item.item_name })
            itemStored = itemData[item_quantity_field] or 0
            item.isCraftable = itemData.isCraftable
        end)

        if not b_functionGetItem then
            logToFile(item.item_displayName .. " not in system or craftable.", "INFO_", true)

            item.displayColor = colors.red

            if string.sub(item.item_name, 1, 17) == "domum_ornamentum:" then
                item.displayColor = colors.lightBlue
            end

            goto continue
        end

        if not (itemStored == 0) then
            b_functionExportItemToPeripheral = pcall(function()
                item.provided = bridge.exportItemToPeripheral({ name = item.item_name, count = item.count }, storage)
            end) or pcall(function()
                item.provided = bridge.exportItem({ name = item.item_name, count = item.count }, storage)
            end)

            if not b_functionExportItemToPeripheral then
                logToFile("Failed to export item.", "WARN_", true)
                item.displayColor = colors.yellow
            end

            if (item.provided == item.count) then
                item.displayColor = colors.green

                if string.sub(item.item_name, 1, 17) == "domum_ornamentum:" then
                    item.displayColor = colors.lightBlue
                end
            else
                item.displayColor = colors.yellow
            end
        end

        if not b_craftEquipment and item.equipment then
            goto continue
        end

        if (item.provided < item.count) and item.isCraftable and b_equipmentCraft then
            b_functionIsItemCrafting = safeCall(function()
                b_CurrentlyCrafting = bridge.isItemCrafting({ name = item.item_name })
            end)

            if not b_functionIsItemCrafting then
                logToFile("Asking for crafting job failed.", "WARN_")
            end

            if b_CurrentlyCrafting then
                item.displayColor = colors.blue
                goto continue
            end
        end

        local b_craftItem = not b_CurrentlyCrafting and item.isCraftable and (item.provided < item.count)

        if b_craftItem then
            -- Skip Equipments if set to false
            if not b_craftEquipment and item.equipment then
                goto continue
            end

            b_functionCraftItem = safeCall(function()
                local craftedItem = { name = item.item_name, count = item.count - item.provided }

                return bridge.craftItem(craftedItem)
            end)

            if not b_functionCraftItem then
                logToFile("Crafting request failed. (Items missing)", "WARN_", true)
                item.displayColor = colors.yellow
                goto continue
            end

            item.displayColor = colors.blue
        end

        ::continue::
    end
end

----------------------------------------------------------------------------
--* MONITOR DASHBOARD (SCADA card system)
----------------------------------------------------------------------------

local state = {
    equipment = {}, builder = {}, others = {},
    scroll = { equipment = 0, builder = 0, others = 0 },
    msg = "", countdown = refreshInterval, quit = false, needScan = false,
}

local function drawHeader()
    fillRect(1, 1, W, 1, C.cardTitle)
    put(2, 1, "MINECOLONIES DASHBOARD  v" .. VERSION, C.titleText, C.cardTitle)
    local cname = ""
    pcall(function() cname = colony.getColonyName() end)
    local right = string.format("%s  %02ds", tostring(cname), state.countdown)
    put(W - #right - 1, 1, right, C.dim, C.cardTitle)
end

-- Generic scrollable request-list card. rowFn(item, x, y, w) draws one row.
local function drawListCard(key, title, list, x, y, w, h, rowFn)
    local cx, cy, cw, ch = card(x, y, w, h, string.format("%s (%d)", title, #list))

    local off = state.scroll[key] or 0
    local maxOff = math.max(0, #list - ch)
    if off > maxOff then off = maxOff; state.scroll[key] = off end

    if #list > ch then
        put(x + w - 7, y, " \24 ", C.btnText, C.btnOk)
        addButton(x + w - 7, y, x + w - 5, y, function()
            state.scroll[key] = math.max(0, (state.scroll[key] or 0) - 1)
        end)
        put(x + w - 4, y, " \25 ", C.btnText, C.btnOk)
        addButton(x + w - 4, y, x + w - 2, y, function()
            state.scroll[key] = math.min(maxOff, (state.scroll[key] or 0) + 1)
        end)
    end

    if #list == 0 then
        put(cx, cy, "None.", C.dim, C.card)
        return
    end

    for i = 1, ch do
        local item = list[i + off]
        if not item then break end
        rowFn(item, cx, cy + i - 1, cw)
    end
end

-- Row renderers keep the original information per category.
local function rowBuilder(item, x, y, w)
    put(x, y, item.provided .. "/" .. item.name, item.displayColor, C.card)
end

local function rowEquipment(item, x, y, w)
    local target = tostring(item.target or "")
    local room = w - #target - 1
    put(x, y, tostring(item.name):sub(1, math.max(0, room)), item.displayColor, C.card)
    put(x + w - #target, y, target, C.dim, C.card)
end

local function rowOthers(item, x, y, w)
    local target = tostring(item.target or "")
    local left = item.provided .. "/" .. item.name
    local room = w - #target - 1
    put(x, y, left:sub(1, math.max(0, room)), item.displayColor, C.card)
    put(x + w - #target, y, target, C.dim, C.card)
end

local function drawLegend(x, y, w, h)
    local cx, cy = card(x, y, w, h, "LEGEND")
    local entries = {
        { colors.red,       "missing / not craftable" },
        { colors.yellow,    "stuck / partial" },
        { colors.blue,      "crafting" },
        { colors.green,     "fully exported" },
        { colors.lightBlue, "domum ornamentum" },
        { colors.gray,      "skipped" },
    }
    for i, e in ipairs(entries) do
        if cy + i - 1 > y + h - 2 then break end
        put(cx, cy + i - 1, "\7 ", e[1], C.card)
        put(cx + 2, cy + i - 1, e[2], C.dim, C.card)
    end
end

local function drawFooter()
    fillRect(1, H, W, 1, C.cardTitle)
    local x = 2
    x = button(x, H, "REFRESH", C.btnOk, C.btnText, function() state.needScan = true end) + 1
    x = button(x, H, "QUIT", C.btnBad, colors.black, function() state.quit = true end) + 2
    if state.msg ~= "" then put(x, H, state.msg, C.dim, C.cardTitle) end
end

-- Relevance-sized layout: builder requests (largest churn) get the big right
-- column; equipment + others stack left with the legend pinned at the bottom.
local function layoutDashboard()
    local topY, botY = 2, H - 1
    local ch = botY - topY + 1

    if W >= 54 then
        local leftW  = math.max(24, math.floor(W * 0.42))
        local rightX = leftW + 2
        local rightW = W - leftW - 1

        local legendH = 8
        local rest = ch - legendH - 2
        local eqH = math.max(5, math.floor(rest * 0.45))
        local otH = rest - eqH - 1

        local y = topY
        drawListCard("equipment", "EQUIPMENT", state.equipment, 1, y, leftW, eqH, rowEquipment)
        y = y + eqH + 1
        drawListCard("others", "OTHER REQUESTS", state.others, 1, y, leftW, otH, rowOthers)
        y = y + otH + 1
        drawLegend(1, y, leftW, botY - y + 1)

        drawListCard("builder", "BUILDER REQUESTS", state.builder, rightX, topY, rightW, ch, rowBuilder)
    else
        local third = math.floor((ch - 2) / 3)
        local y = topY
        drawListCard("builder", "BUILDER REQUESTS", state.builder, 1, y, W, third, rowBuilder)
        y = y + third + 1
        drawListCard("equipment", "EQUIPMENT", state.equipment, 1, y, W, third, rowEquipment)
        y = y + third + 1
        drawListCard("others", "OTHER REQUESTS", state.others, 1, y, W, botY - y + 1, rowOthers)
    end
end

local function redraw()
    W, H = monitor.getSize()
    monitor.setBackgroundColor(C.screen)
    monitor.clear()
    clearButtons()
    drawHeader()
    layoutDashboard()
    drawFooter()
end

----------------------------------------------------------------------------
--* MAIN LOGIC FUNCTIONS
----------------------------------------------------------------------------

function updatePeripheralAll()
    if not updatePeripheralMonitor() or not checkMonitorSize() then
        needTermDrawRequirements = true
    end

    if not updatePeripheralColonyIntegrator() or not colony.isInColony() then
        needTermDrawRequirements = true
    end

    if not updatePeripheralStorageBridge() then
        needTermDrawRequirements = true
    end

    if not updatePeripheralStorage() then
        needTermDrawRequirements = true
    end

    while needTermDrawRequirements do
        termDrawCheckRequirements()
        sleep(1)
    end
end

function requestAndFulfill()
    local equipment_list, builder_list, others_list

    while true do
        local success, err = pcall(function()
            equipment_list, builder_list, others_list = colonyCategorizeRequests()
        end)

        if success then
            break
        else
            logToFile("Failed to get requests, retrying... (" .. err .. ")", "WARN_", true)
            sleep(5)
        end
    end

    -- writeToLogFile("log1.txt", equipment_list, builder_list, others_list)

    storageSystemHandleRequests(equipment_list)

    storageSystemHandleRequests(builder_list)

    storageSystemHandleRequests(others_list)

    -- writeToLogFile("log2.txt", equipment_list, builder_list, others_list)

    return equipment_list, builder_list, others_list
end

local function rescan()
    updatePeripheralAll()
    applyPalette()

    termShowLog()
    term.setCursorPos(1, 5)

    -- debugTableTest()
    -- debugDiskSpace()

    state.equipment, state.builder, state.others = requestAndFulfill()
    state.msg = string.format("B:%d  E:%d  O:%d", #state.builder, #state.equipment, #state.others)
    state.countdown = refreshInterval
    state.needScan = false
end

----------------------------------------------------------------------------
--* MAIN
----------------------------------------------------------------------------

function main()
    termLoadingAnimation()

    updatePeripheralAll()

    monitorLoadingAnimation()

    applyPalette()

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
            if state.countdown <= 0 then rescan() end
            redraw()
            tick = os.startTimer(1)
        elseif e == "char" and ev[2] == "q" then
            break
        elseif e == "monitor_resize" or e == "term_resize" then
            redraw()
        end
    end

    restorePalette()
    resetDefault(monitor)
    resetDefault(term)
    print("CCxM stopped.")
end

main()

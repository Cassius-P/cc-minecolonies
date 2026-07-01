--[[ colony_dump.lua -- dump colony_integrator structure to paste.rs, print link ]]

local colony = peripheral.find("colony_integrator")
if not colony then error("No colony_integrator found", 0) end

local out = {}
local function add(s) out[#out+1] = s end

add("== colony_integrator methods ==")
add(textutils.serialize(peripheral.getMethods(peripheral.getName(colony))))

add("\n== isInColony ==")
add(tostring(colony.isInColony()))

local function try(name, fn)
  add("\n== " .. name .. " ==")
  local ok, res = pcall(fn)
  if ok then add(textutils.serialize(res)) else add("ERROR: " .. tostring(res)) end
end

try("getColonyName", function() return colony.getColonyName() end)
try("getColonyID",   function() return colony.getColonyID() end)

-- Citizens: dump first 3 full so field shapes are visible.
local citizens = colony.getCitizens() or {}
add("\n== getCitizens count ==")
add(tostring(#citizens))
for i = 1, math.min(3, #citizens) do
  add("\n== citizen[" .. i .. "] ==")
  add(textutils.serialize(citizens[i]))
end

-- Buildings: dump first 3 full + list of all types.
local buildings = colony.getBuildings() or {}
add("\n== getBuildings count ==")
add(tostring(#buildings))
for i = 1, math.min(3, #buildings) do
  add("\n== building[" .. i .. "] ==")
  add(textutils.serialize(buildings[i]))
end
add("\n== all building types ==")
local types = {}
for _, b in ipairs(buildings) do types[#types+1] = tostring(b.type or b.name) end
add(textutils.serialize(types))

local body = table.concat(out, "\n")

-- Upload to paste.rs (POST body = raw text, returns URL as plain text).
local resp, err = http.post("https://paste.rs", body)
if not resp then
  print("Upload failed: " .. tostring(err))
  return
end
local link = resp.readAll()
resp.close()
print(link)

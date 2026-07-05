----------------------------------------------------------------------------
-- app/dump_service.lua -- build a selected-colony-data JSON payload and upload
-- it to paste.rs, returning the link. This is the diagnostics "dump" logic that
-- used to live inline in ui/app.lua; it belongs in the app layer, not the UI.
--
--   run(colony, sel) -> link   (colony = raw integrator; sel = which sections)
----------------------------------------------------------------------------

local paste = require("common.ports.paste")

local M = {}

local function g(fn, d) local ok, v = pcall(fn); if ok and v ~= nil then return v else return d end end

-- Deep-clone to break shared table references (serializeJSON errors on
-- "repeated entries" when the same table is referenced more than once).
local function clone(t)
  if type(t) ~= "table" then return t end
  local c = {}
  for k, v in pairs(t) do c[k] = clone(v) end
  return c
end

function M.run(colony, sel)
  sel = sel or {}
  local payload = { at = os.epoch and os.epoch("utc") or 0 }
  if sel.colony then
    payload.colony = { name = g(colony.getColonyName), id = g(colony.getColonyID),
      happiness = g(colony.getHappiness), pop = g(colony.amountOfCitizens),
      maxPop = g(colony.maxOfCitizens), attack = g(colony.isUnderAttack),
      raid = g(colony.isUnderRaid), sites = g(colony.amountOfConstructionSites),
      graves = g(colony.amountOfGraves) }
  end
  if sel.citizens   then payload.citizens   = g(function() return colony.getCitizens() end, {}) end
  if sel.buildings  then payload.buildings  = g(function() return colony.getBuildings() end, {}) end
  if sel.workOrders then payload.workOrders = g(function() return colony.getWorkOrders() end, {}) end
  if sel.requests   then payload.requests   = g(function() return colony.getRequests() end, {}) end
  if sel.visitors   then payload.visitors   = g(function() return colony.getVisitors() end, {}) end

  local okj, body = pcall(textutils.serializeJSON, clone(payload))
  if not okj then body = textutils.serialize(payload) end
  return paste.post(body)
end

return M

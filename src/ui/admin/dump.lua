----------------------------------------------------------------------------
-- ui/admin/dump.lua -- admin view "Dump" tab: select resources, dump to
-- paste.rs as JSON. Registers triggerDump / toggleAllDump on the shared `api`
-- so the global d / a keys can drive it.
----------------------------------------------------------------------------

local diff = require("ui.admin.diff")

local M = { title = "Dump" }

local RESOURCES = {
  { "colony", "Colony info" }, { "citizens", "Citizens" }, { "buildings", "Buildings" },
  { "workOrders", "Work orders" }, { "requests", "Requests" }, { "visitors", "Visitors" },
}

function M.build(tab, ctx, api)
  local tw = select(1, term.getSize())
  tab:addLabel({ x = 2, y = 1, width = tw - 2, foreground = colors.cyan })
    :setText("Dump colony data -> paste.rs (JSON)")

  -- CheckBox renders `checkedText` when checked and `text` when not, so put the
  -- FULL label in both (with a [x]/[ ] marker) and set a visible foreground --
  -- otherwise a checked box shows only a bare "x".
  local cbs = {}
  for i, r in ipairs(RESOURCES) do
    local cb = tab:addCheckBox({ x = 2, y = 2 + i, checked = true, autoSize = true,
      text = "[ ] " .. r[2], checkedText = "[x] " .. r[2], foreground = colors.white })
    cbs[#cbs + 1] = { key = r[1], cb = cb }
  end

  local function selection()
    local sel = {}
    for _, e in ipairs(cbs) do sel[e.key] = e.cb.get("checked") and true or false end
    return sel
  end
  local allOn = true

  local by = 2 + #RESOURCES + 2
  tab:addButton({ x = 2, y = by, width = 16, height = 1 })
    :setText("Create dump"):setBackground(colors.blue):setForeground(colors.white)
    :onClick(function() if ctx.onDump then ctx.onDump(selection()) end end)
  tab:addLabel({ x = 20, y = by, width = tw - 20, foreground = colors.gray })
    :setText("d dump   a all/none")
  local lDump = tab:addLabel({ x = 2, y = by + 2, width = tw - 2 })

  -- Expose to global keys.
  api.triggerDump = function() if ctx.onDump then ctx.onDump(selection()) end end
  api.toggleAllDump = function()
    allOn = not allOn
    for _, e in ipairs(cbs) do e.cb.set("checked", allOn) end
  end

  local set = diff.new()
  return function(state)
    if state.dumping then
      set(lDump, "Dumping...", colors.yellow)
    elseif state.dumpError then
      set(lDump, "Failed: " .. tostring(state.dumpError):sub(1, 40), colors.red)
    elseif state.dumpLink then
      set(lDump, state.dumpLink .. "  (saved /dump_link.txt)", colors.lime)
    else
      set(lDump, "", colors.white)
    end
  end
end

return M

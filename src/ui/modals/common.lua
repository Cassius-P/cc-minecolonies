----------------------------------------------------------------------------
-- ui/modals/common.lua -- shared native-modal plumbing.
--
-- The full-screen modal Frame (screen.nmodalFrame) is created once in
-- layout/screen build; these helpers tear its card subtree down and hide it.
-- Both the apply and sections modals build their card into that frame.
----------------------------------------------------------------------------

local M = {}

-- Remove EVERY child of the modal frame (Basalt has removeChild, not
-- removeChildren). Clearing all of them -- not just the tracked card -- means a
-- reopened modal can never render stale widgets from a previous suggestion.
function M.clearCard(screen)
  local nmf = screen.nmodalFrame
  local kids = nmf and nmf.get("children")
  if type(kids) == "table" then
    local copy = {}
    for i = 1, #kids do copy[i] = kids[i] end
    for i = 1, #copy do nmf:removeChild(copy[i]) end
  end
  screen.nmodalCard = nil
end

-- Hide + tear down whichever native modal is open. `enabled=false` matters: a
-- full-screen frame can still intercept monitor_touch while merely invisible,
-- which would swallow/misroute taps meant for the sections beneath.
function M.hide(screen)
  local nmf = screen.nmodalFrame
  if nmf then
    M.clearCard(screen)
    nmf.set("visible", false)
    nmf.set("enabled", false)
  end
  screen.nmodalSug = nil
  screen.nmodalNode = nil
  screen.nmodalKind = nil
  screen.nmodalEntity = nil
  screen.nmodalEntityLabel = nil
end

return M

-- Windows-style hover-scroll without stealing keyboard focus (follow_mouse = 2).
-- Re-applied after Omarchy's floating workspace-modes hook, which resets
-- follow_mouse to 0 on floating workspace switches.

local M = {}

local enabled = false
local hooks_registered = false

local function enforce_follow_mouse()
  if not enabled then
    return
  end
  if hl.get_config("input.follow_mouse") ~= 2 then
    hl.config({ input = { follow_mouse = 2 } })
  end
end

function M.setup(is_enabled)
  enabled = is_enabled ~= false
  if enabled then
    hl.config({
      input = {
        follow_mouse = 2,
      },
    })
    hl.timer(enforce_follow_mouse, { type = "oneshot", timeout = 50 })
  end

  if not hooks_registered then
    hooks_registered = true
    hl.on("workspace.active", function()
      if enabled then
        hl.timer(enforce_follow_mouse, { type = "oneshot", timeout = 1 })
      end
    end)
    hl.on("monitor.focused", function()
      if enabled then
        hl.timer(enforce_follow_mouse, { type = "oneshot", timeout = 1 })
      end
    end)
  end
end

return M

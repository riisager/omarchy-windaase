-- Windows-style hover-scroll without stealing keyboard focus (follow_mouse = 2).
-- Re-applied after Omarchy's floating workspace-modes hook, which resets
-- follow_mouse to 0 on floating workspace switches.

local M = {}

local function enforce_follow_mouse()
  if hl.get_config("input.follow_mouse") ~= 2 then
    hl.config({ input = { follow_mouse = 2 } })
  end
end

function M.setup()
  hl.config({
    input = {
      follow_mouse = 2,
    },
  })

  hl.timer(enforce_follow_mouse, { type = "oneshot", timeout = 50 })
  hl.on("workspace.active", function()
    hl.timer(enforce_follow_mouse, { type = "oneshot", timeout = 1 })
  end)
  hl.on("monitor.focused", function()
    hl.timer(enforce_follow_mouse, { type = "oneshot", timeout = 1 })
  end)
end

return M

-- Unit tests for hypr.windaase.geometry (runnable standalone with `lua tests/geometry_test.lua`).

local script_dir = debug.getinfo(1, "S").source:match("@(.*/)") or "./"
local repo_root = script_dir .. "../"
package.path = repo_root .. "?.lua;" .. package.path

local geometry = require("hypr.windaase.geometry")

-- 1. JSON decoder & layouts.json loading
local cfg = geometry.load_layouts_config({ repo_root .. "layouts.json" })
assert(cfg.cardW == 84 and cfg.cardH == 52, "unexpected card dimensions")
assert(cfg.cardGap == 10 and cfg.padX == 14 and cfg.padY == 12 and cfg.topMargin == 10, "unexpected layout spacing")
assert(#cfg.layouts == 6, "expected 6 snap layouts, got " .. tostring(#cfg.layouts))
assert(#cfg.layouts[5] == 4, "expected 4 zones in 2x2 layout")
assert(cfg.layouts[6][1].max == true, "expected 6th layout to be maximize")

local decoded, err = geometry.decode_json('{"hello":"world\\n1","arr":[true,false,null,-12.5]}')
assert(decoded and decoded.hello == "world\n1", "json string escape decode failed: " .. tostring(err))
assert(decoded.arr[1] == true and decoded.arr[2] == false and decoded.arr[3] == nil and decoded.arr[4] == -12.5, "json array decode failed")

local bad, bad_err = geometry.decode_json("{broken")
assert(bad == nil and bad_err ~= nil, "expected error on invalid json")

-- 2. monitor_logical_size (scale & transform)
local lw, lh = geometry.monitor_logical_size({ width = 1920, height = 1200, scale = 1, transform = 0 })
assert(lw == 1920 and lh == 1200, "scale 1 logical size failed")

local sw, sh = geometry.monitor_logical_size({ width = 2880, height = 1800, scale = 1.5, transform = 0 })
assert(sw == 1920 and sh == 1200, "scale 1.5 logical size failed")

local rw, rh = geometry.monitor_logical_size({ width = 1920, height = 1080, scale = 1, transform = 1 })
assert(rw == 1080 and rh == 1920, "rotated transform size failed")

-- 3. get_work_area (no obsolete dock_pad; respects reserved bar)
local area = geometry.get_work_area({
  width = 1920,
  height = 1200,
  x = 0,
  y = 0,
  scale = 1,
  transform = 0,
  reserved = { left = 0, top = 0, right = 0, bottom = 26 },
}, 8, 8)
assert(area.x == 8 and area.y == 8, "work area x/y mismatch")
assert(area.w == 1904 and area.h == 1158, "work area w/h mismatch")
assert(area.max_x == 0 and area.max_y == 0 and area.max_w == 1920 and area.max_h == 1174, "max bounds mismatch")

-- 4. zone_rect_in_area (50/50, 65/35, 33/33/33, 2x2)
local left_half = geometry.zone_rect_in_area(area, cfg.layouts[1][1])
local right_half = geometry.zone_rect_in_area(area, cfg.layouts[1][2])
assert(left_half.x == 8 and right_half.x == left_half.x + left_half.w + 8, "50/50 gap mismatch")
assert(left_half.w + right_half.w + 8 == area.w, "50/50 width sum mismatch")

local tl = geometry.zone_rect_in_area(area, cfg.layouts[5][1])
local bl = geometry.zone_rect_in_area(area, cfg.layouts[5][3])
assert(tl.y + tl.h + 8 == bl.y, "2x2 vertical gap mismatch")
assert(bl.y + bl.h == area.y + area.h, "2x2 bottom alignment mismatch")

-- 5. hit_test_snap_layouts
-- Total width = 6*84 + 5*10 = 554; pill_w = 554 + 28 + 2 = 584; on 1920px pill_x = 668; start_x = 683, start_y = 23
local ci, zi, z, px, py, pw, ph = geometry.hit_test_snap_layouts(695, 40, 1920, cfg)
assert(px == 668 and py == 10 and pw == 584 and ph == 78, "pill geometry mismatch")
assert(ci == 0 and zi == 0 and z.rw == 0.5, "hit test first zone mismatch")

local ci2, zi2, z2 = geometry.hit_test_snap_layouts(683 + 5 * (84 + 10) + 40, 40, 1920, cfg)
assert(ci2 == 5 and zi2 == 0 and z2.max == true, "hit test maximize card mismatch")

local miss_c, miss_z, miss = geometry.hit_test_snap_layouts(10, 10, 1920, cfg)
assert(miss_c == -1 and miss_z == -1 and miss == nil, "hit test outside pill should miss")

-- 6. resolve_layouts_config (ultrawide 25/50/25 toggle) & complementary_zone
local std_cfg = geometry.resolve_layouts_config(cfg, false)
assert(#std_cfg.layouts == 6, "expected 6 layouts when ultrawide disabled")

local uw_cfg = geometry.resolve_layouts_config(cfg, true)
assert(#uw_cfg.layouts == 7, "expected 7 layouts when ultrawide enabled")
assert(#uw_cfg.layouts[7] == 3 and uw_cfg.layouts[7][2].rw == 0.5, "expected 25/50/25 7th card")
local uw_ci, uw_zi, uw_z = geometry.hit_test_snap_layouts(636 + 6 * (84 + 10) + 42, 40, 1920, uw_cfg)
assert(uw_ci == 6 and uw_zi == 1 and uw_z.rw == 0.5, "hit test ultrawide center zone mismatch")

local comp_r = geometry.complementary_zone(cfg.layouts[1][1])
assert(comp_r and comp_r.rx == 0.5 and comp_r.rw == 0.5, "50/50 left complementary failed")
local comp_l = geometry.complementary_zone(cfg.layouts[2][2])
assert(comp_l and comp_l.rx == 0 and comp_l.rw == 0.65, "65/35 right complementary failed")
assert(geometry.complementary_zone(cfg.layouts[5][1]) == nil, "quarter zone should not trigger Snap Assist")
assert(geometry.complementary_zone(cfg.layouts[6][1]) == nil, "maximize zone should not trigger Snap Assist")

print("ALL GEOMETRY LUA TESTS PASSED")

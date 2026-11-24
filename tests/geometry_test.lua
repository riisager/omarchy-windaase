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

-- 7. Snap Resize: window_outer_rect & detect_resize_edge
local win_outer = geometry.window_outer_rect({ at = { x = 10, y = 40 }, size = { x = 944, y = 1110 } }, 2, 30)
assert(win_outer.x == 8 and win_outer.y == 8 and win_outer.w == 948 and win_outer.h == 1144, "window_outer_rect mismatch")
local no_tb_outer = geometry.window_outer_rect({ at = { x = 10, y = 10 }, size = { x = 500, y = 400 } }, 2, 0)
assert(no_tb_outer.y == 8 and no_tb_outer.h == 404, "window_outer_rect without titlebar mismatch")

local e1, a1 = geometry.detect_resize_edge({ x = 8, y = 8, w = 948, h = 1158 }, { x = 8, y = 8, w = 990, h = 1158 })
assert(e1 == "right" and a1 == "x", "expected right edge resize")
local e2, a2 = geometry.detect_resize_edge({ x = 964, y = 8, w = 948, h = 1158 }, { x = 920, y = 8, w = 992, h = 1158 })
assert(e2 == "left" and a2 == "x", "expected left edge resize")
local e3, a3 = geometry.detect_resize_edge({ x = 8, y = 8, w = 948, h = 575 }, { x = 8, y = 8, w = 948, h = 620 })
assert(e3 == "bottom" and a3 == "y", "expected bottom edge resize")
local e4, a4 = geometry.detect_resize_edge({ x = 8, y = 591, w = 948, h = 575 }, { x = 8, y = 540, w = 948, h = 626 })
assert(e4 == "top" and a4 == "y", "expected top edge resize")
local em, am = geometry.detect_resize_edge({ x = 8, y = 8, w = 500, h = 400 }, { x = 40, y = 24, w = 500, h = 400 })
assert(em == nil and am == nil, "window move must not trigger resize edge")
local ed, ad = geometry.detect_resize_edge({ x = 8, y = 8, w = 500, h = 400 }, { x = 8, y = 8, w = 550, h = 440 })
assert(ed == nil and ad == nil, "diagonal corner resize must not trigger single-edge seam")

-- 8. find_seam_group (50/50, 50|25/25, 2x2, 3-col isolation, occluded skip, non-seam miss)
local half_pair = {
  { addr = "0x1", outer = { x = 8, y = 8, w = 948, h = 1158 }, focus_history_id = 0, border = 2, titlebar = 30 },
  { addr = "0x2", outer = { x = 964, y = 8, w = 948, h = 1158 }, focus_history_id = 1, border = 2, titlebar = 30 },
}
local g_r = geometry.find_seam_group(half_pair, "0x1", "right", 8, area)
assert(g_r and #g_r.before_list == 1 and #g_r.after_list == 1 and g_r.seam == 956, "50/50 right seam failed")
local g_l = geometry.find_seam_group(half_pair, "0x2", "left", 8, area)
assert(g_l and #g_l.before_list == 1 and #g_l.after_list == 1 and g_l.seam == 956, "50/50 left seam failed")
assert(geometry.find_seam_group(half_pair, "0x1", "left", 8, area) == nil, "outer left border should not match seam")

local three_pane = {
  { addr = "0x1", outer = { x = 8, y = 8, w = 948, h = 1158 }, focus_history_id = 0, border = 2, titlebar = 30 },
  { addr = "0x2", outer = { x = 964, y = 8, w = 948, h = 575 }, focus_history_id = 1, border = 2, titlebar = 30 },
  { addr = "0x3", outer = { x = 964, y = 591, w = 948, h = 575 }, focus_history_id = 2, border = 2, titlebar = 30 },
}
local g_3a = geometry.find_seam_group(three_pane, "0x1", "right", 8, area)
assert(g_3a and #g_3a.before_list == 1 and #g_3a.after_list == 2, "50|25/25 from left failed")
local g_3b = geometry.find_seam_group(three_pane, "0x2", "left", 8, area)
assert(g_3b and #g_3b.before_list == 1 and #g_3b.after_list == 2, "50|25/25 convergence from top-right failed")
local g_3v = geometry.find_seam_group(three_pane, "0x2", "bottom", 8, area)
assert(g_3v and #g_3v.before_list == 1 and g_3v.before_list[1].addr == "0x2" and #g_3v.after_list == 1 and g_3v.after_list[1].addr == "0x3", "50|25/25 vertical seam must not include left half")

local quad = {
  { addr = "0xtl", outer = { x = 8, y = 8, w = 948, h = 575 }, focus_history_id = 0, border = 2, titlebar = 30 },
  { addr = "0xtr", outer = { x = 964, y = 8, w = 948, h = 575 }, focus_history_id = 1, border = 2, titlebar = 30 },
  { addr = "0xbl", outer = { x = 8, y = 591, w = 948, h = 575 }, focus_history_id = 2, border = 2, titlebar = 30 },
  { addr = "0xbr", outer = { x = 964, y = 591, w = 948, h = 575 }, focus_history_id = 3, border = 2, titlebar = 30 },
}
local g_qh = geometry.find_seam_group(quad, "0xtl", "right", 8, area)
assert(g_qh and #g_qh.before_list == 2 and #g_qh.after_list == 2, "2x2 horizontal seam should pair bottom row")
local g_qv = geometry.find_seam_group(quad, "0xtl", "bottom", 8, area)
assert(g_qv and #g_qv.before_list == 2 and #g_qv.after_list == 2, "2x2 vertical seam should pair right col")

local three_col = {
  { addr = "0xc1", outer = { x = 8, y = 8, w = 629, h = 1158 }, focus_history_id = 0, border = 2, titlebar = 30 },
  { addr = "0xc2", outer = { x = 645, y = 8, w = 630, h = 1158 }, focus_history_id = 1, border = 2, titlebar = 30 },
  { addr = "0xc3", outer = { x = 1283, y = 8, w = 629, h = 1158 }, focus_history_id = 2, border = 2, titlebar = 30 },
}
local g_3c = geometry.find_seam_group(three_col, "0xc1", "right", 8, area)
assert(g_3c and #g_3c.before_list == 1 and #g_3c.after_list == 1 and g_3c.after_list[1].addr == "0xc2", "3-column drag should isolate adjacent seam")

local occluded = {
  { addr = "0x1", outer = { x = 8, y = 8, w = 948, h = 1158 }, focus_history_id = 0, border = 2, titlebar = 30 },
  { addr = "0x2", outer = { x = 964, y = 8, w = 948, h = 1158 }, focus_history_id = 1, border = 2, titlebar = 30 },
  { addr = "0xburied", outer = { x = 964, y = 8, w = 948, h = 1158 }, focus_history_id = 9, border = 2, titlebar = 30 },
}
local g_occ = geometry.find_seam_group(occluded, "0x1", "right", 8, area)
assert(g_occ and #g_occ.after_list == 1 and g_occ.after_list[1].addr == "0x2", "occluded background window must be skipped")

-- 9. compute_seam_rects & next_snap_split_seam & compute_solo_snap_resize
local rects_50 = geometry.compute_seam_rects(g_r, 956)
assert(rects_50.pct1 == 50 and rects_50.pct2 == 50 and rects_50.divider_rect.x == 956 and rects_50.divider_rect.w == 8, "50/50 compute_seam_rects mismatch")
assert(rects_50.placements[1].rect.w == 948 and rects_50.placements[2].rect.x == 964 and rects_50.placements[2].rect.w == 948, "50/50 gap separation mismatch")

local s65 = geometry.next_snap_split_seam(g_r, 1)
assert(s65 == 1243, "50 -> 65 preset mismatch: " .. tostring(s65))
local rects_65 = geometry.compute_seam_rects(g_r, s65)
assert(rects_65.pct1 == 65 and rects_65.pct2 == 35, "65/35 percentage mismatch")
assert(rects_65.placements[1].rect.w + rects_65.placements[2].rect.w + 8 == area.w, "65/35 width conservation mismatch")

local g_65 = geometry.find_seam_group({
  { addr = "0x1", outer = rects_65.placements[1].rect, focus_history_id = 0 },
  { addr = "0x2", outer = rects_65.placements[2].rect, focus_history_id = 1 },
}, "0x1", "right", 8, area)
local s75 = geometry.next_snap_split_seam(g_65, 1)
assert(s75 and geometry.compute_seam_rects(g_65, s75).pct1 == 75, "65 -> 75 step failed")
local g_75 = { span_start = g_65.span_start, span_end = g_65.span_end, gap = 8, min_seam = g_65.min_seam, max_seam = g_65.max_seam, seam = s75 }
assert(geometry.next_snap_split_seam(g_75, 1) == nil, "75 right should stop cleanly")
local back_to_50 = geometry.next_snap_split_seam(g_65, -1)
assert(back_to_50 == 956, "65 -> 50 step back failed")

local g_mouse_mid = { span_start = g_r.span_start, span_end = g_r.span_end, gap = 8, min_seam = g_r.min_seam, max_seam = g_r.max_seam, seam = 1090 }
assert(geometry.next_snap_split_seam(g_mouse_mid, 1) == 1243, "intermediate ratio should step up to 65%")
assert(geometry.next_snap_split_seam(g_mouse_mid, -1) == 956, "intermediate ratio should step down to 50%")

local clamped = geometry.compute_seam_rects(g_r, 5000)
assert(clamped.seam == g_r.max_seam and clamped.placements[2].rect.w == 240, "max_seam min_pane clamp failed")

local solo_l = geometry.compute_solo_snap_resize({ x = 8, y = 8, w = 948, h = 1158 }, area, 1, "x")
assert(solo_l and solo_l.pct1 == 65 and solo_l.rect.x == 8 and solo_l.rect.w == 1235, "solo left window resize right failed")
local solo_r = geometry.compute_solo_snap_resize({ x = 964, y = 8, w = 948, h = 1158 }, area, -1, "x")
assert(solo_r and solo_r.pct1 == 35 and solo_r.rect.x == 677 and solo_r.rect.x + solo_r.rect.w == 1912, "solo right window widen left failed")
local solo_v = geometry.compute_solo_snap_resize({ x = 8, y = 8, w = 1904, h = 575 }, area, 1, "y")
assert(solo_v and solo_v.pct1 == 65 and solo_v.rect.y == 8, "solo top window resize down failed")
assert(geometry.compute_solo_snap_resize({ x = 200, y = 200, w = 900, h = 600 }, area, 1, "x") == nil, "free-floating window should not solo-snap resize")

-- 10. resolve_keyboard_snap_resize (seam, 3-col non-fallthrough, cross-edge fallback, solo, nil)
local kb_50 = geometry.resolve_keyboard_snap_resize(half_pair, "0x1", area, 8, 1, "x")
assert(kb_50 and kb_50.kind == "seam" and kb_50.pct1 == 65 and #kb_50.placements == 2, "kb 50/50 -> 65/35 failed")

local three_col_l75 = {
  { addr = "0xc1", outer = { x = 8, y = 8, w = 948, h = 1158 }, focus_history_id = 0, border = 2, titlebar = 30 },
  { addr = "0xc2", outer = { x = 964, y = 8, w = 311, h = 1158 }, focus_history_id = 1, border = 2, titlebar = 30 },
  { addr = "0xc3", outer = { x = 1283, y = 8, w = 629, h = 1158 }, focus_history_id = 2, border = 2, titlebar = 30 },
}
assert(
  geometry.resolve_keyboard_snap_resize(three_col_l75, "0xc1", area, 8, 1, "x") == nil,
  "3-column seam at 75% extreme must stop cleanly instead of solo-resizing over neighbor"
)

local three_col_r75 = {
  { addr = "0xc1", outer = { x = 8, y = 8, w = 629, h = 1158 }, focus_history_id = 0, border = 2, titlebar = 30 },
  { addr = "0xc2", outer = { x = 645, y = 8, w = 948, h = 1158 }, focus_history_id = 1, border = 2, titlebar = 30 },
  { addr = "0xc3", outer = { x = 1601, y = 8, w = 311, h = 1158 }, focus_history_id = 2, border = 2, titlebar = 30 },
}
local kb_mid = geometry.resolve_keyboard_snap_resize(three_col_r75, "0xc2", area, 8, 1, "x")
assert(kb_mid and kb_mid.kind == "seam" and #kb_mid.placements == 2, "3-col middle pane fallback to left seam failed")
local mid_addrs = {}
for _, p in ipairs(kb_mid.placements) do
  mid_addrs[p.addr] = true
end
assert(mid_addrs["0xc1"] and mid_addrs["0xc2"] and not mid_addrs["0xc3"], "3-col fallback must leave 0xc3 untouched")

local solo_kb = geometry.resolve_keyboard_snap_resize(
  { { addr = "0x1", outer = { x = 8, y = 8, w = 948, h = 1158 }, focus_history_id = 0, border = 2, titlebar = 30 } },
  "0x1",
  area,
  8,
  1,
  "x"
)
assert(solo_kb and solo_kb.kind == "solo" and solo_kb.pct1 == 65 and #solo_kb.placements == 1, "kb solo snap resize failed")

local free_kb = geometry.resolve_keyboard_snap_resize(
  { { addr = "0x1", outer = { x = 200, y = 200, w = 900, h = 600 }, focus_history_id = 0, border = 2, titlebar = 30 } },
  "0x1",
  area,
  8,
  1,
  "x"
)
assert(free_kb == nil, "kb free-floating window must return nil")

-- 11. named_zone_spec, pick_adjacent_monitor, and map_rect_between_areas
local left_spec = geometry.named_zone_spec("left")
assert(left_spec and left_spec.rx == 0 and left_spec.rw == 0.5 and left_spec.rh == 1.0 and not left_spec.max, "left zone spec mismatch")
local max_spec = geometry.named_zone_spec("maximize")
assert(max_spec and max_spec.max == true, "maximize zone spec mismatch")
assert(geometry.named_zone_spec("unknown") == nil and geometry.named_zone_spec(nil) == nil, "unknown zone spec should return nil")

local mons = {
  { name = "DP-2", x = 1920, y = 0, width = 2560, height = 1440, scale = 1 },
  { name = "eDP-1", x = 0, y = 120, width = 1920, height = 1200, scale = 1 },
  { name = "HDMI-1", x = 4480, y = 0, width = 1920, height = 1080, scale = 1, disabled = true },
  { name = "DP-4", x = 4480, y = 0, width = 1920, height = 1080, scale = 1, is_mirror = true },
  { name = "DP-3", x = -1920, y = 0, width = 1920, height = 1080, scale = 1 },
}
assert(geometry.pick_adjacent_monitor({ mons[1] }, "DP-2", "r") == nil, "single monitor must return nil")
assert(geometry.pick_adjacent_monitor(mons, "eDP-1", "r").name == "DP-2", "right neighbor from eDP-1 should be DP-2")
assert(geometry.pick_adjacent_monitor(mons, "eDP-1", "l").name == "DP-3", "left neighbor from eDP-1 should be DP-3")
assert(geometry.pick_adjacent_monitor(mons, "DP-3", "l").name == "DP-2", "left wrap from DP-3 should skip disabled/mirror and land on DP-2")
assert(geometry.pick_adjacent_monitor(mons, "DP-2", "r").name == "DP-3", "right wrap from DP-2 should skip disabled/mirror and land on DP-3")

local src_area = geometry.get_work_area({ x = 0, y = 0, width = 1920, height = 1200, reserved = { 0, 26, 0, 0 } }, 8, 8)
local dst_area = geometry.get_work_area({ x = 1920, y = 0, width = 2560, height = 1440, reserved = { 0, 0, 0, 40 } }, 8, 8)

-- Named zone across different resolutions & reserved bar margins
local moved_left = geometry.map_rect_between_areas({ x = 8, y = 34, w = 948, h = 1158 }, src_area, dst_area, "left", nil)
assert(moved_left and moved_left.mode == "zone" and moved_left.x == 1928 and moved_left.y == 8 and moved_left.w == 1268 and moved_left.h == 1384, "left zone monitor move mismatch")

-- Soft-maximize across monitors fills target max work area
local moved_max = geometry.map_rect_between_areas({ x = 0, y = 26, w = 1920, h = 1174 }, src_area, dst_area, "maximize", nil)
assert(moved_max and moved_max.mode == "maximize" and moved_max.x == 1920 and moved_max.y == 0 and moved_max.w == 2560 and moved_max.h == 1400, "maximize monitor move mismatch")

-- Custom Snap Layouts 65/35 zone
local moved_custom = geometry.map_rect_between_areas({ x = 8, y = 34, w = 1235, h = 1158 }, src_area, dst_area, "custom", { rx = 0, ry = 0, rw = 0.65, rh = 1.0, max = false })
local expected_65 = geometry.zone_rect_in_area(dst_area, { rx = 0, ry = 0, rw = 0.65, rh = 1.0, max = false })
assert(moved_custom and moved_custom.mode == "zone" and moved_custom.w == expected_65.w and moved_custom.x == expected_65.x, "custom zone monitor move mismatch")

-- Edge-aligned Snap-Resized pane without explicit custom_zone keeps proportional split
local moved_resized = geometry.map_rect_between_areas({ x = 8, y = 34, w = 1235, h = 1158 }, src_area, dst_area, nil, nil)
assert(moved_resized and moved_resized.mode == "zone" and moved_resized.x == 1928 and moved_resized.y == 8 and moved_resized.h == 1384 and math.abs(moved_resized.w - expected_65.w) <= 2, "edge-aligned pane proportional move mismatch")

-- Free-floating window clamps size/position safely inside target monitor
local moved_float = geometry.map_rect_between_areas({ x = 300, y = 200, w = 1100, h = 700 }, src_area, dst_area, nil, nil)
assert(moved_float and moved_float.mode == "float" and moved_float.w == 1100 and moved_float.h == 700, "free-floating size should be preserved when it fits")
assert(moved_float.x >= dst_area.x and moved_float.x + moved_float.w <= dst_area.x + dst_area.w, "free-floating X must stay inside target work area")
assert(moved_float.y >= dst_area.y and moved_float.y + moved_float.h <= dst_area.y + dst_area.h, "free-floating Y must stay inside target work area")

local oversized_float = geometry.map_rect_between_areas({ x = 0, y = 0, w = 3000, h = 2000 }, dst_area, src_area, nil, nil)
assert(oversized_float and oversized_float.w == src_area.w and oversized_float.h == src_area.h and oversized_float.x == src_area.x and oversized_float.y == src_area.y, "oversized window must clamp to smaller target monitor work area")

-- 12. Alt+Tab MRU ordering and cyclic stepping
local alt_ordered = geometry.order_alttab_windows({
  { address = "0xmin1", mapped = true, focus_history_id = 1, workspace = { id = -98, name = "special:minimized" } },
  { address = "0xopen2", mapped = true, focus_history_id = 3, workspace = { id = 2, name = "2" } },
  { address = "0xunmapped", mapped = false, focus_history_id = 0, workspace = { id = 1, name = "1" } },
  { address = "0xopen1", mapped = true, focus_history_id = 1, workspace = { id = 1, name = "1" } },
  { address = "0xact", mapped = true, focus_history_id = 2, workspace = { id = 1, name = "1" } },
}, "0xact")
assert(#alt_ordered == 4, "unmapped windows must be excluded from Alt+Tab list")
assert(alt_ordered[1].address == "0xact", "active window must come first")
assert(alt_ordered[2].address == "0xopen1", "second window must follow focus_history_id order")
assert(alt_ordered[3].address == "0xopen2", "third window must follow focus_history_id order")
assert(alt_ordered[4].address == "0xmin1", "minimized windows must appear after non-minimized windows")

assert(geometry.step_index(1, 4, 1) == 2, "step forward failed")
assert(geometry.step_index(4, 4, 1) == 1, "step forward wrap failed")
assert(geometry.step_index(1, 4, -1) == 4, "step backward wrap failed")
assert(geometry.step_index(1, 0, 1) == 0, "empty list step failed")

-- 13. Off-screen window rescue geometry (dock/undock & disabled monitor transitions)
local dock_mons = {
  { id = 0, name = "eDP-1", x = 0, y = 0, width = 1920, height = 1200, scale = 1.25, transform = 0, reserved = { 0, 0, 0, 40 }, disabled = true },
  { id = 3, name = "DP-7", x = 1536, y = 0, width = 1920, height = 1200, scale = 1, transform = 0, reserved = { 0, 0, 0, 40 }, active_workspace = { id = 41 } },
  { id = 1, name = "DP-5", x = 3456, y = 0, width = 1920, height = 1200, scale = 1, transform = 0, reserved = { 0, 0, 0, 40 }, active_workspace = { id = 21 } },
  { id = 2, name = "DP-6", x = 5376, y = 0, width = 1920, height = 1200, scale = 1, transform = 0, reserved = { 0, 0, 0, 40 }, active_workspace = { id = 31 } },
}
local dp7_area = geometry.get_work_area(dock_mons[2], 8, 8)
local dp6_area = geometry.get_work_area(dock_mons[4], 8, 8)

-- Workspace monitor wins over focused monitor; stale disabled window.monitor is skipped
local resolved_dp6 = geometry.resolve_active_monitor_for_window({
  monitor = dock_mons[1],
  workspace = { id = 31, name = "31", monitor = dock_mons[4] },
}, dock_mons, dock_mons[2])
assert(resolved_dp6 and resolved_dp6.name == "DP-6", "window on ws 31 must resolve to DP-6 even when focused monitor is DP-7")

-- Gone/disabled monitor falls back to active monitor, then first active monitor
local fallback_active = geometry.resolve_active_monitor_for_window({
  monitor = dock_mons[1],
  workspace = { id = 9, name = "9", monitor = { name = "HDMI-1" } },
}, dock_mons, dock_mons[2])
assert(fallback_active and fallback_active.name == "DP-7", "unplugged monitor window should fall back to active monitor")

local fallback_first = geometry.resolve_active_monitor_for_window({
  monitor = dock_mons[1],
  workspace = { id = 9, name = "9", monitor = dock_mons[1] },
}, dock_mons, dock_mons[1])
assert(fallback_first and fallback_first.name == "DP-7", "disabled active_mon must fall back to first enabled monitor")

-- Stranded soft-maximized Chrome rect (at [1, 31], size [1532, 886] -> outer [-1, -1, 1536, 920] on eDP-1)
local stranded_chrome = { x = -1, y = -1, w = 1536, h = 920 }
assert(geometry.rect_needs_rescue(stranded_chrome, dp6_area) == true, "stranded Chrome must require rescue onto DP-6")
assert(geometry.rect_needs_rescue({ x = 1546, y = 6, w = 658, h = 1144 }, dp7_area) == false, "healthy DP-7 window must not trigger rescue")
assert(geometry.rect_needs_rescue({ x = 7000, y = 20, w = 900, h = 700 }, dp6_area) == false, "partially overhanging window with visible grab bar should not trigger rescue")
assert(geometry.rect_needs_rescue({ x = 5500, y = -200, w = 600, h = 250 }, dp6_area) == true, "window with titlebar off top of monitor must trigger rescue")
assert(geometry.rect_needs_rescue({ x = 5500, y = 1145, w = 600, h = 500 }, dp6_area) == true, "window sunk beneath taskbar must trigger rescue")
assert(geometry.rect_needs_rescue({ x = 5376, y = 100, w = 800, h = 600 }, dp6_area) == false, "flush window inside DP-6 must not trigger rescue")

local found_edp = geometry.find_containing_monitor(stranded_chrome, dock_mons, "DP-6")
assert(found_edp and found_edp.name == "eDP-1", "find_containing_monitor must detect disabled source monitor eDP-1")
local edp_area = geometry.get_work_area(found_edp, 8, 8)
local rescued_chrome = geometry.rescue_rect_to_area(stranded_chrome, dp6_area, nil, nil, edp_area)
assert(rescued_chrome and rescued_chrome.mode == "maximize", "stranded soft-maximized Chrome must preserve maximize mode")
assert(rescued_chrome.x == 5376 and rescued_chrome.y == 0 and rescued_chrome.w == 1920 and rescued_chrome.h == 1160, "rescued Chrome must fill DP-6 max work area")

-- 50% snapped left pane rescued from disabled eDP-1 onto DP-6 preserves proportional snap zone
local edp_left = geometry.zone_rect_in_area(edp_area, cfg.layouts[1][1])
local rescued_left = geometry.rescue_rect_to_area(edp_left, dp6_area, nil, nil, edp_area)
assert(rescued_left and rescued_left.mode == "zone", "50% snapped pane should preserve zone mode on rescue")
assert(rescued_left.x == 5384 and rescued_left.y == 8 and rescued_left.w == 948 and rescued_left.h == 1144, "rescued 50% left pane mismatch on DP-6")

-- Free-floating window whose old monitor already vanished (src_area = nil) clamps & stays inside dst_area
local vanished_float = geometry.rescue_rect_to_area({ x = -2200, y = -300, w = 900, h = 650 }, dp6_area, nil, nil, nil)
assert(vanished_float and vanished_float.mode == "float" and vanished_float.w == 900 and vanished_float.h == 650, "vanished-monitor float must preserve size when it fits")
assert(vanished_float.x >= dp6_area.x and vanished_float.x + vanished_float.w <= dp6_area.x + dp6_area.w, "rescued vanished-monitor float X must lie inside DP-6")
assert(vanished_float.y >= dp6_area.y and vanished_float.y + vanished_float.h <= dp6_area.y + dp6_area.h, "rescued vanished-monitor float Y must lie inside DP-6")

local huge_vanished = geometry.rescue_rect_to_area({ x = 9000, y = 2000, w = 3000, h = 2000 }, dp6_area, nil, nil, nil)
assert(huge_vanished and huge_vanished.x == dp6_area.x and huge_vanished.y == dp6_area.y and huge_vanished.w == dp6_area.w and huge_vanished.h == dp6_area.h, "oversized vanished-monitor float must clamp to dst_area")

-- 14. Multi-monitor drag edge detection, oversized height rescue & free-drop clamping
local dual_mons = {
  { id = 1, name = "DP-1", x = 0, y = 0, width = 1920, height = 1200, scale = 1, transform = 0, reserved = { 0, 0, 0, 40 } },
  { id = 2, name = "DP-2", x = 1920, y = 0, width = 1920, height = 1200, scale = 1, transform = 0, reserved = { 0, 0, 0, 40 } },
  { id = 0, name = "eDP-1", x = 3840, y = 0, width = 1920, height = 1200, scale = 1.25, transform = 0, reserved = { 0, 0, 0, 40 } },
}
local dp1_area = geometry.get_work_area(dual_mons[1], 8, 8)
local dp2_area = geometry.get_work_area(dual_mons[2], 8, 8)
local edp_dock2_area = geometry.get_work_area(dual_mons[3], 8, 8)

-- Oversized 1144px Teams window sitting on 1.25x eDP-1 (max_h = 920) must trigger rescue and clamp
local teams_outer = { x = 3848, y = 8, w = 748, h = 1144 }
assert(geometry.rect_needs_rescue(teams_outer, edp_dock2_area) == true, "oversized tall window on 1.25x eDP-1 must trigger rescue")
local clamped_teams = geometry.clamp_free_drop_rect(teams_outer, edp_dock2_area)
assert(clamped_teams and clamped_teams.x == 3848 and clamped_teams.y == 8 and clamped_teams.w == 748 and clamped_teams.h == edp_dock2_area.h, "clamp_free_drop_rect must shrink oversized height into eDP-1 work area")
assert(geometry.clamp_free_drop_rect({ x = 3900, y = 60, w = 800, h = 600 }, edp_dock2_area) == nil, "comfortable window inside eDP-1 must not be clamped")

-- Bounded edge snap: cursor inside DP-2 (x=2200) must never snap against DP-1 or eDP-1
assert(geometry.detect_drag_edge_zone(2200, 400, dp1_area, dual_mons, "DP-1") == nil, "cursor on DP-2 must never snap on DP-1")
assert(geometry.detect_drag_edge_zone(2200, 400, edp_dock2_area, dual_mons, "eDP-1") == nil, "cursor on DP-2 must never snap on eDP-1")
assert(geometry.detect_drag_edge_zone(2, 400, dp1_area, dual_mons, "DP-1") == "left", "outer left wall of DP-1 should snap left")
assert(geometry.detect_drag_edge_zone(5370, 400, edp_dock2_area, dual_mons, "eDP-1") == "right", "outer right wall of eDP-1 should snap right")
assert(geometry.detect_drag_edge_zone(1926, 400, dp2_area, dual_mons, "DP-2") == "left", "releasing within tight seam margin on DP-2 left should snap left")
assert(geometry.detect_drag_edge_zone(1940, 400, dp2_area, dual_mons, "DP-2") == nil, "crossing seam onto DP-2 must not trigger false left snap")

-- Oversize check gating in rect_needs_rescue (only_unreachable keeps visible oversized windows calm on click)
local oversized_visible_rect = { x = 5400, y = 40, w = 800, h = 1185 }
local offscreen_rect = { x = 100, y = 40, w = 800, h = 600 }
assert(geometry.rect_needs_rescue(oversized_visible_rect, dp6_area, true) == true, "oversized visible rect should require rescue when check_oversize=true")
assert(geometry.rect_needs_rescue(oversized_visible_rect, dp6_area, false) == false, "oversized visible rect must not trigger rescue when check_oversize=false")
assert(geometry.rect_needs_rescue(offscreen_rect, dp6_area, false) == true, "offscreen rect must still trigger rescue when check_oversize=false")

print("ALL GEOMETRY LUA TESTS PASSED")

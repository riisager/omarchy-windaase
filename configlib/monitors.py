"""Multi-monitor dock profile management and monitors.lua synchronization."""

import glob
import json
import math
import os
import re
import shutil
import subprocess
import sys
import time

from .common import atomic_write, config_lock, omarchy_dir

MONITORS_BLOCK_BEGIN = "-- BEGIN OMARCHY-WINDAASE MONITORS"
MONITORS_BLOCK_END = "-- END OMARCHY-WINDAASE MONITORS"
CONNECTOR_NAME_RE = re.compile(r"^[A-Za-z0-9._-]+$")
MODE_STRING_RE = re.compile(r"^(\d{3,5})x(\d{3,5})(?:@(\d+(?:\.\d+)?))?$")

RESCUE_OFFSCREEN_LUA = (
    'local ok, w = pcall(require, "hypr.windaase"); '
    'if ok and w and w.rescue_offscreen_windows then w.rescue_offscreen_windows() end'
)


def monitors_profiles_path(home_dir=None):
    return os.path.join(omarchy_dir(home_dir=home_dir), "windaase-monitors.json")


def monitors_lua_path(home_dir=None):
    home = os.path.expanduser(home_dir) if home_dir else os.path.expanduser("~")
    return os.path.join(home, ".config", "hypr", "monitors.lua")


def monitors_preview_lock_path(runtime_dir=None, home_dir=None):
    home = os.path.expanduser(home_dir) if home_dir else os.path.expanduser("~")
    base = (
        runtime_dir
        or os.environ.get("XDG_RUNTIME_DIR")
        or os.environ.get("XDG_CACHE_HOME")
        or os.path.join(home, ".cache")
    )
    return os.path.join(base, "omarchy-windaase-monitor-preview.json")


def is_internal_connector(name):
    return bool(re.match(r"^(?:eDP|LVDS|DSI)(?:-\d+)?$", str(name or "")))


def validate_connector_name(name):
    if not isinstance(name, str) or not CONNECTOR_NAME_RE.fullmatch(name):
        raise ValueError(f"Unsafe monitor connector name: {name!r}")
    return name


def safe_desc_selector(desc):
    text = str(desc or "").strip()
    if not (1 <= len(text) <= 160):
        return ""
    if any(ch in text for ch in ('"', "'", "\\", "\n", "\r", "\t", "\x00", "$", "`")):
        return ""
    return f"desc:{text}"


def validate_output_selector(selector):
    if not isinstance(selector, str):
        raise ValueError("Monitor selector must be a string")
    if selector.startswith("desc:"):
        desc = selector[5:]
        if safe_desc_selector(desc) != selector:
            raise ValueError(f"Unsafe desc monitor selector: {selector!r}")
        return selector
    return validate_connector_name(selector)


def validate_monitor_mode(mode_str):
    raw = str(mode_str or "").strip()
    if not raw or raw.lower() == "preferred":
        return "preferred"
    clean = re.sub(r"(?i)hz$", "", raw).strip()
    m = MODE_STRING_RE.fullmatch(clean)
    if not m:
        raise ValueError(f"Invalid monitor mode: {mode_str!r}")
    w = int(m.group(1), 10)
    h = int(m.group(2), 10)
    if not (320 <= w <= 16384 and 200 <= h <= 16384):
        raise ValueError(f"Monitor mode dimensions out of range: {mode_str!r}")
    if m.group(3):
        hz = float(m.group(3))
        if not math.isfinite(hz) or hz <= 0 or hz > 1000:
            raise ValueError(f"Monitor refresh rate out of range: {mode_str!r}")
        return f"{w}x{h}@{m.group(3)}"
    return f"{w}x{h}"


def dedupe_available_modes(raw_modes):
    if not isinstance(raw_modes, list):
        return []
    out = []
    seen = set()
    for raw in raw_modes:
        if not isinstance(raw, str):
            continue
        clean = re.sub(r"(?i)hz$", "", raw).strip()
        if not MODE_STRING_RE.fullmatch(clean) or "@" not in clean:
            continue
        if clean not in seen:
            seen.add(clean)
            out.append(clean)
    return out


def clean_hypr_scale(scale, width, height):
    req = float(scale)
    w = int(round(float(width)))
    h = int(round(float(height)))
    if not math.isfinite(req) or req <= 0 or w <= 0 or h <= 0:
        raise ValueError(f"Invalid scale parameters: scale={scale!r}, w={width!r}, h={height!r}")
    req = max(0.25, min(8.0, req))
    divisor = math.gcd(w * 120, h * 120)
    if divisor <= 0:
        return round(req, 4)
    units = max(1, min(divisor, int(round(req * 120))))
    while divisor % units != 0:
        units += 1
    return round(units / 120.0, 4)


def _format_scale_str(scale_val):
    val = float(scale_val)
    if not math.isfinite(val) or val <= 0:
        raise ValueError(f"Invalid monitor scale: {scale_val!r}")
    val = max(0.25, min(8.0, val))
    text = f"{round(val, 4):.4f}".rstrip("0").rstrip(".")
    return text or "1"


def format_hl_monitor_call(output, enabled, mode="preferred", x=0, y=0, scale=1.0, transform=0, include_disabled_false=False):
    sel = validate_output_selector(output)
    if not enabled:
        return f'hl.monitor({{ output = "{sel}", disabled = true }})'
    clean_mode = validate_monitor_mode(mode)
    px = int(round(float(x)))
    py = int(round(float(y)))
    if not (-32768 <= px <= 32768 and -32768 <= py <= 32768):
        raise ValueError(f"Monitor position out of range: {x}, {y}")
    tr = int(round(float(transform))) % 4
    scale_str = _format_scale_str(scale)
    dis_part = "disabled = false, " if include_disabled_false else ""
    tr_part = f", transform = {tr}" if tr in (1, 2, 3) else ""
    return f'hl.monitor({{ output = "{sel}", {dis_part}mode = "{clean_mode}", position = "{px}x{py}", scale = {scale_str}{tr_part} }})'


def is_clamshell_closed(home_dir=None, lid_paths=None):
    home = os.path.expanduser(home_dir) if home_dir else os.path.expanduser("~")
    state_flag = os.path.join(home, ".local", "state", "omarchy", "toggles", "hypr", "internal-monitor-clamshell.lua")
    if os.path.exists(state_flag):
        return True
    paths = lid_paths if lid_paths is not None else glob.glob("/proc/acpi/button/lid/*/state")
    for p in paths:
        try:
            with open(p, "r", encoding="utf-8", errors="ignore") as handle:
                if "closed" in handle.read().lower():
                    return True
        except OSError:
            continue
    return False


def resolve_monitor_match_keys(raw_monitors):
    """Assign hardware matchKey values, display numbers (1..N), and a stable dock profileId."""
    filtered = []
    for raw in raw_monitors or []:
        if not isinstance(raw, dict):
            continue
        name = raw.get("name")
        if not name or name == "FALLBACK":
            continue
        if not isinstance(name, str) or not CONNECTOR_NAME_RE.fullmatch(name):
            continue
        mirror_of = raw.get("mirrorOf")
        if mirror_of not in (None, "", "none"):
            continue
        filtered.append(raw)

    desc_counts = {}
    for raw in filtered:
        if is_internal_connector(raw["name"]):
            continue
        dsel = safe_desc_selector(raw.get("description"))
        if dsel:
            desc_counts[dsel] = desc_counts.get(dsel, 0) + 1

    items = []
    for raw in filtered:
        name = raw["name"]
        internal = is_internal_connector(name)
        dsel = "" if internal else safe_desc_selector(raw.get("description"))
        match_key = name if (internal or not dsel or desc_counts.get(dsel, 0) != 1) else dsel
        items.append({
            "raw": raw,
            "name": name,
            "internal": internal,
            "matchKey": match_key,
        })

    items.sort(key=lambda item: (0 if item["internal"] else 1, item["matchKey"], item["name"]))
    for idx, item in enumerate(items, start=1):
        item["number"] = idx

    profile_id = " | ".join(sorted(item["matchKey"] for item in items))
    return items, profile_id


def _load_monitors_db(home_dir=None):
    path = monitors_profiles_path(home_dir=home_dir)
    if not os.path.exists(path):
        return {"profiles": {}}
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return {"profiles": {}}
    if not isinstance(data, dict) or not isinstance(data.get("profiles"), dict):
        return {"profiles": {}}
    return data


def _save_monitors_db(db, home_dir=None):
    path = monitors_profiles_path(home_dir=home_dir)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    atomic_write(path, json.dumps(db, indent=2, ensure_ascii=False) + "\n")


def _parse_mode_dimensions(mode_str, fallback_w, fallback_h, fallback_hz):
    if mode_str and mode_str != "preferred":
        m = MODE_STRING_RE.fullmatch(mode_str)
        if m:
            w = int(m.group(1), 10)
            h = int(m.group(2), 10)
            hz = float(m.group(3)) if m.group(3) else float(fallback_hz or 60.0)
            return w, h, hz
    return int(fallback_w or 1920), int(fallback_h or 1080), float(fallback_hz or 60.0)


def apply_safety_rules(entries, clamshell_closed):
    """Ensure closed laptops do not force-enable internal screens over externals and never leave 0 displays."""
    if not entries:
        return []
    safe = [dict(e) for e in entries]
    ext_enabled = any(bool(e.get("enabled")) and not is_internal_connector(e.get("name")) for e in safe)
    if clamshell_closed and ext_enabled:
        for e in safe:
            if is_internal_connector(e.get("name")):
                e["enabled"] = False
    if not any(bool(e.get("enabled")) for e in safe):
        target = next((e for e in safe if is_internal_connector(e.get("name"))), safe[0])
        target["enabled"] = True
        target["x"] = 0
        target["y"] = 0
    return safe


def _validate_and_normalize_entries(raw_entries, items_by_key, raw_by_name):
    if not isinstance(raw_entries, list) or not raw_entries:
        raise ValueError("Expected non-empty monitors list")
    parsed = []
    seen_keys = set()
    for entry in raw_entries:
        if not isinstance(entry, dict):
            raise ValueError("Each monitor entry must be an object")
        name = validate_connector_name(entry.get("name", ""))
        item = items_by_key.get(entry.get("matchKey")) or items_by_key.get(name)
        if item is None:
            raise ValueError(f"Unknown or disconnected monitor: {name}")
        mkey = item["matchKey"]
        if mkey in seen_keys:
            raise ValueError(f"Duplicate monitor key in payload: {mkey}")
        seen_keys.add(mkey)

        raw = raw_by_name[item["name"]]
        avail_modes = dedupe_available_modes(raw.get("availableModes") or [])
        fb_w = int(raw.get("width") or 1920)
        fb_h = int(raw.get("height") or 1080)
        fb_hz = float(raw.get("refreshRate") or 60.0)

        enabled = bool(entry.get("enabled", True))
        mode = validate_monitor_mode(entry.get("mode", "preferred"))
        mode_w, mode_h, mode_hz = _parse_mode_dimensions(mode, fb_w, fb_h, fb_hz)
        scale_in = entry.get("scale", raw.get("scale") or 1.0)
        clean_sc = clean_hypr_scale(scale_in, mode_w, mode_h)
        transform = int(round(float(entry.get("transform", raw.get("transform") or 0)))) % 4
        x = int(round(float(entry.get("x", raw.get("x") or 0))))
        y = int(round(float(entry.get("y", raw.get("y") or 0))))
        if not (-32768 <= x <= 32768 and -32768 <= y <= 32768):
            raise ValueError(f"Monitor position out of bounds: {x}, {y}")

        parsed.append({
            "name": item["name"],
            "matchKey": mkey,
            "internal": item["internal"],
            "enabled": enabled,
            "mode": mode,
            "x": x,
            "y": y,
            "scale": clean_sc,
            "transform": transform,
            "width": mode_w,
            "height": mode_h,
            "refreshRate": mode_hz,
            "availableModes": avail_modes,
        })

    for item in items_by_key.values():
        if item["matchKey"] not in seen_keys:
            raw = raw_by_name[item["name"]]
            parsed.append({
                "name": item["name"],
                "matchKey": item["matchKey"],
                "internal": item["internal"],
                "enabled": not bool(raw.get("disabled")),
                "mode": "preferred",
                "x": int(raw.get("x") or 0),
                "y": int(raw.get("y") or 0),
                "scale": float(raw.get("scale") or 1.0),
                "transform": int(raw.get("transform") or 0) % 4,
                "width": int(raw.get("width") or 1920),
                "height": int(raw.get("height") or 1080),
                "refreshRate": float(raw.get("refreshRate") or 60.0),
                "availableModes": dedupe_available_modes(raw.get("availableModes") or []),
            })
            seen_keys.add(item["matchKey"])

    return parsed


def _strip_legacy_monitors_rules(text):
    lines = text.splitlines(keepends=True)
    out = []
    i = 0
    n = len(lines)
    monitor_rule_re = re.compile(r'^\s*hl\.monitor\(\{.*output\s*=\s*"([^"]*)"')
    while i < n:
        line = lines[i]
        stripped = line.strip()
        # Strip custom eDP auto-switcher block when migrating pre-Windaase monitors.lua.
        if re.match(r"^\s*local\s+last_edp_pos\s*=", line):
            i += 1
            while i < n:
                if re.match(r'^\s*hl\.on\(\s*"monitor\.removed"', lines[i]):
                    i += 1
                    while i < n and not re.match(r"^\s*end\)\s*$", lines[i]):
                        i += 1
                    i += 1
                    break
                i += 1
            continue
        m = monitor_rule_re.match(line)
        if m and m.group(1) != "" and not stripped.startswith("--"):
            i += 1
            continue
        out.append(line)
        i += 1
    return "".join(out)


def sync_monitors_lua(path, rules, gdk_scale, create_backup=True):
    """Maintain single-line hl.monitor rules and GDK_SCALE inside ~/.config/hypr/monitors.lua."""
    existing = ""
    existed = os.path.exists(path)
    if existed:
        with open(path, "r", encoding="utf-8") as handle:
            existing = handle.read()

    has_block = MONITORS_BLOCK_BEGIN in existing and MONITORS_BLOCK_END in existing
    if existed and create_backup and not has_block:
        bak_path = f"{path}.bak-windaase-{int(time.time())}"
        shutil.copy2(path, bak_path)

    base_text = existing if has_block else _strip_legacy_monitors_rules(existing)
    if has_block:
        block_re = re.compile(
            re.escape(MONITORS_BLOCK_BEGIN) + r".*?" + re.escape(MONITORS_BLOCK_END) + r"[ \t]*\r?\n?",
            re.DOTALL,
        )
        base_text = block_re.sub("", base_text, count=1)

    rule_lines = [
        MONITORS_BLOCK_BEGIN,
        "-- Managed automatically by Omarchy-windaase dock profiles.",
    ]
    ordered_rules = [r for r in rules if bool(r.get("enabled", True))] + [
        r for r in rules if not bool(r.get("enabled", True))
    ]
    for r in ordered_rules:
        sel = r["name"] if is_internal_connector(r["name"]) else r.get("matchKey", r["name"])
        rule_lines.append(
            format_hl_monitor_call(
                sel,
                bool(r.get("enabled", True)),
                mode=r.get("mode", "preferred"),
                x=r.get("x", 0),
                y=r.get("y", 0),
                scale=r.get("scale", 1.0),
                transform=r.get("transform", 0),
                include_disabled_false=False,
            )
        )
    rule_lines.append(MONITORS_BLOCK_END)
    block_text = "\n".join(rule_lines) + "\n"

    gdk_int = max(1, int(gdk_scale))
    gdk_re = re.compile(r"(^\s*local\s+omarchy_gdk_scale\s*=\s*)\d+(.*)$", re.MULTILINE)
    if gdk_re.search(base_text):
        base_text = gdk_re.sub(rf"\g<1>{gdk_int}\g<2>", base_text, count=1)

    catchall_re = re.compile(r'(^\s*hl\.monitor\(\{[^}\n]*output\s*=\s*""[^}\n]*\}\)[ \t]*\r?\n?)', re.MULTILINE)
    m_catch = catchall_re.search(base_text)
    if m_catch:
        pos = m_catch.end()
        prefix = base_text[:pos].rstrip("\n")
        suffix = base_text[pos:].lstrip("\n")
        combined = f"{prefix}\n\n{block_text}\n{suffix}" if suffix else f"{prefix}\n\n{block_text}"
    else:
        gdk_pos = gdk_re.search(base_text)
        if gdk_pos:
            pos = gdk_pos.start()
            prefix = base_text[:pos].rstrip("\n")
            suffix = base_text[pos:]
            combined = f"{prefix}\n\n{block_text}\n{suffix}" if prefix else f"{block_text}\n{suffix}"
        else:
            trimmed = base_text.strip("\n")
            combined = f"{trimmed}\n\n{block_text}" if trimmed else block_text
            if "omarchy_gdk_scale" not in combined:
                combined += f'\nlocal omarchy_gdk_scale = {gdk_int}\nhl.env("GDK_SCALE", tostring(omarchy_gdk_scale))\n'

    combined = re.sub(r"\n{3,}", "\n\n", combined.lstrip("\n"))
    if not combined.endswith("\n"):
        combined += "\n"

    if combined != existing:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        atomic_write(path, combined)
        return True
    return False


def strip_monitors_lua_block(path):
    """Remove the Windaase-managed monitors block from monitors.lua cleanly."""
    if not os.path.exists(path):
        return False
    with open(path, "r", encoding="utf-8") as handle:
        text = handle.read()
    if MONITORS_BLOCK_BEGIN not in text or MONITORS_BLOCK_END not in text:
        return False
    block_re = re.compile(
        r"\n?" + re.escape(MONITORS_BLOCK_BEGIN) + r".*?" + re.escape(MONITORS_BLOCK_END) + r"[ \t]*\r?\n?",
        re.DOTALL,
    )
    updated = block_re.sub("\n", text, count=1)
    updated = re.sub(r"\n{3,}", "\n\n", updated.lstrip("\n"))
    if updated and not updated.endswith("\n"):
        updated += "\n"
    if updated != text:
        atomic_write(path, updated)
        return True
    return False


def _default_hyprctl_monitors():
    res = subprocess.run(["hyprctl", "-j", "monitors", "all"], capture_output=True, text=True, check=True, timeout=5)
    return json.loads(res.stdout)


def _default_hyprctl_eval(expr, ignore_errors=False):
    res = subprocess.run(
        ["hyprctl", "eval", expr],
        capture_output=True,
        text=True,
        check=False,
        timeout=5,
    )
    if not ignore_errors and res.returncode != 0:
        detail = (res.stderr or res.stdout or "").strip() or f"exit {res.returncode}"
        raise RuntimeError(f"hyprctl eval failed: {detail}")


def _eval_monitor_entries(entries, hypr_eval=_default_hyprctl_eval, rescue=True):
    enabled_list = [e for e in entries if e.get("enabled")]
    disabled_list = [e for e in entries if not e.get("enabled")]
    for e in enabled_list + disabled_list:
        expr = format_hl_monitor_call(
            e["name"],
            bool(e.get("enabled")),
            mode=e.get("mode", "preferred"),
            x=e.get("x", 0),
            y=e.get("y", 0),
            scale=e.get("scale", 1.0),
            transform=e.get("transform", 0),
            include_disabled_false=True,
        )
        hypr_eval(expr)
    if rescue:
        if hypr_eval is _default_hyprctl_eval:
            _default_hyprctl_eval(RESCUE_OFFSCREEN_LUA, ignore_errors=True)
        else:
            hypr_eval(RESCUE_OFFSCREEN_LUA)


def _compute_gdk_scale(entries):
    scales = [float(e.get("scale") or 1.0) for e in entries if e.get("enabled")]
    min_scale = min(scales) if scales else 1.0
    return max(1, int(min_scale + 0.5))


def build_monitors_status(raw_monitors, home_dir=None, lid_paths=None):
    items, profile_id = resolve_monitor_match_keys(raw_monitors)
    db = _load_monitors_db(home_dir=home_dir)
    saved_profile = db["profiles"].get(profile_id)
    saved_by_key = {}
    if isinstance(saved_profile, dict) and isinstance(saved_profile.get("monitors"), list):
        for sm in saved_profile["monitors"]:
            if isinstance(sm, dict) and sm.get("matchKey"):
                saved_by_key[sm["matchKey"]] = sm

    clamshell = is_clamshell_closed(home_dir=home_dir, lid_paths=lid_paths)
    has_ext_enabled = any((not it["internal"]) and (not bool(it["raw"].get("disabled"))) for it in items)

    monitors_out = []
    for it in items:
        raw = it["raw"]
        avail = dedupe_available_modes(raw.get("availableModes") or [])
        w = int(raw.get("width") or 1920)
        h = int(raw.get("height") or 1080)
        hz = float(raw.get("refreshRate") or 60.0)
        live_mode = f"{w}x{h}@{hz:.2f}"
        saved = saved_by_key.get(it["matchKey"])
        mode = "preferred"
        if saved and isinstance(saved.get("mode"), str):
            cand_mode = validate_monitor_mode(saved["mode"])
            if cand_mode != "preferred":
                sw, sh, shz = _parse_mode_dimensions(cand_mode, w, h, hz)
                if sw == w and sh == h and abs(shz - hz) <= 1.0:
                    mode = cand_mode
        enabled = not bool(raw.get("disabled"))
        monitors_out.append({
            "number": it["number"],
            "name": it["name"],
            "matchKey": it["matchKey"],
            "description": str(raw.get("description") or it["name"]),
            "model": str(raw.get("model") or it["name"]),
            "make": str(raw.get("make") or ""),
            "internal": it["internal"],
            "enabled": enabled,
            "clamshellLocked": bool(it["internal"] and clamshell and has_ext_enabled),
            "focused": bool(raw.get("focused")),
            "width": w,
            "height": h,
            "refreshRate": hz,
            "mode": mode,
            "liveMode": live_mode,
            "availableModes": avail,
            "x": int(raw.get("x") or 0),
            "y": int(raw.get("y") or 0),
            "scale": float(raw.get("scale") or 1.0),
            "transform": int(raw.get("transform") or 0) % 4,
        })

    return {
        "profileId": profile_id,
        "profileSaved": saved_profile is not None,
        "clamshellClosed": clamshell,
        "monitors": monitors_out,
    }


def monitors_preview_action(raw_monitors, payload, home_dir=None, runtime_dir=None, lid_paths=None, hypr_eval=_default_hyprctl_eval):
    items, _ = resolve_monitor_match_keys(raw_monitors)
    items_by_key = {}
    raw_by_name = {}
    for it in items:
        items_by_key[it["matchKey"]] = it
        items_by_key[it["name"]] = it
        raw_by_name[it["name"]] = it["raw"]

    raw_entries = payload.get("monitors") if isinstance(payload, dict) else payload
    desired = _validate_and_normalize_entries(raw_entries, items_by_key, raw_by_name)
    desired = apply_safety_rules(desired, is_clamshell_closed(home_dir=home_dir, lid_paths=lid_paths))

    revert_entries = []
    for it in items:
        raw = it["raw"]
        w = int(raw.get("width") or 1920)
        h = int(raw.get("height") or 1080)
        hz = float(raw.get("refreshRate") or 60.0)
        avail = dedupe_available_modes(raw.get("availableModes") or [])
        cur_mode = f"{w}x{h}@{hz:.2f}"
        pref_mode = avail[0] if avail else cur_mode
        revert_entries.append({
            "name": it["name"],
            "matchKey": it["matchKey"],
            "internal": it["internal"],
            "enabled": not bool(raw.get("disabled")),
            "mode": "preferred" if cur_mode == pref_mode else cur_mode,
            "x": int(raw.get("x") or 0),
            "y": int(raw.get("y") or 0),
            "scale": float(raw.get("scale") or 1.0),
            "transform": int(raw.get("transform") or 0) % 4,
        })

    lock_path = monitors_preview_lock_path(runtime_dir=runtime_dir, home_dir=home_dir)
    os.makedirs(os.path.dirname(lock_path), exist_ok=True)
    atomic_write(lock_path, json.dumps({
        "expiresAt": time.time() + 20.0,
        "revert": revert_entries,
    }) + "\n")

    _eval_monitor_entries(desired, hypr_eval=hypr_eval, rescue=True)
    return {"ok": True, "revert": revert_entries}


def monitors_commit_action(raw_monitors, payload, home_dir=None, runtime_dir=None, lid_paths=None, hypr_eval=_default_hyprctl_eval):
    items, profile_id = resolve_monitor_match_keys(raw_monitors)
    items_by_key = {}
    raw_by_name = {}
    for it in items:
        items_by_key[it["matchKey"]] = it
        items_by_key[it["name"]] = it
        raw_by_name[it["name"]] = it["raw"]

    raw_entries = payload.get("monitors") if isinstance(payload, dict) else payload
    desired = _validate_and_normalize_entries(raw_entries, items_by_key, raw_by_name)
    clamshell = is_clamshell_closed(home_dir=home_dir, lid_paths=lid_paths)

    lock_path = monitors_preview_lock_path(runtime_dir=runtime_dir, home_dir=home_dir)
    if os.path.exists(lock_path) and not os.path.islink(lock_path):
        os.unlink(lock_path)

    with config_lock(home_dir=home_dir):
        db = _load_monitors_db(home_dir=home_dir)
        prev_profile = db["profiles"].get(profile_id)
        prev_by_key = {}
        if isinstance(prev_profile, dict) and isinstance(prev_profile.get("monitors"), list):
            for pm in prev_profile["monitors"]:
                if isinstance(pm, dict) and pm.get("matchKey"):
                    prev_by_key[pm["matchKey"]] = pm

        # Preserve internal panel's open-lid preference while lid is physically closed over externals.
        ext_enabled = any(bool(e["enabled"]) and not e["internal"] for e in desired)
        saved_desired = [dict(e) for e in desired]
        if clamshell and ext_enabled:
            for e in saved_desired:
                if e["internal"]:
                    prev = prev_by_key.get(e["matchKey"])
                    e["enabled"] = bool(prev.get("enabled", True)) if prev else True
        if not any(bool(e["enabled"]) for e in saved_desired):
            target = next((e for e in saved_desired if e["internal"]), saved_desired[0])
            target["enabled"] = True

        runtime_desired = apply_safety_rules(saved_desired, clamshell)

        db["profiles"][profile_id] = {
            "monitors": [
                {
                    "matchKey": e["matchKey"],
                    "name": e["name"],
                    "enabled": bool(e["enabled"]),
                    "mode": e["mode"],
                    "x": int(e["x"]),
                    "y": int(e["y"]),
                    "scale": float(e["scale"]),
                    "transform": int(e["transform"]),
                }
                for e in saved_desired
            ]
        }
        _save_monitors_db(db, home_dir=home_dir)
        sync_monitors_lua(monitors_lua_path(home_dir=home_dir), saved_desired, _compute_gdk_scale(runtime_desired))

    _eval_monitor_entries(runtime_desired, hypr_eval=hypr_eval, rescue=True)
    return {"ok": True, "profileId": profile_id, "profileSaved": True}


def monitors_revert_action(raw_monitors=None, payload=None, home_dir=None, runtime_dir=None, lid_paths=None, hypr_eval=_default_hyprctl_eval):
    lock_path = monitors_preview_lock_path(runtime_dir=runtime_dir, home_dir=home_dir)
    revert_list = None
    if payload is not None:
        revert_list = payload.get("monitors") if isinstance(payload, dict) else payload
    elif os.path.exists(lock_path):
        try:
            with open(lock_path, "r", encoding="utf-8") as handle:
                data = json.load(handle)
            if isinstance(data, dict) and isinstance(data.get("revert"), list):
                revert_list = data["revert"]
        except (OSError, ValueError):
            revert_list = None

    if os.path.exists(lock_path) and not os.path.islink(lock_path):
        os.unlink(lock_path)

    if not revert_list or not raw_monitors:
        return {"ok": True, "reverted": False}

    items, _ = resolve_monitor_match_keys(raw_monitors)
    items_by_key = {}
    raw_by_name = {}
    for it in items:
        items_by_key[it["matchKey"]] = it
        items_by_key[it["name"]] = it
        raw_by_name[it["name"]] = it["raw"]

    entries = _validate_and_normalize_entries(revert_list, items_by_key, raw_by_name)
    entries = apply_safety_rules(entries, is_clamshell_closed(home_dir=home_dir, lid_paths=lid_paths))
    _eval_monitor_entries(entries, hypr_eval=hypr_eval, rescue=True)
    return {"ok": True, "reverted": True}


def _entry_differs_from_live(desired, raw_live):
    live_enabled = not bool(raw_live.get("disabled"))
    if bool(desired["enabled"]) != live_enabled:
        return True
    if not desired["enabled"]:
        return False
    if int(desired["x"]) != int(raw_live.get("x") or 0):
        return True
    if int(desired["y"]) != int(raw_live.get("y") or 0):
        return True
    if (int(desired["transform"]) % 4) != (int(raw_live.get("transform") or 0) % 4):
        return True
    if abs(float(desired["scale"]) - float(raw_live.get("scale") or 1.0)) > 0.01:
        return True
    if desired["mode"] != "preferred":
        w = int(raw_live.get("width") or 0)
        h = int(raw_live.get("height") or 0)
        hz = float(raw_live.get("refreshRate") or 0.0)
        mw, mh, mhz = _parse_mode_dimensions(desired["mode"], w, h, hz)
        if w != mw or h != mh or abs(hz - mhz) > 1.0:
            return True
    return False


def monitors_apply_action(raw_monitors, home_dir=None, runtime_dir=None, lid_paths=None, hypr_eval=_default_hyprctl_eval):
    lock_path = monitors_preview_lock_path(runtime_dir=runtime_dir, home_dir=home_dir)
    if os.path.exists(lock_path):
        try:
            with open(lock_path, "r", encoding="utf-8") as handle:
                lock_data = json.load(handle)
            if isinstance(lock_data, dict) and float(lock_data.get("expiresAt", 0)) > time.time():
                return {"ok": True, "skipped": "preview-active"}
        except (OSError, ValueError, TypeError):
            pass

    items, profile_id = resolve_monitor_match_keys(raw_monitors)
    if not items:
        return {"ok": True, "applied": False}

    clamshell = is_clamshell_closed(home_dir=home_dir, lid_paths=lid_paths)
    db = _load_monitors_db(home_dir=home_dir)
    saved_profile = db["profiles"].get(profile_id)
    if not isinstance(saved_profile, dict) or not isinstance(saved_profile.get("monitors"), list):
        # Recover if disconnecting a dock left every remaining monitor disabled.
        if all(bool(it["raw"].get("disabled")) for it in items):
            target = next((it for it in items if it["internal"]), items[0])
            raw = target["raw"]
            _eval_monitor_entries(
                [{
                    "name": target["name"],
                    "enabled": True,
                    "mode": "preferred",
                    "x": 0,
                    "y": 0,
                    "scale": float(raw.get("scale") or 1.0),
                    "transform": int(raw.get("transform") or 0) % 4,
                }],
                hypr_eval=hypr_eval,
                rescue=True,
            )
            return {"ok": True, "recovered": True}
        return {"ok": True, "applied": False}

    saved_by_key = {sm["matchKey"]: sm for sm in saved_profile["monitors"] if isinstance(sm, dict) and sm.get("matchKey")}
    desired = []
    for it in items:
        raw = it["raw"]
        sm = saved_by_key.get(it["matchKey"])
        if sm:
            desired.append({
                "name": it["name"],
                "matchKey": it["matchKey"],
                "internal": it["internal"],
                "enabled": bool(sm.get("enabled", True)),
                "mode": validate_monitor_mode(sm.get("mode", "preferred")),
                "x": int(round(float(sm.get("x", 0)))),
                "y": int(round(float(sm.get("y", 0)))),
                "scale": float(sm.get("scale", 1.0)),
                "transform": int(round(float(sm.get("transform", 0)))) % 4,
            })
        else:
            desired.append({
                "name": it["name"],
                "matchKey": it["matchKey"],
                "internal": it["internal"],
                "enabled": not bool(raw.get("disabled")),
                "mode": "preferred",
                "x": int(raw.get("x") or 0),
                "y": int(raw.get("y") or 0),
                "scale": float(raw.get("scale") or 1.0),
                "transform": int(raw.get("transform") or 0) % 4,
            })

    desired = apply_safety_rules(desired, clamshell)
    raw_by_name = {it["name"]: it["raw"] for it in items}
    to_apply = [e for e in desired if _entry_differs_from_live(e, raw_by_name[e["name"]])]
    if to_apply:
        _eval_monitor_entries(to_apply, hypr_eval=hypr_eval, rescue=True)

    # Apply live monitor rules only; writing monitors.lua here triggers Hyprland auto-reloads mid-hotplug.
    return {"ok": True, "applied": len(to_apply) > 0, "profileId": profile_id}


def cmd_monitors_status(args):
    if args:
        raise ValueError("monitors-status takes no arguments")
    raw_monitors = _default_hyprctl_monitors()
    status = build_monitors_status(raw_monitors)
    sys.stdout.write(json.dumps(status, separators=(",", ":"), ensure_ascii=False) + "\n")


def cmd_monitors_preview(args):
    if len(args) != 1:
        raise ValueError("Expected <json> for monitors-preview")
    payload = json.loads(args[0])
    raw_monitors = _default_hyprctl_monitors()
    res = monitors_preview_action(raw_monitors, payload)
    sys.stdout.write(json.dumps(res, separators=(",", ":"), ensure_ascii=False) + "\n")


def cmd_monitors_commit(args):
    if len(args) != 1:
        raise ValueError("Expected <json> for monitors-commit")
    payload = json.loads(args[0])
    raw_monitors = _default_hyprctl_monitors()
    monitors_commit_action(raw_monitors, payload)
    status = build_monitors_status(_default_hyprctl_monitors())
    sys.stdout.write(json.dumps(status, separators=(",", ":"), ensure_ascii=False) + "\n")


def cmd_monitors_revert(args):
    if len(args) > 1:
        raise ValueError("Expected optional <json> for monitors-revert")
    payload = json.loads(args[0]) if len(args) == 1 else None
    raw_monitors = _default_hyprctl_monitors()
    monitors_revert_action(raw_monitors=raw_monitors, payload=payload)
    status = build_monitors_status(_default_hyprctl_monitors())
    sys.stdout.write(json.dumps(status, separators=(",", ":"), ensure_ascii=False) + "\n")


def cmd_monitors_apply(args):
    if args:
        raise ValueError("monitors-apply takes no arguments")
    raw_monitors = _default_hyprctl_monitors()
    res = monitors_apply_action(raw_monitors)
    sys.stdout.write(json.dumps(res, separators=(",", ":"), ensure_ascii=False) + "\n")


def cmd_strip_monitors_block(args):
    if args:
        raise ValueError("strip-monitors-block takes no arguments")
    with config_lock():
        strip_monitors_lua_block(monitors_lua_path())

"""Browser multi-profile detection for Chromium and Gecko windows."""

import glob
import json
import os
import re
import sys

CHROMIUM_BROWSER_SUBDIRS = {
    "google-chrome": ".config/google-chrome",
    "chromium": ".config/chromium",
    "brave-browser": ".config/BraveSoftware/Brave-Browser",
    "brave": ".config/BraveSoftware/Brave-Browser",
    "vivaldi-stable": ".config/vivaldi",
    "vivaldi": ".config/vivaldi",
    "vivaldi-snapshot": ".config/vivaldi-snapshot",
    "microsoft-edge": ".config/microsoft-edge",
    "microsoft-edge-stable": ".config/microsoft-edge",
    "microsoft-edge-beta": ".config/microsoft-edge-beta",
    "microsoft-edge-dev": ".config/microsoft-edge-dev",
}
GECKO_BROWSER_SUBDIRS = {
    "firefox": (".mozilla/firefox", ".config/mozilla/firefox"),
    "org.mozilla.firefox": (".mozilla/firefox", ".config/mozilla/firefox"),
    "firefox-developer-edition": (".mozilla/firefox", ".config/mozilla/firefox"),
    "firefox-nightly": (".mozilla/firefox", ".config/mozilla/firefox"),
    "zen": (".zen",),
    "zen-browser": (".zen",),
    "zen-beta": (".zen",),
    "zen-alpha": (".zen",),
    "zen-twilight": (".zen",),
    "app.zen_browser.zen": (".zen",),
    "io.github.zen_browser.zen": (".zen",),
}
MAX_SESSION_BYTES = 4 * 1024 * 1024
INCOGNITO_RE = re.compile(
    r"[\[(](?:incognito|inkognito|inprivate|guest|gæst|private(?:\s+browsing)?|privat\s+(?:browsing|vindue))[\])]"
    r"|(?:^|[-\u2013\u2014]\s+)(?:InPrivate|(?:(?:Mozilla\s+Firefox|Zen(?:\s+Browser)?)\s+)?(?:Private\s+Browsing|Privat\s+(?:browsing|vindue)))\b",
    re.IGNORECASE,
)
BROWSER_SUFFIX_RE = re.compile(
    r"\s+[-\u2013\u2014]\s+(?:Google Chrome|Chromium|Brave(?:\s+Browser)?|Vivaldi|Microsoft\u200b?\s+Edge(?:\s+(?:Beta|Dev|Canary))?|Mozilla Firefox|Firefox(?:\s+(?:Developer Edition|Nightly))?|Zen(?:\s+Browser)?)\s*$",
    re.IGNORECASE,
)
EDGE_MORE_PAGES_RE = re.compile(r"\s+(?:and\s+\d+\s+more\s+pages?|og\s+\d+\s+flere\s+sider?)\s*$", re.IGNORECASE)
UNREAD_PREFIX_RE = re.compile(r"^(?:\(\d+\)|[•●])\s+")
GENERIC_BROWSER_TITLES = frozenset({
    "new tab",
    "ny fane",
    "untitled",
    "unavngivet",
    "about:blank",
    "google chrome",
    "chromium",
    "brave",
    "vivaldi",
    "microsoft edge",
    "edge",
    "firefox",
    "zen",
    "zen browser",
})


def _normalize_address(raw_addr):
    s = str(raw_addr or "").strip()
    m = re.fullmatch(r"(?:0[xX])?([0-9a-fA-F]{1,20})", s)
    return ("0x" + m.group(1).lower()) if m else ""


def _is_valid_profile_dir(name):
    if not isinstance(name, str):
        return False
    trimmed = name.strip()
    if not trimmed or len(trimmed) > 64 or trimmed in (".", ".."):
        return False
    if re.search(r"[/\\\x00-\x1f\x7f]", name):
        return False
    return True


def _strip_edge_profile_segment(text, profile_names_lower=None):
    m = re.match(r"^(.*?)\s+[-\u2013\u2014]\s+([^\-\u2013\u2014]+)$", text)
    if not m:
        return text, ""
    head, tail = m.group(1).strip(), m.group(2).strip()
    if profile_names_lower is not None and tail.lower() not in profile_names_lower:
        return text, ""
    return head, tail


def _browser_title_candidates(title, initial_title, profile_names_lower=None):
    out = []
    seen = set()

    def add(val):
        text = str(val or "").strip()
        if len(text) < 3 or text.lower() in GENERIC_BROWSER_TITLES:
            return
        if text not in seen:
            seen.add(text)
            out.append(text)

    for raw in (title, initial_title):
        clean_title = BROWSER_SUFFIX_RE.sub("", str(raw or "")).strip()
        add(clean_title)
        unread_stripped = UNREAD_PREFIX_RE.sub("", clean_title).strip()
        if unread_stripped != clean_title:
            add(unread_stripped)
        if profile_names_lower:
            no_prof, _ = _strip_edge_profile_segment(unread_stripped, profile_names_lower)
            if no_prof != unread_stripped:
                add(no_prof)
            no_pages = EDGE_MORE_PAGES_RE.sub("", no_prof).strip()
            if no_pages != no_prof:
                add(no_pages)
        else:
            no_pages = EDGE_MORE_PAGES_RE.sub("", unread_stripped).strip()
            if no_pages != unread_stripped:
                add(no_pages)
    return out


def _read_tail_bytes(path, max_bytes=MAX_SESSION_BYTES):
    try:
        with open(path, "rb") as handle:
            handle.seek(0, os.SEEK_END)
            size = handle.tell()
            if size > max_bytes:
                handle.seek(-max_bytes, os.SEEK_END)
            else:
                handle.seek(0)
            return handle.read()
    except OSError:
        return b""


def _load_chromium_context(base_dir):
    state_path = os.path.join(base_dir, "Local State")
    if not os.path.isfile(state_path):
        return None
    try:
        with open(state_path, "r", encoding="utf-8") as handle:
            parsed = json.load(handle)
    except (OSError, ValueError):
        return None

    prof_obj = parsed.get("profile") if isinstance(parsed, dict) else None
    info_cache = prof_obj.get("info_cache") if isinstance(prof_obj, dict) else None
    if not isinstance(info_cache, dict):
        return None

    profiles = {}
    for pdir, info in info_cache.items():
        if pdir in ("System Profile", "Guest Profile") or not _is_valid_profile_dir(pdir):
            continue
        if not isinstance(info, dict):
            continue
        if info.get("is_ephemeral") is True or info.get("is_omitted_from_profile_list") is True:
            continue

        raw_name = info.get("name") or info.get("shortcut_name") or info.get("gaia_name") or pdir
        name = re.sub(r"[\r\n\t]+", " ", str(raw_name)).strip()[:64] or pdir
        initial = (name[0].upper() if name else "?") or "?"

        pic_file = ""
        for pic_key in ("gaia_picture_file_name", "edge_picture_file_name", "avatar_picture_file_name"):
            cand_pic = str(info.get(pic_key) or "").strip()
            if cand_pic:
                pic_file = cand_pic
                break

        picture_path = ""
        if _is_valid_profile_dir(pic_file):
            candidate_pic = os.path.join(base_dir, pdir, pic_file)
            if os.path.isfile(candidate_pic):
                picture_path = candidate_pic
        elif not pic_file:
            edge_pic = os.path.join(base_dir, pdir, "Edge Profile Picture.png")
            if os.path.isfile(edge_pic):
                picture_path = edge_pic

        try:
            active_time = float(info.get("active_time") or 0.0)
        except (TypeError, ValueError):
            active_time = 0.0

        profiles[pdir] = {
            "dir": pdir,
            "name": name,
            "initial": initial,
            "picturePath": picture_path,
            "active_time": active_time,
            "blobs": None,
        }

    # Only tag browsers when the user has 2+ configured profiles.
    if len(profiles) < 2:
        return None

    last_used = str(prof_obj.get("last_used") or "")
    raw_active = prof_obj.get("last_active_profiles")
    active_list = [p for p in (raw_active if isinstance(raw_active, list) else []) if p in profiles]

    name_map = {}
    for prof in profiles.values():
        name_map.setdefault(prof["name"].lower(), []).append(prof)

    return {
        "base_dir": base_dir,
        "profiles": profiles,
        "name_map": name_map,
        "active_list": active_list,
        "active_set": set(active_list),
        "last_used": last_used if last_used in profiles else "",
    }


def _match_chromium_title_profile(title, ctx):
    stripped = BROWSER_SUFFIX_RE.sub("", str(title or "")).strip()
    if not stripped:
        return None
    _, seg = _strip_edge_profile_segment(stripped, None)
    if not seg:
        return None
    matches = ctx["name_map"].get(seg.lower(), [])
    if len(matches) == 1:
        return matches[0]
    return None


def _profile_session_blobs(ctx, pdir):
    prof = ctx["profiles"][pdir]
    if prof["blobs"] is not None:
        return prof["blobs"]
    blobs = []
    sessions_dir = os.path.join(ctx["base_dir"], pdir, "Sessions")
    if os.path.isdir(sessions_dir):
        for prefix in ("Session_*", "Tabs_*"):
            try:
                paths = glob.glob(os.path.join(sessions_dir, prefix))
                paths.sort(key=os.path.getmtime, reverse=True)
            except OSError:
                paths = []
            if paths:
                data = _read_tail_bytes(paths[0])
                if data:
                    blobs.append(data)
    prof["blobs"] = blobs
    return blobs


def _public_profile_payload(prof, confident):
    return {
        "dir": prof["dir"],
        "name": prof["name"],
        "initial": prof["initial"],
        "picturePath": prof["picturePath"],
        "confident": bool(confident),
    }


def _resolve_gecko_profile_path(base_dir, raw_path, is_relative):
    path = str(raw_path or "").strip()
    if not path or re.search(r"[\x00-\x1f\x7f]", path):
        return ""
    if is_relative:
        if path.startswith("/") or "\\" in path:
            return ""
        parts = path.split("/")
        if any(part == ".." for part in parts):
            return ""
        base_real = os.path.realpath(base_dir)
        cand_real = os.path.realpath(os.path.join(base_real, *parts))
        if cand_real != base_real and not cand_real.startswith(base_real + os.sep):
            return ""
        return cand_real
    if not os.path.isabs(path) or ".." in path.split(os.sep):
        return ""
    return os.path.realpath(path)


def _load_gecko_context(home, candidate_subdirs):
    base_dir = ""
    ini_path = ""
    for sub in candidate_subdirs:
        cand_dir = os.path.join(home, sub)
        cand_ini = os.path.join(cand_dir, "profiles.ini")
        if os.path.isfile(cand_ini):
            base_dir = cand_dir
            ini_path = cand_ini
            break
    if not ini_path:
        return None
    try:
        with open(ini_path, "r", encoding="utf-8", errors="ignore") as handle:
            raw = handle.read()
    except OSError:
        return None

    sections = {}
    section_order = []
    current = ""
    for line in raw.splitlines():
        s = line.strip()
        if not s or s[0] in ("#", ";"):
            continue
        sec_m = re.fullmatch(r"\[([^\]]+)\]", s)
        if sec_m:
            current = sec_m.group(1).strip()
            if current not in sections:
                sections[current] = {}
                section_order.append(current)
            continue
        if not current or "=" not in s:
            continue
        k, v = s.split("=", 1)
        sections[current][k.strip().lower()] = v.strip()

    install_defaults = set()
    for sec_name in section_order:
        if re.match(r"^install", sec_name, re.IGNORECASE):
            dval = sections[sec_name].get("default", "")
            if dval:
                install_defaults.add(dval)

    profiles = []
    seen_names = set()
    for sec_name in section_order:
        if not re.match(r"^profile\d*$", sec_name, re.IGNORECASE):
            continue
        sec = sections[sec_name]
        raw_name = re.sub(r"[\r\n\t]+", " ", str(sec.get("name", ""))).strip()[:64]
        raw_path = sec.get("path", "")
        if not raw_name or not _is_valid_profile_dir(raw_name) or raw_name.startswith("-"):
            continue
        is_rel = sec.get("isrelative", "1").strip() != "0"
        prof_path = _resolve_gecko_profile_path(base_dir, raw_path, is_rel)
        if not prof_path:
            continue
        low = raw_name.lower()
        if low in seen_names:
            continue
        seen_names.add(low)
        profiles.append({
            "dir": raw_name,
            "name": raw_name,
            "initial": (raw_name[0].upper() if raw_name else "?") or "?",
            "picturePath": "",
            "profile_path": prof_path,
            "raw_path": raw_path,
            "is_default": (raw_path in install_defaults) or (sec.get("default") == "1"),
        })

    if len(profiles) < 2:
        return None

    # Sort longer paths first for unambiguous prefix matching against open fd symlinks.
    by_path_desc = sorted(profiles, key=lambda p: len(p["profile_path"]), reverse=True)
    by_name = {p["name"]: p for p in profiles}
    by_name_lower = {p["name"].lower(): p for p in profiles}
    return {
        "base_dir": base_dir,
        "profiles": profiles,
        "by_path_desc": by_path_desc,
        "by_name": by_name,
        "by_name_lower": by_name_lower,
    }


def _resolve_gecko_pid_profile(ctx, pid, proc_root="/proc", pid_cache=None):
    if not isinstance(pid, int) or isinstance(pid, bool) or pid <= 0:
        return None, False
    if pid_cache is not None and pid in pid_cache:
        cached = pid_cache[pid]
        return cached, cached is not None

    matched = None
    proc_dir = os.path.join(proc_root, str(pid))

    cmdline_path = os.path.join(proc_dir, "cmdline")
    try:
        with open(cmdline_path, "rb") as handle:
            raw_args = handle.read().split(b"\x00")
        args = [a.decode("utf-8", errors="ignore") for a in raw_args if a]
    except OSError:
        args = []

    idx = 0
    while idx < len(args) and matched is None:
        arg = args[idx]
        prof_arg = None
        path_arg = None
        if arg in ("-P", "--profile-name") and idx + 1 < len(args):
            prof_arg = args[idx + 1]
            idx += 1
        elif arg.startswith("--profile-name="):
            prof_arg = arg.split("=", 1)[1]
        elif arg == "--profile" and idx + 1 < len(args):
            path_arg = args[idx + 1]
            idx += 1
        elif arg.startswith("--profile="):
            path_arg = arg.split("=", 1)[1]

        if prof_arg is not None:
            matched = ctx["by_name"].get(prof_arg) or ctx["by_name_lower"].get(prof_arg.lower())
        elif path_arg:
            real_arg = os.path.realpath(path_arg)
            for prof in ctx["by_path_desc"]:
                if real_arg == prof["profile_path"] or path_arg == prof["raw_path"]:
                    matched = prof
                    break
        idx += 1

    if matched is None:
        fd_dir = os.path.join(proc_dir, "fd")
        try:
            entries = os.listdir(fd_dir)[:512]
        except OSError:
            entries = []
        for entry in entries:
            link_path = os.path.join(fd_dir, entry)
            try:
                target = os.readlink(link_path)
            except OSError:
                continue
            target_real = os.path.realpath(target) if os.path.isabs(target) else target
            for prof in ctx["by_path_desc"]:
                pp = prof["profile_path"]
                if target_real == pp or target_real.startswith(pp + os.sep):
                    matched = prof
                    break
            if matched is not None:
                break

    if pid_cache is not None:
        pid_cache[pid] = matched
    return matched, matched is not None


def resolve_browser_window_profiles(windows, home_dir=None, proc_root="/proc"):
    """Map browser window addresses to profile metadata for multi-profile setups."""
    if not isinstance(windows, list):
        return {}
    home = os.path.expanduser(home_dir) if home_dir else os.path.expanduser("~")
    chromium_contexts = {}
    gecko_contexts = {}
    gecko_pid_cache = {}
    resolved = {}

    for win in windows:
        if not isinstance(win, dict):
            continue
        addr = _normalize_address(win.get("address"))
        if not addr:
            continue
        raw_app = str(win.get("appKey") or "").strip().lower()
        if raw_app.endswith(".desktop"):
            raw_app = raw_app[:-8]

        title = str(win.get("title") or "")
        initial_title = str(win.get("initialTitle") or "")
        if INCOGNITO_RE.search(title) or INCOGNITO_RE.search(initial_title):
            continue

        if raw_app in GECKO_BROWSER_SUBDIRS:
            subdirs = GECKO_BROWSER_SUBDIRS[raw_app]
            if subdirs not in gecko_contexts:
                gecko_contexts[subdirs] = _load_gecko_context(home, subdirs)
            gctx = gecko_contexts[subdirs]
            if gctx is None:
                continue
            raw_pid = win.get("pid")
            try:
                pid = int(raw_pid) if raw_pid is not None else 0
            except (TypeError, ValueError):
                pid = 0
            prof, confident = _resolve_gecko_pid_profile(gctx, pid, proc_root=proc_root, pid_cache=gecko_pid_cache)
            if prof is not None:
                resolved[addr] = _public_profile_payload(prof, confident)
            continue

        subdir = CHROMIUM_BROWSER_SUBDIRS.get(raw_app)
        if not subdir:
            continue

        if subdir not in chromium_contexts:
            chromium_contexts[subdir] = _load_chromium_context(os.path.join(home, subdir))
        ctx = chromium_contexts[subdir]
        if ctx is None:
            continue

        profiles = ctx["profiles"]
        best_prof = _match_chromium_title_profile(title, ctx) or _match_chromium_title_profile(initial_title, ctx)
        confident = best_prof is not None

        if best_prof is None:
            candidates = _browser_title_candidates(title, initial_title, ctx["name_map"])
            for cand in candidates:
                n16 = cand.encode("utf-16le", errors="ignore")
                n8 = cand.encode("utf-8", errors="ignore")
                hits = []
                for pdir, prof in profiles.items():
                    best_pos = -1
                    for blob in _profile_session_blobs(ctx, pdir):
                        pos = max(blob.rfind(n16) if n16 else -1, blob.rfind(n8) if n8 else -1)
                        if pos > best_pos:
                            best_pos = pos
                    if best_pos >= 0:
                        hits.append((pdir in ctx["active_set"], best_pos, prof["active_time"], pdir))
                if hits:
                    hits.sort(reverse=True)
                    best_prof = profiles[hits[0][3]]
                    confident = len(hits) == 1
                    break

        if best_prof is None and len(ctx["active_list"]) == 1:
            best_prof = profiles[ctx["active_list"][0]]
            confident = True

        if best_prof is None and win.get("activated") and ctx["last_used"]:
            best_prof = profiles[ctx["last_used"]]
            confident = False

        if best_prof is not None:
            resolved[addr] = _public_profile_payload(best_prof, confident)

    return resolved


def cmd_browser_window_profiles(args):
    if len(args) != 1:
        raise ValueError("Expected <windows_json> for browser-window-profiles")
    try:
        windows = json.loads(args[0])
    except ValueError as exc:
        raise ValueError(f"Invalid windows JSON: {exc}") from exc
    result = resolve_browser_window_profiles(windows)
    sys.stdout.write(json.dumps(result, separators=(",", ":")) + "\n")

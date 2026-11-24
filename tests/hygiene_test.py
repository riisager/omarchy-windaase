#!/usr/bin/env python3
"""Static hygiene and packaging checks for Omarchy-windase."""

import glob
import json
import os
import re
import shutil
import subprocess
import sys
import unittest

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if REPO_ROOT not in sys.path:
    sys.path.insert(0, REPO_ROOT)
REGEX_PREFIX_CHARS = set("(=,:?[!&|{;\n")


def strip_qml_comments_and_strings(src):
    """Return src with string contents and JS/QML comments blanked for structural checks."""
    out = []
    i = 0
    n = len(src)
    last_non_ws = "\n"

    while i < n:
        ch = src[i]

        if ch in ('"', "'"):
            quote = ch
            out.append(quote)
            i += 1
            while i < n:
                c = src[i]
                if c == "\\":
                    out.append("  ")
                    i += 2
                    continue
                if c == quote:
                    out.append(quote)
                    i += 1
                    break
                out.append("\n" if c == "\n" else " ")
                i += 1
            last_non_ws = quote
            continue

        if ch == "/" and i + 1 < n and src[i + 1] == "/":
            i += 2
            while i < n and src[i] != "\n":
                i += 1
            continue

        if ch == "/" and i + 1 < n and src[i + 1] == "*":
            i += 2
            while i + 1 < n and not (src[i] == "*" and src[i + 1] == "/"):
                if src[i] == "\n":
                    out.append("\n")
                i += 1
            i += 2
            continue

        if ch == "/" and last_non_ws in REGEX_PREFIX_CHARS:
            out.append("/")
            i += 1
            in_class = False
            while i < n:
                c = src[i]
                if c == "\n":
                    out.append("\n")
                    i += 1
                    break
                if c == "\\":
                    out.append("  ")
                    i += 2
                    continue
                if c == "[":
                    in_class = True
                elif c == "]" and in_class:
                    in_class = False
                elif c == "/" and not in_class:
                    out.append("/")
                    i += 1
                    break
                out.append(" ")
                i += 1
            last_non_ws = "/"
            continue

        out.append(ch)
        if not ch.isspace():
            last_non_ws = ch
        i += 1

    return "".join(out)


def iter_qml_text_blocks(cleaned_src):
    """Yield the body inside each `Text { ... }` block (tracking brace depth)."""
    pattern = re.compile(r"(?<![A-Za-z0-9_.])Text\s*\{")
    for match in pattern.finditer(cleaned_src):
        start = match.end()
        depth = 1
        pos = start
        n = len(cleaned_src)
        while pos < n and depth > 0:
            ch = cleaned_src[pos]
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
            pos += 1
        yield match.start(), cleaned_src[start : pos - 1]


def qml_files():
    paths = sorted(glob.glob(os.path.join(REPO_ROOT, "*.qml")))
    return paths


class HygieneTests(unittest.TestCase):
    def test_qml_text_blocks_use_plain_text(self):
        files = qml_files()
        self.assertGreater(len(files), 0)
        total_blocks = 0
        plain_re = re.compile(r"\btextFormat\s*:\s*Text\.PlainText\b")

        for path in files:
            with open(path, "r", encoding="utf-8") as handle:
                cleaned = strip_qml_comments_and_strings(handle.read())
            for offset, block in iter_qml_text_blocks(cleaned):
                total_blocks += 1
                line_no = cleaned[:offset].count("\n") + 1
                rel = os.path.relpath(path, REPO_ROOT)
                self.assertRegex(
                    block,
                    plain_re,
                    f"{rel}:{line_no}: Text element must set `textFormat: Text.PlainText`",
                )

        self.assertGreater(total_blocks, 0)

    def test_qml_animations_use_style_duration(self):
        files = qml_files()
        dur_re = re.compile(r"\bduration\s*:\s*([^\n;}]+)")
        total_durations = 0

        for path in files:
            with open(path, "r", encoding="utf-8") as handle:
                cleaned = strip_qml_comments_and_strings(handle.read())
            for match in dur_re.finditer(cleaned):
                total_durations += 1
                expr = match.group(1).strip()
                line_no = cleaned[: match.start()].count("\n") + 1
                rel = os.path.relpath(path, REPO_ROOT)
                self.assertTrue(
                    expr.startswith("Style.duration("),
                    f"{rel}:{line_no}: animation duration must use Style.duration(...), got `{expr}`",
                )

        self.assertGreater(total_durations, 0)

    def test_qml_has_no_infinite_loops(self):
        forbidden = (
            re.compile(r"\bAnimation\.Infinite\b"),
            re.compile(r"\bloops\s*:\s*-1\b"),
        )
        for path in qml_files():
            with open(path, "r", encoding="utf-8") as handle:
                cleaned = strip_qml_comments_and_strings(handle.read())
            rel = os.path.relpath(path, REPO_ROOT)
            for pattern in forbidden:
                self.assertNotRegex(cleaned, pattern, f"{rel}: infinite QML loop breaks 0% idle CPU invariant")

    def test_no_symlinks_in_repo(self):
        for root, dirs, files in os.walk(REPO_ROOT, followlinks=False):
            dirs[:] = [d for d in dirs if d not in (".git", "__pycache__")]
            for name in dirs + files:
                full_path = os.path.join(root, name)
                self.assertFalse(
                    os.path.islink(full_path),
                    f"Repository must not contain symlinks: {os.path.relpath(full_path, REPO_ROOT)}",
                )

    def test_manifest_and_layouts_valid(self):
        manifest_path = os.path.join(REPO_ROOT, "manifest.json")
        with open(manifest_path, "r", encoding="utf-8") as handle:
            manifest = json.load(handle)

        self.assertEqual(manifest.get("schemaVersion"), 1)
        self.assertEqual(manifest.get("id"), "riisager.windaase")
        entry_points = manifest.get("entryPoints") or {}
        self.assertGreater(len(entry_points), 0)
        for role, rel_target in entry_points.items():
            self.assertIsInstance(rel_target, str)
            self.assertTrue(
                os.path.isfile(os.path.join(REPO_ROOT, rel_target)),
                f"manifest.json entryPoint '{role}' missing: {rel_target}",
            )

        layouts_path = os.path.join(REPO_ROOT, "layouts.json")
        with open(layouts_path, "r", encoding="utf-8") as handle:
            layouts = json.load(handle)

        cards = layouts.get("layouts")
        self.assertIsInstance(cards, list)
        self.assertGreater(len(cards), 0)

        ultrawide = layouts.get("ultrawideLayout")
        self.assertIsInstance(ultrawide, list)
        self.assertGreater(len(ultrawide), 0)

        all_zones = [zone for card in cards for zone in card] + list(ultrawide)
        for idx, zone in enumerate(all_zones):
            self.assertIsInstance(zone, dict, f"Zone {idx} must be an object")
            for key in ("rx", "ry", "rw", "rh"):
                val = zone.get(key)
                self.assertIsInstance(val, (int, float))
                self.assertNotIsInstance(val, bool)
            self.assertTrue(0 <= zone["rx"] < 1, f"Zone {idx} rx out of range: {zone['rx']}")
            self.assertTrue(0 <= zone["ry"] < 1, f"Zone {idx} ry out of range: {zone['ry']}")
            self.assertTrue(0 < zone["rw"] <= 1, f"Zone {idx} rw out of range: {zone['rw']}")
            self.assertTrue(0 < zone["rh"] <= 1, f"Zone {idx} rh out of range: {zone['rh']}")

    def test_install_sh_stages_all_plugin_files(self):
        install_path = os.path.join(REPO_ROOT, "install.sh")
        with open(install_path, "r", encoding="utf-8") as handle:
            install_src = handle.read()

        match = re.search(
            r"STAGING_DIR=.*?omarchy plugin validate \"\$\{STAGING_DIR\}\"",
            install_src,
            flags=re.DOTALL,
        )
        self.assertIsNotNone(match, "Could not locate staging block in install.sh")
        staging_block = match.group(0)

        expected_files = [os.path.basename(p) for p in qml_files()] + [
            "TaskbarModel.js",
            "manifest.json",
            "layouts.json",
            "windaase-config.py",
            "LICENSE",
            "README.md",
            "nautilus/windaase_context_menu.py",
        ]
        for rel_file in expected_files:
            self.assertIn(
                rel_file,
                staging_block,
                f"install.sh staging block must copy {rel_file}",
            )

        self.assertIn("${SCRIPT_DIR}/js/\"*.js", staging_block, "install.sh must stage js/*.js")
        self.assertIn("${SCRIPT_DIR}/configlib/\"*.py", staging_block, "install.sh must stage configlib/*.py")
        self.assertGreater(len(glob.glob(os.path.join(REPO_ROOT, "js", "*.js"))), 0)
        self.assertGreater(len(glob.glob(os.path.join(REPO_ROOT, "configlib", "*.py"))), 0)

    def test_qml_avoids_raw_array_isarray(self):
        pattern = re.compile(r"\bArray\.isArray\s*\(")
        for path in qml_files():
            with open(path, "r", encoding="utf-8") as handle:
                cleaned = strip_qml_comments_and_strings(handle.read())
            rel = os.path.relpath(path, REPO_ROOT)
            self.assertNotRegex(
                cleaned,
                pattern,
                f"{rel}: use isArrayLike(...) instead of Array.isArray(...) for Qt6 QVariantList safety",
            )

    def test_hypr_option_keys_and_defaults_synced(self):
        from configlib.common import HYPR_OPTION_KEYS as PY_KEYS

        with open(os.path.join(REPO_ROOT, "hypr", "windaase.lua"), "r", encoding="utf-8") as handle:
            lua_src = handle.read()
        m_defaults = re.search(r"local\s+DEFAULTS\s*=\s*\{(.*?)\}", lua_src, flags=re.DOTALL)
        self.assertIsNotNone(m_defaults)
        lua_bool_defaults = {
            k: (v == "true")
            for k, v in re.findall(r"([a-z0-9_]+)\s*=\s*(true|false)", m_defaults.group(1))
        }

        js_info = json.loads(
            subprocess.check_output(
                [
                    "node",
                    "-e",
                    (
                        "const TM = require('./TaskbarModel.js');"
                        "console.log(JSON.stringify({"
                        "keys: TM.HYPR_OPTION_KEYS,"
                        "defaults: TM.defaultHyprSettings(),"
                        "toggles: TM.HYPR_SETTINGS_TOGGLES"
                        "}));"
                    ),
                ],
                cwd=REPO_ROOT,
                text=True,
            )
        )
        with open(os.path.join(REPO_ROOT, "i18n", "en.json"), "r", encoding="utf-8") as handle:
            en_catalog = json.load(handle)

        py_set = set(PY_KEYS)
        js_set = set(js_info["keys"])
        toggle_keys = [t["key"] for t in js_info["toggles"]]

        self.assertEqual(py_set, set(lua_bool_defaults.keys()))
        self.assertEqual(py_set, js_set)
        self.assertEqual(js_info["defaults"], lua_bool_defaults)
        self.assertEqual(set(toggle_keys), py_set)
        self.assertEqual(len(toggle_keys), len(set(toggle_keys)))
        for t in js_info["toggles"]:
            self.assertIn(t["labelKey"], en_catalog)

    def test_browser_catalog_synced_between_js_and_python(self):
        from configlib.browsers import CHROMIUM_BROWSER_SUBDIRS, GECKO_BROWSER_SUBDIRS

        with open(os.path.join(REPO_ROOT, "js", "BrowserProfiles.js"), "r", encoding="utf-8") as handle:
            js_src = handle.read()
        m_chrom = re.search(r"var\s+chromiumMap\s*=\s*\{(.*?)\n  \}", js_src, flags=re.DOTALL)
        m_gecko = re.search(r"var\s+geckoMap\s*=\s*\{(.*?)\n  \}", js_src, flags=re.DOTALL)
        self.assertIsNotNone(m_chrom)
        self.assertIsNotNone(m_gecko)

        js_chromium = set(re.findall(r'"([^"]+)"\s*:\s*\{', m_chrom.group(1)))
        js_gecko = set(re.findall(r'"([^"]+)"\s*:\s*\{', m_gecko.group(1)))

        self.assertEqual(js_chromium, set(CHROMIUM_BROWSER_SUBDIRS.keys()))
        self.assertEqual(js_gecko, set(GECKO_BROWSER_SUBDIRS.keys()))

    def test_layouts_fallbacks_match_layouts_json(self):
        with open(os.path.join(REPO_ROOT, "layouts.json"), "r", encoding="utf-8") as handle:
            canonical = json.load(handle)

        js_fallback = json.loads(
            subprocess.check_output(
                [
                    "node",
                    "-e",
                    "const SL = require('./js/SnapLayoutMath.js'); console.log(JSON.stringify(SL.DEFAULT_LAYOUTS_CONFIG));",
                ],
                cwd=REPO_ROOT,
                text=True,
            )
        )
        self.assertEqual(js_fallback, canonical)

        lua_bin = shutil.which("lua") or shutil.which("lua5.4")
        self.assertIsNotNone(lua_bin)
        lua_script = (
            "package.path = './?.lua;' .. package.path;"
            "local g = require('hypr.windaase.geometry');"
            "local cfg = g.resolve_layouts_config(nil, true);"
            "print(cfg.cardW .. ',' .. cfg.cardH .. ',' .. cfg.cardGap .. ',' .. cfg.padX .. ',' .. cfg.padY .. ',' .. cfg.topMargin .. ',' .. #cfg.layouts);"
            "for _, card in ipairs(cfg.layouts) do "
            "  local parts = {};"
            "  for _, z in ipairs(card) do "
            "    parts[#parts+1] = string.format('%.5f:%.5f:%.5f:%.5f:%s', z.rx, z.ry, z.rw, z.rh, tostring(z.max == true));"
            "  end;"
            "  print(table.concat(parts, '|'));"
            "end"
        )
        lua_lines = subprocess.check_output([lua_bin, "-e", lua_script], cwd=REPO_ROOT, text=True).strip().splitlines()
        meta = [int(x) for x in lua_lines[0].split(",")]
        expected_cards = list(canonical["layouts"]) + [canonical["ultrawideLayout"]]
        self.assertEqual(
            meta,
            [
                canonical["cardW"],
                canonical["cardH"],
                canonical["cardGap"],
                canonical["padX"],
                canonical["padY"],
                canonical["topMargin"],
                len(expected_cards),
            ],
        )
        for idx, card in enumerate(expected_cards):
            zones = lua_lines[idx + 1].split("|")
            self.assertEqual(len(zones), len(card))
            for z_raw, z_exp in zip(zones, card):
                rx, ry, rw, rh, mx = z_raw.split(":")
                self.assertAlmostEqual(float(rx), float(z_exp["rx"]), places=4)
                self.assertAlmostEqual(float(ry), float(z_exp["ry"]), places=4)
                self.assertAlmostEqual(float(rw), float(z_exp["rw"]), places=4)
                self.assertAlmostEqual(float(rh), float(z_exp["rh"]), places=4)
                self.assertEqual(mx == "true", bool(z_exp["max"]))

    def test_minimize_tag_prefixes_synced_between_js_and_lua(self):
        js_prefixes = json.loads(
            subprocess.check_output(
                [
                    "node",
                    "-e",
                    "const WA = require('./js/WindowActions.js'); console.log(JSON.stringify(WA.MINIMIZE_TAG_PREFIXES));",
                ],
                cwd=REPO_ROOT,
                text=True,
            )
        )
        with open(os.path.join(REPO_ROOT, "hypr", "windaase", "show_desktop.lua"), "r", encoding="utf-8") as handle:
            lua_src = handle.read()
        for prefix in js_prefixes:
            escaped_lua = prefix.replace("-", "%-")
            self.assertIn(escaped_lua, lua_src, f"show_desktop.lua missing tag pattern for {prefix}")


if __name__ == "__main__":
    unittest.main(verbosity=2)

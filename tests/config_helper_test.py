#!/usr/bin/env python3
"""Unit tests for windaase-config.py in an isolated temporary HOME."""

import glob
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SCRIPT_PATH = os.path.join(REPO_ROOT, "windaase-config.py")
INSTALL_SH = os.path.join(REPO_ROOT, "install.sh")
UNINSTALL_SH = os.path.join(REPO_ROOT, "uninstall.sh")


class ConfigHelperTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = self.tmp.name
        self.omarchy_dir = os.path.join(self.home, ".config", "omarchy")
        os.makedirs(self.omarchy_dir, exist_ok=True)
        self.env = os.environ.copy()
        self.env["HOME"] = self.home

    def tearDown(self):
        self.tmp.cleanup()

    def run_helper(self, *args):
        return subprocess.run(
            [sys.executable, SCRIPT_PATH, *args],
            env=self.env,
            capture_output=True,
            text=True,
            check=False,
        )

    def read_text(self, path):
        with open(path, "r", encoding="utf-8") as handle:
            return handle.read()

    def read_json(self, path):
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)

    def test_bar_height_create_and_update_preserves_other_sections(self):
        res = self.run_helper("bar-height", "40")
        self.assertEqual(res.returncode, 0, res.stderr)
        toml_path = os.path.join(self.omarchy_dir, "shell.toml")
        self.assertEqual(self.read_text(toml_path), "[bar]\nsize-horizontal = 40\n")

        with open(toml_path, "w", encoding="utf-8") as handle:
            handle.write("[font]\nbase-size = 14\n\n[bar]\n# comment\nsize-horizontal = 26\n")
        res = self.run_helper("bar-height", "46")
        self.assertEqual(res.returncode, 0, res.stderr)
        content = self.read_text(toml_path)
        self.assertIn("[font]\nbase-size = 14\n", content)
        self.assertIn("size-horizontal = 46\n", content)
        self.assertIn("# comment\n", content)

    def test_bar_height_rejects_out_of_range(self):
        for bad in ("20", "70", "abc", "-5"):
            res = self.run_helper("bar-height", bad)
            self.assertNotEqual(res.returncode, 0)

    def test_two_line_clock_toggle_preserves_other_clock_fields(self):
        shell_json = os.path.join(self.omarchy_dir, "shell.json")
        initial = {
            "bar": {
                "position": "bottom",
                "layout": {
                    "right": [
                        {
                            "id": "omarchy.clock",
                            "format": "dddd HH:mm",
                            "formatAlt": "d MMMM 'W'ww yyyy",
                            "verticalFormat": "HH\n—\nmm",
                        }
                    ]
                },
            }
        }
        with open(shell_json, "w", encoding="utf-8") as handle:
            json.dump(initial, handle)

        res = self.run_helper("two-line-clock", "on")
        self.assertEqual(res.returncode, 0, res.stderr)
        loaded = self.read_json(shell_json)
        clock = loaded["bar"]["layout"]["right"][0]
        self.assertEqual(clock["format"], "HH:mm\ndd-MM-yyyy")
        self.assertEqual(clock["formatAlt"], "d MMMM 'W'ww yyyy")
        self.assertEqual(clock["verticalFormat"], "HH\n—\nmm")

        res = self.run_helper("two-line-clock", "off")
        self.assertEqual(res.returncode, 0, res.stderr)
        loaded = self.read_json(shell_json)
        self.assertEqual(loaded["bar"]["layout"]["right"][0]["format"], "dddd HH:mm")

    def test_hypr_set_and_validation(self):
        res = self.run_helper("hypr-set", "hover_scroll", "false", "--no-reload")
        self.assertEqual(res.returncode, 0, res.stderr)
        res = self.run_helper("hypr-set", "auto_raise", "true", "--no-reload")
        self.assertEqual(res.returncode, 0, res.stderr)
        res = self.run_helper("hypr-set", "snap_assist", "false", "--no-reload")
        self.assertEqual(res.returncode, 0, res.stderr)
        res = self.run_helper("hypr-set", "snap_resize", "false", "--no-reload")
        self.assertEqual(res.returncode, 0, res.stderr)
        res = self.run_helper("hypr-set", "ultrawide_layout", "true", "--no-reload")
        self.assertEqual(res.returncode, 0, res.stderr)

        cfg_path = os.path.join(self.omarchy_dir, "windaase.json")
        loaded = self.read_json(cfg_path)
        self.assertEqual(
            loaded,
            {
                "hover_scroll": False,
                "auto_raise": True,
                "snap_assist": False,
                "snap_resize": False,
                "ultrawide_layout": True,
            },
        )

        self.assertNotEqual(self.run_helper("hypr-set", "evil_key", "false", "--no-reload").returncode, 0)
        self.assertNotEqual(self.run_helper("hypr-set", "hover_scroll", "yes", "--no-reload").returncode, 0)

    def test_bar_height_reset_preserves_other_sections_or_deletes_empty_file(self):
        toml_path = os.path.join(self.omarchy_dir, "shell.toml")
        self.assertEqual(self.run_helper("bar-height", "40").returncode, 0)
        self.assertEqual(self.run_helper("bar-height-reset").returncode, 0)
        self.assertFalse(os.path.exists(toml_path))

        with open(toml_path, "w", encoding="utf-8") as handle:
            handle.write("[font]\nbase-size = 14\n\n[bar]\nsize-horizontal = 40\n")
        res = self.run_helper("bar-height-reset")
        self.assertEqual(res.returncode, 0, res.stderr)
        content = self.read_text(toml_path)
        self.assertIn("[font]\nbase-size = 14\n", content)
        self.assertNotIn("size-horizontal", content)
        self.assertNotIn("[bar]", content)

    def _luac_ok(self, content):
        luac = shutil.which("luac")
        if not luac:
            return
        res = subprocess.run([luac, "-p", "-"], input=content, text=True, capture_output=True, check=False)
        self.assertEqual(res.returncode, 0, f"Invalid Lua output:\n{res.stderr}\n---\n{content}")

    def test_strip_hyprland_loader_single_and_multiline_setup(self):
        lua_path = os.path.join(self.home, "hyprland.lua")

        # 1. Single-line setup() with banner comment
        single = (
            'o.bind("SUPER + Return", "Terminal", { term = "foot" })\n\n'
            "-- Omarchy-windåse\n"
            'require("hypr.windaase").setup()\n'
        )
        with open(lua_path, "w", encoding="utf-8") as handle:
            handle.write(single)
        res = self.run_helper("strip-hyprland-loader", lua_path)
        self.assertEqual(res.returncode, 0, res.stderr)
        cleaned = self.read_text(lua_path)
        self.assertEqual(cleaned, 'o.bind("SUPER + Return", "Terminal", { term = "foot" })\n')
        self._luac_ok(cleaned)

        # 2. Exact documented multiline setup({...}) with nested tables, strings & comments with ) / }
        multiline = (
            'o.bind("SUPER + Q", "Close", hl.dsp.window.close())\n\n'
            "-- Omarchy-windåse\n"
            'require("hypr.windaase").setup({\n'
            "  aero_snap = true,     -- handle ) and } inside comments\n"
            "  snap_layouts = true,  -- Top-edge drag & Super + Z\n"
            "  soft_maximize = true,\n"
            "  auto_raise = true,\n"
            "  hover_scroll = true,\n"
            '  shortcuts = true,     -- string ) test: "})" }\n'
            "  gap_out = 8,\n"
            "  gap_in = 8,\n"
            '  extra = { nested = { label = "ok ) }" } },\n'
            "})\n\n"
            'o.bind("SUPER + W", "Workspace", "test")\n'
        )
        with open(lua_path, "w", encoding="utf-8") as handle:
            handle.write(multiline)
        res = self.run_helper("strip-hyprland-loader", lua_path)
        self.assertEqual(res.returncode, 0, res.stderr)
        cleaned = self.read_text(lua_path)
        self._luac_ok(cleaned)
        self.assertNotIn("hypr.windaase", cleaned)
        self.assertNotIn("aero_snap", cleaned)
        self.assertNotIn("-- Omarchy-windåse", cleaned)
        self.assertIn('o.bind("SUPER + Q"', cleaned)
        self.assertIn('o.bind("SUPER + W"', cleaned)

    def test_strip_hyprland_loader_table_call_local_var_and_comments(self):
        lua_path = os.path.join(self.home, "hyprland.lua")
        source = (
            '-- Keep commented reference: require("hypr.windaase").setup()\n'
            "local keep = 42\n"
            "-- Omarchy-windåse\n"
            'require("hypr.windaase").setup { hover_scroll = false }\n'
            'local w = require("hypr.windaase")\n'
            "w.setup({\n"
            "  shortcuts = false,\n"
            "})\n"
        )
        with open(lua_path, "w", encoding="utf-8") as handle:
            handle.write(source)
        res = self.run_helper("strip-hyprland-loader", lua_path)
        self.assertEqual(res.returncode, 0, res.stderr)
        cleaned = self.read_text(lua_path)
        self._luac_ok(cleaned)
        self.assertIn('-- Keep commented reference: require("hypr.windaase").setup()', cleaned)
        self.assertIn("local keep = 42", cleaned)
        self.assertNotIn("hover_scroll", cleaned)
        self.assertNotIn("shortcuts", cleaned)

    def test_strip_hyprland_loader_refuses_unsafe_expressions(self):
        lua_path = os.path.join(self.home, "hyprland.lua")
        cases = [
            'if require("hypr.windaase") then\n  print("ok")\nend\n',
            'local w = require("hypr.windaase")\no.bind("SUPER + D", "Desktop", w.show_desktop)\n',
            'pcall(require, "hypr.windaase")\n',
        ]
        for body in cases:
            with open(lua_path, "w", encoding="utf-8") as handle:
                handle.write(body)
            res = self.run_helper("strip-hyprland-loader", lua_path)
            self.assertNotEqual(res.returncode, 0, f"Expected refusal for:\n{body}")
            self.assertEqual(self.read_text(lua_path), body)

    def _make_stub_bin(self):
        stub_dir = os.path.join(self.home, "stub-bin")
        os.makedirs(stub_dir, exist_ok=True)

        stubs = {
            "omarchy": (
                "#!/bin/bash\n"
                'if [[ "${1:-} ${2:-}" == "plugin validate" ]]; then\n'
                '  [[ -f "${3:-}/manifest.json" ]] || exit 1\n'
                "fi\n"
                "exit 0\n"
            ),
            "omarchy-shell": "#!/bin/bash\nexit 0\n",
            "hyprctl": "#!/bin/bash\nexit 0\n",
            "omarchy-hyprland-workspace-layout-default": (
                "#!/bin/bash\n"
                'modes_dir="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/workspace-layouts"\n'
                'mkdir -p "$modes_dir"\n'
                'for f in "$modes_dir"/[0-9]*.lua; do\n'
                '  [[ -f "$f" ]] || continue\n'
                '  rm -f "$f"\n'
                "done\n"
                'printf \'o.workspace_mode({ default = "%s" })\\n\' "${1:-floating}" > "$modes_dir/default.lua"\n'
            ),
        }
        for name, content in stubs.items():
            path = os.path.join(stub_dir, name)
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(content)
            os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)
        return stub_dir

    def test_uninstall_sh_cleanly_removes_multiline_setup(self):
        stub_dir = self._make_stub_bin()
        hypr_dir = os.path.join(self.home, ".config", "hypr")
        os.makedirs(hypr_dir, exist_ok=True)
        hyprland_lua = os.path.join(hypr_dir, "hyprland.lua")
        with open(hyprland_lua, "w", encoding="utf-8") as handle:
            handle.write(
                "-- Existing user config\n"
                'o.bind("SUPER + Return", "Term", { term = "foot" })\n\n'
                "-- Omarchy-windåse\n"
                'require("hypr.windaase").setup({\n'
                "  aero_snap = true,\n"
                "  snap_layouts = true,\n"
                "  gap_out = 8,\n"
                "  gap_in = 8,\n"
                "})\n"
            )

        env = self.env.copy()
        env["PATH"] = f"{stub_dir}:{env['PATH']}"
        env["XDG_STATE_HOME"] = os.path.join(self.home, ".local", "state")

        res = subprocess.run(["bash", UNINSTALL_SH], env=env, capture_output=True, text=True, check=False)
        self.assertEqual(res.returncode, 0, res.stderr + res.stdout)

        cleaned = self.read_text(hyprland_lua)
        self._luac_ok(cleaned)
        self.assertNotIn("hypr.windaase", cleaned)
        self.assertNotIn("aero_snap", cleaned)
        self.assertIn('o.bind("SUPER + Return"', cleaned)
        backups = glob.glob(f"{hyprland_lua}.bak-uninstall-*")
        self.assertEqual(len(backups), 1)

    def test_install_full_backs_up_and_preserves_workspace_layout_overrides(self):
        stub_dir = self._make_stub_bin()
        hypr_dir = os.path.join(self.home, ".config", "hypr")
        state_home = os.path.join(self.home, ".local", "state")
        layouts_dir = os.path.join(state_home, "omarchy", "workspace-layouts")
        os.makedirs(hypr_dir, exist_ok=True)
        os.makedirs(layouts_dir, exist_ok=True)

        with open(os.path.join(hypr_dir, "hyprland.lua"), "w", encoding="utf-8") as handle:
            handle.write("-- Clean start\n")
        with open(os.path.join(self.omarchy_dir, "shell.json"), "w", encoding="utf-8") as handle:
            handle.write('{"bar":{"position":"top"}}\n')
        with open(os.path.join(layouts_dir, "default.lua"), "w", encoding="utf-8") as handle:
            handle.write('o.workspace_mode({ default = "dwindle" })\n')
        with open(os.path.join(layouts_dir, "3.lua"), "w", encoding="utf-8") as handle:
            handle.write('o.workspace_mode({ workspace = "3", mode = "scrolling" })\n')

        env = self.env.copy()
        env["PATH"] = f"{stub_dir}:{env['PATH']}"
        env["XDG_STATE_HOME"] = state_home

        res = subprocess.run(["bash", INSTALL_SH, "--full"], env=env, capture_output=True, text=True, check=False)
        self.assertEqual(res.returncode, 0, res.stderr + res.stdout)

        layout_backups = glob.glob(os.path.join(state_home, "omarchy", "workspace-layouts.bak-*"))
        self.assertEqual(len(layout_backups), 1)
        self.assertTrue(os.path.exists(os.path.join(layout_backups[0], "default.lua")))
        self.assertTrue(os.path.exists(os.path.join(layout_backups[0], "3.lua")))

        shell_backups = glob.glob(os.path.join(self.omarchy_dir, "shell.json.bak-*"))
        self.assertEqual(len(shell_backups), 1)

        self.assertEqual(
            self.read_text(os.path.join(layouts_dir, "default.lua")),
            'o.workspace_mode({ default = "floating" })\n',
        )
        self.assertEqual(
            self.read_text(os.path.join(layouts_dir, "3.lua")),
            'o.workspace_mode({ workspace = "3", mode = "scrolling" })\n',
        )

    def test_strip_hyprland_loader_refuses_submodule_and_handles_crlf(self):
        lua_path = os.path.join(self.home, "hyprland.lua")

        submod = 'local snap = require("hypr.windaase.snap")\nsnap.apply_snap(nil, "left")\n'
        with open(lua_path, "w", encoding="utf-8") as handle:
            handle.write(submod)
        res = self.run_helper("strip-hyprland-loader", lua_path)
        self.assertNotEqual(res.returncode, 0)
        self.assertEqual(self.read_text(lua_path), submod)

        crlf = (
            'o.bind("SUPER + Return", "Term", { term = "foot" })\r\n\r\n'
            "-- Omarchy-windåse\r\n"
            'require("hypr.windaase").setup({\r\n'
            '  note = "line\\\r\ncontinued",\r\n'
            "  hover_scroll = true,\r\n"
            "})\r\n"
        )
        with open(lua_path, "wb") as handle:
            handle.write(crlf.encode("utf-8"))
        res = self.run_helper("strip-hyprland-loader", lua_path)
        self.assertEqual(res.returncode, 0, res.stderr)
        with open(lua_path, "rb") as handle:
            cleaned = handle.read().decode("utf-8")
        self._luac_ok(cleaned)
        self.assertEqual(cleaned, 'o.bind("SUPER + Return", "Term", { term = "foot" })\r\n')

    def _setup_fake_install_state(self, hyprland_content, installed_helper_body=None):
        stub_dir = self._make_stub_bin()
        hypr_dir = os.path.join(self.home, ".config", "hypr")
        plugin_dir = os.path.join(self.home, ".config", "omarchy", "plugins", "riisager.windaase")
        lua_sub_dir = os.path.join(hypr_dir, "windaase")
        lua_entry = os.path.join(hypr_dir, "windaase.lua")
        windaase_json = os.path.join(self.omarchy_dir, "windaase.json")
        hyprland_lua = os.path.join(hypr_dir, "hyprland.lua")
        state_home = os.path.join(self.home, ".local", "state")

        os.makedirs(plugin_dir, exist_ok=True)
        os.makedirs(lua_sub_dir, exist_ok=True)
        with open(hyprland_lua, "w", encoding="utf-8") as handle:
            handle.write(hyprland_content)
        with open(lua_entry, "w", encoding="utf-8") as handle:
            handle.write("-- module\nreturn {}\n")
        with open(os.path.join(lua_sub_dir, "snap.lua"), "w", encoding="utf-8") as handle:
            handle.write("return {}\n")
        with open(windaase_json, "w", encoding="utf-8") as handle:
            handle.write('{"hover_scroll":true}\n')
        if installed_helper_body is not None:
            with open(os.path.join(plugin_dir, "windaase-config.py"), "w", encoding="utf-8") as handle:
                handle.write(installed_helper_body)

        env = self.env.copy()
        env["PATH"] = f"{stub_dir}:{env['PATH']}"
        env["XDG_STATE_HOME"] = state_home
        return {
            "env": env,
            "hyprland_lua": hyprland_lua,
            "lua_entry": lua_entry,
            "lua_sub_dir": lua_sub_dir,
            "plugin_dir": plugin_dir,
            "windaase_json": windaase_json,
        }

    def test_uninstall_sh_prefers_script_dir_helper_over_older_installed_helper(self):
        original = (
            'o.bind("SUPER + Return", "Term", { term = "foot" })\n\n'
            "-- Omarchy-windåse\n"
            'require("hypr.windaase").setup({\n'
            "  aero_snap = true,\n"
            "  gap_out = 8,\n"
            "})\n"
        )
        old_helper = '#!/usr/bin/env python3\nimport sys\nsys.stderr.write("Unknown subcommand\\n")\nsys.exit(1)\n'
        st = self._setup_fake_install_state(original, installed_helper_body=old_helper)

        res = subprocess.run(["bash", UNINSTALL_SH], env=st["env"], capture_output=True, text=True, check=False)
        self.assertEqual(res.returncode, 0, res.stderr + res.stdout)

        cleaned = self.read_text(st["hyprland_lua"])
        self._luac_ok(cleaned)
        self.assertNotIn("hypr.windaase", cleaned)
        self.assertFalse(os.path.exists(st["lua_entry"]))
        self.assertFalse(os.path.exists(st["lua_sub_dir"]))
        self.assertFalse(os.path.exists(st["plugin_dir"]))
        self.assertFalse(os.path.exists(st["windaase_json"]))

    def test_uninstall_sh_keeps_lua_module_when_older_fallback_helper_fails(self):
        original = (
            "-- Omarchy-windåse\n"
            'require("hypr.windaase").setup({\n'
            "  aero_snap = true,\n"
            "})\n"
        )
        old_helper = '#!/usr/bin/env python3\nimport sys\nsys.stderr.write("Unknown subcommand\\n")\nsys.exit(1)\n'
        st = self._setup_fake_install_state(original, installed_helper_body=old_helper)

        toml_path = os.path.join(self.omarchy_dir, "shell.toml")
        with open(toml_path, "w", encoding="utf-8") as handle:
            handle.write("[bar]\nsize-horizontal = 40\n")

        isolated_dir = os.path.join(self.home, "alone")
        os.makedirs(isolated_dir, exist_ok=True)
        solo_uninstall = os.path.join(isolated_dir, "uninstall.sh")
        shutil.copy2(UNINSTALL_SH, solo_uninstall)

        res = subprocess.run(
            ["bash", solo_uninstall, "--restore-stock"],
            env=st["env"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("left", res.stderr)
        self.assertEqual(self.read_text(st["hyprland_lua"]), original)
        self.assertTrue(os.path.exists(st["lua_entry"]))
        self.assertTrue(os.path.exists(st["lua_sub_dir"]))
        self.assertTrue(os.path.exists(st["plugin_dir"]))
        self.assertTrue(os.path.exists(st["windaase_json"]))
        self.assertEqual(self.read_text(toml_path), "[bar]\nsize-horizontal = 40\n")
        self.assertEqual(glob.glob(f"{st['hyprland_lua']}.bak-uninstall-*"), [])

    def test_uninstall_sh_keeps_lua_module_when_strip_fails_on_custom_wrapper(self):
        custom = 'if require("hypr.windaase") then\n  print("x")\nend\n'
        st = self._setup_fake_install_state(custom)

        res = subprocess.run(["bash", UNINSTALL_SH], env=st["env"], capture_output=True, text=True, check=False)
        self.assertNotEqual(res.returncode, 0)
        self.assertEqual(self.read_text(st["hyprland_lua"]), custom)
        self.assertTrue(os.path.exists(st["lua_entry"]))
        self.assertTrue(os.path.exists(st["lua_sub_dir"]))
        self.assertTrue(os.path.exists(st["plugin_dir"]))
        self.assertEqual(glob.glob(f"{st['hyprland_lua']}.bak-uninstall-*"), [])

    def test_uninstall_sh_keeps_lua_module_when_helper_missing(self):
        original = 'require("hypr.windaase").setup()\n'
        st = self._setup_fake_install_state(original, installed_helper_body=None)

        isolated_dir = os.path.join(self.home, "alone-missing")
        os.makedirs(isolated_dir, exist_ok=True)
        solo_uninstall = os.path.join(isolated_dir, "uninstall.sh")
        shutil.copy2(UNINSTALL_SH, solo_uninstall)

        res = subprocess.run(["bash", solo_uninstall], env=st["env"], capture_output=True, text=True, check=False)
        self.assertNotEqual(res.returncode, 0)
        self.assertEqual(self.read_text(st["hyprland_lua"]), original)
        self.assertTrue(os.path.exists(st["lua_entry"]))
        self.assertTrue(os.path.exists(st["lua_sub_dir"]))
        self.assertTrue(os.path.exists(st["plugin_dir"]))

    def test_uninstall_sh_handles_commented_out_require_cleanly(self):
        commented = '-- require("hypr.windaase").setup()\no.bind("SUPER + Q", "Close", "x")\n'
        st = self._setup_fake_install_state(commented)

        res = subprocess.run(["bash", UNINSTALL_SH], env=st["env"], capture_output=True, text=True, check=False)
        self.assertEqual(res.returncode, 0, res.stderr + res.stdout)
        self.assertEqual(self.read_text(st["hyprland_lua"]), commented)
        self.assertEqual(glob.glob(f"{st['hyprland_lua']}.bak-uninstall-*"), [])
        self.assertFalse(os.path.exists(st["lua_entry"]))
        self.assertFalse(os.path.exists(st["lua_sub_dir"]))
        self.assertFalse(os.path.exists(st["plugin_dir"]))

    def test_install_sh_in_place_from_plugin_dir_preserves_git_and_installs_hypr(self):
        stub_dir = self._make_stub_bin()
        hypr_dir = os.path.join(self.home, ".config", "hypr")
        plugin_dir = os.path.join(self.home, ".config", "omarchy", "plugins", "riisager.windaase")
        os.makedirs(hypr_dir, exist_ok=True)
        os.makedirs(os.path.dirname(plugin_dir), exist_ok=True)

        shutil.copytree(REPO_ROOT, plugin_dir, ignore=shutil.ignore_patterns(".git", "docs"))
        git_dir = os.path.join(plugin_dir, ".git")
        os.makedirs(git_dir, exist_ok=True)
        with open(os.path.join(git_dir, "HEAD"), "w", encoding="utf-8") as handle:
            handle.write("ref: refs/heads/main\n")

        hyprland_lua = os.path.join(hypr_dir, "hyprland.lua")
        with open(hyprland_lua, "w", encoding="utf-8") as handle:
            handle.write("-- Existing user config\n")

        env = self.env.copy()
        env["PATH"] = f"{stub_dir}:{env['PATH']}"
        env["XDG_STATE_HOME"] = os.path.join(self.home, ".local", "state")

        res = subprocess.run(
            ["bash", os.path.join(plugin_dir, "install.sh")],
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(res.returncode, 0, res.stderr + res.stdout)

        # In-place install must preserve git checkout and companion sources inside PLUGIN_DEST
        self.assertEqual(self.read_text(os.path.join(git_dir, "HEAD")), "ref: refs/heads/main\n")
        self.assertTrue(os.path.exists(os.path.join(plugin_dir, "install.sh")))
        self.assertTrue(os.path.exists(os.path.join(plugin_dir, "hypr", "windaase.lua")))
        self.assertTrue(os.path.exists(os.path.join(plugin_dir, "SnapAssistCard.qml")))
        self.assertTrue(os.path.exists(os.path.join(plugin_dir, "ProfileAvatar.qml")))

        # Hyprland companion must be installed and wired into hyprland.lua
        self.assertTrue(os.path.exists(os.path.join(hypr_dir, "windaase.lua")))
        self.assertTrue(os.path.exists(os.path.join(hypr_dir, "windaase", "snap.lua")))
        self.assertTrue(os.path.exists(os.path.join(hypr_dir, "windaase", "snap_resize.lua")))
        self.assertTrue(os.path.exists(os.path.join(hypr_dir, "windaase", "layouts.json")))
        lua_content = self.read_text(hyprland_lua)
        self.assertIn('require("hypr.windaase").setup()', lua_content)
        self._luac_ok(lua_content)

    def test_browser_window_profiles_resolution(self):
        chrome_dir = os.path.join(self.home, ".config", "google-chrome")
        os.makedirs(os.path.join(chrome_dir, "Default", "Sessions"), exist_ok=True)
        os.makedirs(os.path.join(chrome_dir, "Profile 1", "Sessions"), exist_ok=True)

        pic_default = os.path.join(chrome_dir, "Default", "Google Profile Picture.png")
        with open(pic_default, "wb") as handle:
            handle.write(b"png")

        with open(os.path.join(chrome_dir, "Default", "Sessions", "Session_100"), "wb") as handle:
            handle.write(b"hdr" + "Inbox - Personal".encode("utf-16le") + b"tail")
        with open(os.path.join(chrome_dir, "Profile 1", "Sessions", "Session_200"), "wb") as handle:
            handle.write(b"hdr" + "Admin Dashboard".encode("utf-16le") + b"tail")

        local_state = {
            "profile": {
                "last_used": "Default",
                "last_active_profiles": ["Default", "Profile 1"],
                "info_cache": {
                    "Default": {
                        "name": "Personal",
                        "gaia_picture_file_name": "Google Profile Picture.png",
                        "active_time": 200.0,
                    },
                    "Profile 1": {
                        "name": "Work",
                        "gaia_picture_file_name": "../escaped.png",
                        "active_time": 100.0,
                    },
                    "../evil": {
                        "name": "Evil",
                        "active_time": 999.0,
                    },
                    "Guest Profile": {
                        "name": "Guest",
                    },
                },
            }
        }
        with open(os.path.join(chrome_dir, "Local State"), "w", encoding="utf-8") as handle:
            json.dump(local_state, handle)

        # Brave with only 1 profile must be skipped completely
        brave_dir = os.path.join(self.home, ".config", "BraveSoftware", "Brave-Browser")
        os.makedirs(brave_dir, exist_ok=True)
        with open(os.path.join(brave_dir, "Local State"), "w", encoding="utf-8") as handle:
            json.dump({"profile": {"info_cache": {"Default": {"name": "Only"}}}}, handle)

        # Chromium with 2 configured profiles but only 1 active profile
        chromium_dir = os.path.join(self.home, ".config", "chromium")
        os.makedirs(chromium_dir, exist_ok=True)
        with open(os.path.join(chromium_dir, "Local State"), "w", encoding="utf-8") as handle:
            json.dump(
                {
                    "profile": {
                        "last_used": "Default",
                        "last_active_profiles": ["Default"],
                        "info_cache": {
                            "Default": {"name": "Main", "active_time": 10.0},
                            "Profile 1": {"name": "Alt", "active_time": 5.0},
                        },
                    }
                },
                handle,
            )

        payload = [
            {"address": "0xAAA1", "appKey": "google-chrome", "title": "(3) Inbox - Personal – Google Chrome", "initialTitle": "", "activated": False},
            {"address": "0xAAA2", "appKey": "google-chrome", "title": "Admin Dashboard – Google Chrome", "initialTitle": "", "activated": False},
            {"address": "0xAAA3", "appKey": "google-chrome", "title": "Admin Dashboard (Incognito) – Google Chrome", "initialTitle": "", "activated": True},
            {"address": "0xAAA4", "appKey": "google-chrome", "title": "Ny fane – Google Chrome", "initialTitle": "", "activated": False},
            {"address": "0xAAA5", "appKey": "google-chrome", "title": "Ny fane – Google Chrome", "initialTitle": "", "activated": True},
            {"address": "0xBBB1", "appKey": "chromium", "title": "Waiting tab – Chromium", "initialTitle": "", "activated": False},
            {"address": "0xBBB2", "appKey": "chromium", "title": "Private (Guest) – Chromium", "initialTitle": "", "activated": True},
            {"address": "0xCCC1", "appKey": "brave-browser", "title": "Docs – Brave", "initialTitle": "", "activated": True},
        ]

        res = self.run_helper("browser-window-profiles", json.dumps(payload))
        self.assertEqual(res.returncode, 0, res.stderr)
        out = json.loads(res.stdout)

        self.assertEqual(out["0xaaa1"]["dir"], "Default")
        self.assertEqual(out["0xaaa1"]["name"], "Personal")
        self.assertEqual(out["0xaaa1"]["picturePath"], pic_default)
        self.assertTrue(out["0xaaa1"]["confident"])

        # Path traversal in gaia_picture_file_name must resolve to empty string
        self.assertEqual(out["0xaaa2"]["dir"], "Profile 1")
        self.assertEqual(out["0xaaa2"]["picturePath"], "")
        self.assertTrue(out["0xaaa2"]["confident"])

        # Incognito skipped; unfocused generic Ny fane skipped; focused Ny fane gets fallback
        self.assertNotIn("0xaaa3", out)
        self.assertNotIn("0xaaa4", out)
        self.assertEqual(out["0xaaa5"]["dir"], "Default")
        self.assertFalse(out["0xaaa5"]["confident"])

        # Chromium single active profile fallback succeeds (and Guest window skipped)
        self.assertEqual(out["0xbbb1"]["dir"], "Default")
        self.assertEqual(out["0xbbb1"]["name"], "Main")
        self.assertTrue(out["0xbbb1"]["confident"])
        self.assertNotIn("0xbbb2", out)

        # Single-profile Brave is skipped
        self.assertNotIn("0xccc1", out)

    def test_vivaldi_edge_firefox_and_zen_window_profiles(self):
        import importlib.util

        spec = importlib.util.spec_from_file_location("windaase_config", SCRIPT_PATH)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)

        # Vivaldi (2 profiles, session match)
        vivaldi_dir = os.path.join(self.home, ".config", "vivaldi")
        os.makedirs(os.path.join(vivaldi_dir, "Default", "Sessions"), exist_ok=True)
        os.makedirs(os.path.join(vivaldi_dir, "Profile 1", "Sessions"), exist_ok=True)
        with open(os.path.join(vivaldi_dir, "Default", "Sessions", "Session_1"), "wb") as h:
            h.write(b"v" + "Home Feed".encode("utf-16le"))
        with open(os.path.join(vivaldi_dir, "Profile 1", "Sessions", "Session_2"), "wb") as h:
            h.write(b"v" + "Sprint Board".encode("utf-16le"))
        with open(os.path.join(vivaldi_dir, "Local State"), "w", encoding="utf-8") as h:
            json.dump(
                {
                    "profile": {
                        "last_used": "Default",
                        "last_active_profiles": ["Default", "Profile 1"],
                        "info_cache": {
                            "Default": {"name": "Home", "active_time": 20.0},
                            "Profile 1": {"name": "Office", "active_time": 10.0},
                        },
                    }
                },
                h,
            )

        # Microsoft Edge (2 profiles, Edge Profile Picture.png fallback + title segment + InPrivate)
        edge_dir = os.path.join(self.home, ".config", "microsoft-edge")
        os.makedirs(os.path.join(edge_dir, "Default", "Sessions"), exist_ok=True)
        os.makedirs(os.path.join(edge_dir, "Profile 1", "Sessions"), exist_ok=True)
        edge_pic = os.path.join(edge_dir, "Profile 1", "Edge Profile Picture.png")
        with open(edge_pic, "wb") as h:
            h.write(b"png")
        with open(os.path.join(edge_dir, "Local State"), "w", encoding="utf-8") as h:
            json.dump(
                {
                    "profile": {
                        "last_used": "Default",
                        "last_active_profiles": ["Default", "Profile 1"],
                        "info_cache": {
                            "Default": {"name": "Personal", "active_time": 10.0},
                            "Profile 1": {"name": "Work", "active_time": 30.0},
                        },
                    }
                },
                h,
            )

        # Firefox (~/.mozilla/firefox/profiles.ini + fake /proc cmdline & fd symlinks)
        ff_dir = os.path.join(self.home, ".mozilla", "firefox")
        ff_p1 = os.path.join(ff_dir, "aaa111.default")
        ff_p2 = os.path.join(ff_dir, "bbb222.work")
        os.makedirs(ff_p1, exist_ok=True)
        os.makedirs(ff_p2, exist_ok=True)
        with open(os.path.join(ff_dir, "profiles.ini"), "w", encoding="utf-8") as h:
            h.write(
                "[Install123]\n"
                "Default=aaa111.default\n\n"
                "[Profile0]\n"
                "Name=default-release\n"
                "IsRelative=1\n"
                "Path=aaa111.default\n\n"
                "[Profile1]\n"
                "Name=Work\n"
                "IsRelative=1\n"
                "Path=bbb222.work\n\n"
                "[Profile2]\n"
                "Name=BadTraversal\n"
                "IsRelative=1\n"
                "Path=../../etc\n"
            )

        # Zen Browser (~/.zen/profiles.ini)
        zen_dir = os.path.join(self.home, ".zen")
        zen_p1 = os.path.join(zen_dir, "111.main")
        zen_p2 = os.path.join(zen_dir, "222.dev")
        os.makedirs(zen_p1, exist_ok=True)
        os.makedirs(zen_p2, exist_ok=True)
        with open(os.path.join(zen_dir, "profiles.ini"), "w", encoding="utf-8") as h:
            h.write(
                "[Profile0]\n"
                "Name=Main\n"
                "IsRelative=1\n"
                "Path=111.main\n"
                "Default=1\n\n"
                "[Profile1]\n"
                "Name=Dev\n"
                "IsRelative=1\n"
                "Path=222.dev\n"
            )

        proc_root = os.path.join(self.home, "fakeproc")
        # pid 1001: Firefox launched with -P Work
        os.makedirs(os.path.join(proc_root, "1001", "fd"), exist_ok=True)
        with open(os.path.join(proc_root, "1001", "cmdline"), "wb") as h:
            h.write(b"firefox\x00-P\x00Work\x00")
        # pid 1002: Firefox default instance detected via fd symlink
        os.makedirs(os.path.join(proc_root, "1002", "fd"), exist_ok=True)
        with open(os.path.join(proc_root, "1002", "cmdline"), "wb") as h:
            h.write(b"firefox\x00")
        os.symlink(os.path.join(ff_p1, "places.sqlite"), os.path.join(proc_root, "1002", "fd", "7"))
        # pid 2001: Zen launched with --profile <zen_p2>
        os.makedirs(os.path.join(proc_root, "2001", "fd"), exist_ok=True)
        with open(os.path.join(proc_root, "2001", "cmdline"), "wb") as h:
            h.write(b"zen-browser\x00--profile=" + zen_p2.encode("utf-8") + b"\x00")

        payload = [
            {"address": "0x1111", "appKey": "vivaldi-stable", "title": "Sprint Board - Vivaldi", "initialTitle": "", "activated": False},
            {"address": "0x2221", "appKey": "microsoft-edge", "title": "Docs and 3 more pages - Work - Microsoft\u200b Edge", "initialTitle": "", "activated": False},
            {"address": "0x2222", "appKey": "microsoft-edge", "title": "New tab - InPrivate - Microsoft\u200b Edge", "initialTitle": "", "activated": True},
            {"address": "0x3331", "appKey": "firefox", "pid": 1001, "title": "PR Review — Mozilla Firefox", "initialTitle": "", "activated": False},
            {"address": "0x3332", "appKey": "firefox", "pid": 1002, "title": "News — Mozilla Firefox", "initialTitle": "", "activated": True},
            {"address": "0x3333", "appKey": "firefox", "pid": 1001, "title": "Docs — Mozilla Firefox Private Browsing", "initialTitle": "", "activated": True},
            {"address": "0x4441", "appKey": "zen-browser", "pid": 2001, "title": "Repo — Zen Browser", "initialTitle": "", "activated": True},
        ]

        out = mod.resolve_browser_window_profiles(payload, home_dir=self.home, proc_root=proc_root)
        self.assertEqual(out["0x1111"]["dir"], "Profile 1")
        self.assertEqual(out["0x1111"]["name"], "Office")
        self.assertTrue(out["0x1111"]["confident"])

        self.assertEqual(out["0x2221"]["dir"], "Profile 1")
        self.assertEqual(out["0x2221"]["name"], "Work")
        self.assertEqual(out["0x2221"]["picturePath"], edge_pic)
        self.assertTrue(out["0x2221"]["confident"])
        self.assertNotIn("0x2222", out)

        self.assertEqual(out["0x3331"]["name"], "Work")
        self.assertEqual(out["0x3331"]["initial"], "W")
        self.assertTrue(out["0x3331"]["confident"])
        self.assertEqual(out["0x3332"]["name"], "default-release")
        self.assertTrue(out["0x3332"]["confident"])
        self.assertNotIn("0x3333", out)

        self.assertEqual(out["0x4441"]["name"], "Dev")
        self.assertTrue(out["0x4441"]["confident"])

    def _run_install_with_mv_wrapper(self, fail_rollback=False):
        stub_dir = self._make_stub_bin()
        real_mv = shutil.which("mv")
        self.assertTrue(real_mv, "Expected mv binary in PATH")

        plugin_dest = os.path.join(self.omarchy_dir, "plugins", "riisager.windaase")
        os.makedirs(plugin_dest, exist_ok=True)
        with open(os.path.join(plugin_dest, "manifest.json"), "w", encoding="utf-8") as handle:
            handle.write('{"id":"riisager.windaase"}\n')
        marker = os.path.join(plugin_dest, "custom-local-note.txt")
        with open(marker, "w", encoding="utf-8") as handle:
            handle.write("keep-me\n")

        mv_wrapper = os.path.join(stub_dir, "mv")
        rollback_block = (
            'if [[ "${fail_rollback}" == "1" && "${src}" == *.old.* && "${dst}" == */riisager.windaase ]]; then\n'
            '  exit 1\n'
            'fi\n'
        )
        with open(mv_wrapper, "w", encoding="utf-8") as handle:
            handle.write(
                "#!/bin/bash\n"
                'src="${1:-}"\n'
                'dst="${2:-}"\n'
                f'fail_rollback="{1 if fail_rollback else 0}"\n'
                'if [[ "${src}" == *.staging.* && "${dst}" == */riisager.windaase ]]; then\n'
                '  exit 1\n'
                'fi\n'
                + rollback_block
                + f'exec "{real_mv}" "$@"\n'
            )
        os.chmod(mv_wrapper, os.stat(mv_wrapper).st_mode | stat.S_IXUSR)

        env = self.env.copy()
        env["PATH"] = f"{stub_dir}:{env['PATH']}"
        res = subprocess.run(
            ["bash", INSTALL_SH, "--shell-only"],
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )
        return res, plugin_dest, marker

    def test_install_sh_restores_previous_plugin_when_staged_swap_fails(self):
        res, plugin_dest, marker = self._run_install_with_mv_wrapper(fail_rollback=False)
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("restored previous plugin", res.stderr)
        self.assertTrue(os.path.exists(marker))
        self.assertEqual(self.read_text(marker), "keep-me\n")
        self.assertEqual(glob.glob(f"{plugin_dest}.staging.*"), [])
        self.assertEqual(glob.glob(f"{plugin_dest}.old.*"), [])

    def test_install_sh_preserves_recovery_dir_when_rollback_also_fails(self):
        res, plugin_dest, marker = self._run_install_with_mv_wrapper(fail_rollback=True)
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("previous plugin preserved at", res.stderr)
        self.assertFalse(os.path.exists(marker))
        self.assertEqual(glob.glob(f"{plugin_dest}.staging.*"), [])
        preserved_dirs = glob.glob(f"{plugin_dest}.old.*")
        self.assertEqual(len(preserved_dirs), 1)
        preserved_marker = os.path.join(preserved_dirs[0], "custom-local-note.txt")
        self.assertTrue(os.path.exists(preserved_marker))
        self.assertEqual(self.read_text(preserved_marker), "keep-me\n")

    def test_nautilus_menu_enable_disable_status_and_pycache_cleanup(self):
        ext_path = os.path.join(
            self.home, ".local", "share", "nautilus-python", "extensions", "windaase_context_menu.py"
        )
        pycache_dir = os.path.join(os.path.dirname(ext_path), "__pycache__")

        res = self.run_helper("nautilus-menu", "status")
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(res.stdout.strip(), "not-installed")

        res = self.run_helper("nautilus-menu", "on")
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertTrue(os.path.isfile(ext_path))
        self.assertFalse(os.path.islink(ext_path))
        self.assertEqual(stat.S_IMODE(os.stat(ext_path).st_mode), 0o644)
        self.assertIn("# Managed by Omarchy-windåse (riisager.windaase)", self.read_text(ext_path))

        res = self.run_helper("nautilus-menu", "status")
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(res.stdout.strip(), "installed")

        os.makedirs(pycache_dir, exist_ok=True)
        pyc_file = os.path.join(pycache_dir, "windaase_context_menu.cpython-313.pyc")
        unrelated_pyc = os.path.join(pycache_dir, "localsend.cpython-313.pyc")
        with open(pyc_file, "wb") as handle:
            handle.write(b"pyc")
        with open(unrelated_pyc, "wb") as handle:
            handle.write(b"keep")

        res = self.run_helper("nautilus-menu", "off")
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertFalse(os.path.lexists(ext_path))
        self.assertFalse(os.path.exists(pyc_file))
        self.assertTrue(os.path.exists(unrelated_pyc))

        res = self.run_helper("nautilus-menu", "status")
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertEqual(res.stdout.strip(), "not-installed")

    def test_nautilus_menu_refuses_unmanaged_file_and_symlink(self):
        ext_dir = os.path.join(self.home, ".local", "share", "nautilus-python", "extensions")
        os.makedirs(ext_dir, exist_ok=True)
        ext_path = os.path.join(ext_dir, "windaase_context_menu.py")

        # Unmanaged regular file must not be overwritten or deleted.
        with open(ext_path, "w", encoding="utf-8") as handle:
            handle.write("# custom user extension\n")
        for action in ("on", "off"):
            res = self.run_helper("nautilus-menu", action)
            self.assertNotEqual(res.returncode, 0)
            self.assertEqual(self.read_text(ext_path), "# custom user extension\n")
        res = self.run_helper("nautilus-menu", "status")
        self.assertEqual(res.stdout.strip(), "not-installed")
        os.unlink(ext_path)

        # Symlink (even dangling) must not be followed, overwritten, or deleted.
        target = os.path.join(self.home, "outside-target.py")
        os.symlink(target, ext_path)
        for action in ("on", "off"):
            res = self.run_helper("nautilus-menu", action)
            self.assertNotEqual(res.returncode, 0)
            self.assertTrue(os.path.islink(ext_path))
            self.assertFalse(os.path.exists(target))
        res = self.run_helper("nautilus-menu", "status")
        self.assertEqual(res.stdout.strip(), "not-installed")

    def test_install_stages_nautilus_without_auto_enable_and_refreshes_when_enabled(self):
        stub_dir = self._make_stub_bin()
        env = self.env.copy()
        env["PATH"] = f"{stub_dir}:{env['PATH']}"

        plugin_dest = os.path.join(self.omarchy_dir, "plugins", "riisager.windaase")
        ext_dir = os.path.join(self.home, ".local", "share", "nautilus-python", "extensions")
        ext_path = os.path.join(ext_dir, "windaase_context_menu.py")

        # Fresh install stages nautilus/windaase_context_menu.py without enabling it.
        res = subprocess.run(["bash", INSTALL_SH, "--shell-only"], env=env, capture_output=True, text=True, check=False)
        self.assertEqual(res.returncode, 0, res.stderr + res.stdout)
        staged_ext = os.path.join(plugin_dest, "nautilus", "windaase_context_menu.py")
        self.assertTrue(os.path.isfile(staged_ext))
        self.assertFalse(os.path.lexists(ext_path))

        # When already opt-in enabled with outdated managed content, install refreshes it.
        os.makedirs(ext_dir, exist_ok=True)
        with open(ext_path, "w", encoding="utf-8") as handle:
            handle.write("# Managed by Omarchy-windåse (riisager.windaase)\n# stale version\n")

        res = subprocess.run(["bash", INSTALL_SH, "--shell-only"], env=env, capture_output=True, text=True, check=False)
        self.assertEqual(res.returncode, 0, res.stderr + res.stdout)
        self.assertEqual(self.read_text(ext_path), self.read_text(staged_ext))

    def test_uninstall_removes_nautilus_ext_but_keeps_localsend(self):
        stub_dir = self._make_stub_bin()
        env = self.env.copy()
        env["PATH"] = f"{stub_dir}:{env['PATH']}"

        res = subprocess.run(["bash", INSTALL_SH, "--shell-only"], env=env, capture_output=True, text=True, check=False)
        self.assertEqual(res.returncode, 0, res.stderr + res.stdout)

        res = self.run_helper("nautilus-menu", "on")
        self.assertEqual(res.returncode, 0, res.stderr)

        ext_dir = os.path.join(self.home, ".local", "share", "nautilus-python", "extensions")
        windaase_ext = os.path.join(ext_dir, "windaase_context_menu.py")
        localsend_ext = os.path.join(ext_dir, "localsend.py")
        with open(localsend_ext, "w", encoding="utf-8") as handle:
            handle.write("# keep localsend\n")

        res = subprocess.run(["bash", UNINSTALL_SH], env=env, capture_output=True, text=True, check=False)
        self.assertEqual(res.returncode, 0, res.stderr + res.stdout)
        self.assertFalse(os.path.lexists(windaase_ext))
        self.assertTrue(os.path.isfile(localsend_ext))
        self.assertEqual(self.read_text(localsend_ext), "# keep localsend\n")

    def test_nautilus_context_menu_pure_helpers(self):
        import importlib.util

        nautilus_py = os.path.join(REPO_ROOT, "nautilus", "windaase_context_menu.py")
        spec = importlib.util.spec_from_file_location("windaase_context_menu", nautilus_py)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)

        # format_paths_payload
        self.assertEqual(
            mod.format_paths_payload(["/a/one.txt", "", "   ", "/a/one.txt", "/b/two.txt"]),
            "/a/one.txt\n/b/two.txt",
        )
        self.assertEqual(mod.format_paths_payload([]), "")

        # build_terminal_command
        stub_map = {
            "uwsm-app": "/usr/bin/uwsm-app",
            "xdg-terminal-exec": "/usr/bin/xdg-terminal-exec",
            "omarchy-launch-editor": "/usr/share/omarchy/bin/omarchy-launch-editor",
        }
        self.assertEqual(
            mod.build_terminal_command("/tmp/my folder", which_fn=stub_map.get),
            ["/usr/bin/uwsm-app", "--", "/usr/bin/xdg-terminal-exec", "--dir=/tmp/my folder"],
        )
        no_uwsm = {"xdg-terminal-exec": "/usr/bin/xdg-terminal-exec"}
        self.assertEqual(
            mod.build_terminal_command("/tmp/dir", which_fn=no_uwsm.get),
            ["/usr/bin/xdg-terminal-exec", "--dir=/tmp/dir"],
        )
        self.assertIsNone(mod.build_terminal_command("/tmp/dir", which_fn={}.get))

        # build_editor_command
        self.assertEqual(
            mod.build_editor_command(["/a.txt", "", "/b.txt"], which_fn=stub_map.get),
            ["/usr/share/omarchy/bin/omarchy-launch-editor", "/a.txt", "/b.txt"],
        )
        self.assertIsNone(mod.build_editor_command(["/a.txt"], which_fn={}.get))
        self.assertIsNone(mod.build_editor_command([], which_fn=stub_map.get))

        # create_new_text_file uniqueness and symlink/overwrite safety
        work_dir = os.path.join(self.home, "folder")
        os.makedirs(work_dir, exist_ok=True)
        first = mod.create_new_text_file(work_dir)
        self.assertEqual(first, os.path.join(work_dir, "Untitled.txt"))
        with open(first, "w", encoding="utf-8") as handle:
            handle.write("do-not-clobber")

        # Dangling symlink at Untitled 2.txt must also not be followed or overwritten.
        dangling = os.path.join(work_dir, "Untitled 2.txt")
        escaped_target = os.path.join(self.home, "should-not-exist.txt")
        os.symlink(escaped_target, dangling)

        second = mod.create_new_text_file(work_dir)
        self.assertEqual(second, os.path.join(work_dir, "Untitled 3.txt"))
        self.assertEqual(self.read_text(first), "do-not-clobber")
        self.assertFalse(os.path.exists(escaped_target))
        self.assertIsNone(mod.create_new_text_file(os.path.join(work_dir, "missing")))

        # load_labels locale resolution + traversal rejection
        plugin_i18n = os.path.join(self.omarchy_dir, "plugins", "riisager.windaase", "i18n")
        os.makedirs(plugin_i18n, exist_ok=True)
        shutil.copy2(os.path.join(REPO_ROOT, "i18n", "da.json"), os.path.join(plugin_i18n, "da.json"))
        shutil.copy2(os.path.join(REPO_ROOT, "i18n", "pt-BR.json"), os.path.join(plugin_i18n, "pt-BR.json"))

        with open(os.path.join(self.omarchy_dir, "language"), "w", encoding="utf-8") as handle:
            handle.write("pt-BR\n")
        pt_labels = mod.load_labels(home_dir=self.home)
        self.assertEqual(pt_labels["nautilus.copyPath"], "Copiar como caminho")

        # Traversal attempt falls back safely to defaults
        with open(os.path.join(self.omarchy_dir, "language"), "w", encoding="utf-8") as handle:
            handle.write("../../../etc/passwd\n")
        fallback_labels = mod.load_labels(home_dir=self.home, lang_env="")
        self.assertEqual(fallback_labels["nautilus.copyPath"], "Copy as path")

        # Missing language file falls back to lang_env (e.g. da_DK.UTF-8 -> da)
        os.unlink(os.path.join(self.omarchy_dir, "language"))
        da_labels = mod.load_labels(home_dir=self.home, lang_env="da_DK.UTF-8")
        self.assertEqual(da_labels["nautilus.copyPath"], "Kopiér som sti")
        self.assertEqual(da_labels["nautilus.newTextDocument"], "Nyt tekstdokument")


if __name__ == "__main__":
    unittest.main(verbosity=2)

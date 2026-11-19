#!/usr/bin/env python3
"""Unit tests for windaase-config.py in an isolated temporary HOME."""

import json
import os
import subprocess
import sys
import tempfile
import unittest

SCRIPT_PATH = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "windaase-config.py")
)


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

        cfg_path = os.path.join(self.omarchy_dir, "windaase.json")
        loaded = self.read_json(cfg_path)
        self.assertEqual(loaded, {"hover_scroll": False, "auto_raise": True})

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


if __name__ == "__main__":
    unittest.main(verbosity=2)

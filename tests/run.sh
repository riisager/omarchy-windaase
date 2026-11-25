#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

LUA_BIN="${LUA_BIN:-$(command -v lua || command -v lua5.4 || true)}"
LUAC_BIN="${LUAC_BIN:-$(command -v luac || command -v luac5.4 || true)}"

if [[ -z "$LUA_BIN" || -z "$LUAC_BIN" ]]; then
  echo "Error: lua and luac (5.4) are required to run the test suite." >&2
  exit 1
fi

echo "==> Checking Python and JS syntax"
python3 -m py_compile windaase-config.py configlib/*.py nautilus/windaase_context_menu.py
node --check TaskbarModel.js js/*.js

echo "==> Checking Lua syntax ($LUAC_BIN)"
"$LUAC_BIN" -p hypr/windaase.lua hypr/windaase/*.lua

echo "==> Running Lua geometry & module tests ($LUA_BIN)"
"$LUA_BIN" tests/geometry_test.lua
"$LUA_BIN" tests/modules_test.lua

echo "==> Running JS taskbar model & 50-locale i18n tests"
node tests/taskbar_model.test.js

echo "==> Running Python config helper tests"
python3 tests/config_helper_test.py

echo "==> Running Omarchy hygiene & packaging tests"
python3 tests/hygiene_test.py

echo "==> Checking shell script syntax"
bash -n install.sh uninstall.sh tests/run.sh

if command -v shellcheck >/dev/null 2>&1; then
  echo "==> Running shellcheck"
  shellcheck -S warning install.sh uninstall.sh tests/run.sh
fi

if command -v omarchy >/dev/null 2>&1; then
  echo "==> Validating plugin manifest & bundle"
  omarchy plugin validate .
fi

echo "==> All checks passed."

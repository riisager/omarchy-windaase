#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="riisager.windaase"
PLUGIN_DEST="${HOME}/.config/omarchy/plugins/${PLUGIN_ID}"
HYPR_DIR="${HOME}/.config/hypr"
HYPRLAND_LUA="${HYPR_DIR}/hyprland.lua"

RESTORE_STOCK=0
for arg in "$@"; do
  case "$arg" in
    --restore-stock) RESTORE_STOCK=1 ;;
    -h|--help)
      cat <<USAGE
Usage: ./uninstall.sh [--restore-stock]

Removes the Omarchy-windåse plugin and Hyprland Lua module.
Pass --restore-stock to also re-enable omarchy.dock, reset [bar] size-horizontal, and move the bar back to top.
USAGE
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

CONFIG_HELPER="${PLUGIN_DEST}/windaase-config.py"
if [[ ! -f "${CONFIG_HELPER}" && -f "${SCRIPT_DIR}/windaase-config.py" ]]; then
  CONFIG_HELPER="${SCRIPT_DIR}/windaase-config.py"
fi

if [[ "$RESTORE_STOCK" -eq 1 ]] && [[ -f "${CONFIG_HELPER}" ]]; then
  python3 "${CONFIG_HELPER}" bar-height-reset || true
fi

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin disable "${PLUGIN_ID}" >/dev/null 2>&1 || true
fi

rm -rf "${PLUGIN_DEST}" "${HYPR_DIR}/windaase.lua" "${HYPR_DIR}/windaase"
rm -f "${HOME}/.config/omarchy/windaase.json"

if [[ -f "${HYPRLAND_LUA}" ]] && grep -qE 'Omarchy-windåse|require\(["'\'']hypr\.windaase["'\'']\)' "${HYPRLAND_LUA}"; then
  BACKUP="${HYPRLAND_LUA}.bak-uninstall-$(date +%Y%m%d-%H%M%S)"
  cp "${HYPRLAND_LUA}" "${BACKUP}"
  python3 - "${HYPRLAND_LUA}" <<'PY'
import re, sys
p = sys.argv[1]
txt = open(p, "r", encoding="utf-8").read()
txt = re.sub(r'\n?--\s*Omarchy-windåse\n?', '\n', txt)
txt = re.sub(r'^.*require\(["\']hypr\.windaase["\']\).*\n?', '', txt, flags=re.M)
open(p, "w", encoding="utf-8").write(txt.rstrip() + "\n")
PY
  echo "==> Removed hypr.windaase from ${HYPRLAND_LUA} (backup: ${BACKUP})"
fi

if [[ "$RESTORE_STOCK" -eq 1 ]] && command -v omarchy >/dev/null 2>&1; then
  omarchy plugin enable omarchy.dock >/dev/null 2>&1 || true
  omarchy bar position top >/dev/null 2>&1 || true
fi

if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell -q shell rescanPlugins || true
fi

if command -v hyprctl >/dev/null 2>&1; then
  hyprctl reload >/dev/null || true
fi

echo "==> Omarchy-windåse uninstalled."

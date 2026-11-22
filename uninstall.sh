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

CONFIG_HELPER="${SCRIPT_DIR}/windaase-config.py"
if [[ ! -f "${CONFIG_HELPER}" ]]; then
  if [[ -f "${PLUGIN_DEST}/windaase-config.py" ]]; then
    CONFIG_HELPER="${PLUGIN_DEST}/windaase-config.py"
  else
    CONFIG_HELPER=""
  fi
fi

if [[ -f "${HYPRLAND_LUA}" ]] && grep -qE 'Omarchy-windåse|Omarchy-windaase|hypr[./]windaase' "${HYPRLAND_LUA}"; then
  if [[ -z "${CONFIG_HELPER}" ]]; then
    echo "Error: windaase-config.py not found; leaving ${HYPRLAND_LUA} and ${HYPR_DIR}/windaase* intact so Hyprland stays valid. Please remove hypr.windaase manually and re-run uninstall.sh." >&2
    exit 1
  fi

  BACKUP="${HYPRLAND_LUA}.bak-uninstall-$(date +%Y%m%d-%H%M%S)-$$"
  cp "${HYPRLAND_LUA}" "${BACKUP}"
  if python3 "${CONFIG_HELPER}" strip-hyprland-loader "${HYPRLAND_LUA}"; then
    if cmp -s "${HYPRLAND_LUA}" "${BACKUP}"; then
      rm -f "${BACKUP}"
    else
      echo "==> Removed hypr.windaase from ${HYPRLAND_LUA} (backup: ${BACKUP})"
    fi
  else
    cp "${BACKUP}" "${HYPRLAND_LUA}"
    rm -f "${BACKUP}"
    echo "Error: could not safely strip hypr.windaase from ${HYPRLAND_LUA}; restored backup and left ${HYPR_DIR}/windaase* intact so Hyprland stays valid. Please remove it manually and re-run uninstall.sh." >&2
    exit 1
  fi
fi

if [[ "$RESTORE_STOCK" -eq 1 ]] && [[ -n "${CONFIG_HELPER}" ]]; then
  python3 "${CONFIG_HELPER}" bar-height-reset || true
fi

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin disable "${PLUGIN_ID}" >/dev/null 2>&1 || true
fi

if [[ -n "${CONFIG_HELPER}" ]]; then
  python3 "${CONFIG_HELPER}" nautilus-menu off >/dev/null 2>&1 || true
else
  NAUTILUS_EXT="${HOME}/.local/share/nautilus-python/extensions/windaase_context_menu.py"
  if [[ -f "${NAUTILUS_EXT}" && ! -L "${NAUTILUS_EXT}" ]] && grep -qF "# Managed by Omarchy-windåse (riisager.windaase)" "${NAUTILUS_EXT}"; then
    rm -f "${NAUTILUS_EXT}"
    for pyc in "${HOME}/.local/share/nautilus-python/extensions/__pycache__/windaase_context_menu"*.pyc; do
      [[ -f "${pyc}" && ! -L "${pyc}" ]] || continue
      rm -f "${pyc}"
    done
  fi
fi

rm -rf "${PLUGIN_DEST}" "${HYPR_DIR}/windaase.lua" "${HYPR_DIR}/windaase"
rm -f "${HOME}/.config/omarchy/windaase.json" "${HOME}/.config/omarchy/.windaase.lock"

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

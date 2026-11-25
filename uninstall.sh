#!/bin/bash
set -euo pipefail

{
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
Pass --restore-stock to also re-enable omarchy.dock, reset [bar] size-horizontal, reset two-line clock, restore dwindle workspace default, and move the bar back to top.
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

  # Step 1: Fail-closed Hyprland loader removal before mutating other state.
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

  # Step 2: Flush live omarchy-shell mutations before disk fallbacks run.
  if command -v omarchy >/dev/null 2>&1; then
    omarchy plugin disable "${PLUGIN_ID}" >/dev/null 2>&1 || true
    if [[ "$RESTORE_STOCK" -eq 1 ]]; then
      omarchy plugin enable omarchy.dock >/dev/null 2>&1 || true
      omarchy bar position top >/dev/null 2>&1 || true
    fi
  fi

  # Step 3: Run CONFIG_HELPER cleanups before deleting ${PLUGIN_DEST} and lock files.
  if [[ "$RESTORE_STOCK" -eq 1 ]] && [[ -n "${CONFIG_HELPER}" ]]; then
    python3 "${CONFIG_HELPER}" bar-height-reset || true
    python3 "${CONFIG_HELPER}" strip-monitors-block || true
    rm -f "${HOME}/.config/omarchy/windaase-monitors.json"
    if command -v omarchy-hyprland-workspace-layout-default >/dev/null 2>&1 && omarchy-hyprland-workspace-layout-default dwindle >/dev/null 2>&1; then
      :
    else
      python3 "${CONFIG_HELPER}" reset-floating-default || true
    fi
  fi

  if [[ -n "${CONFIG_HELPER}" ]]; then
    CLEANUP_ARGS=()
    if [[ "$RESTORE_STOCK" -eq 1 ]]; then
      CLEANUP_ARGS+=(--restore-stock)
    fi
    SHELL_CLEAN_STATUS="$(python3 "${CONFIG_HELPER}" uninstall-shell-cleanup "${CLEANUP_ARGS[@]}" 2>/dev/null || true)"
    if [[ "${SHELL_CLEAN_STATUS}" == "updated" ]] && command -v omarchy-shell >/dev/null 2>&1; then
      omarchy-shell -q shell reloadConfig >/dev/null 2>&1 || true
    fi
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

  # Step 4: Remove plugin directory, Hyprland Lua files, and transient state/lock files.
  rm -rf "${PLUGIN_DEST}" "${HYPR_DIR}/windaase.lua" "${HYPR_DIR}/windaase" "${HOME}/.config/omarchy/.windaase-install"
  rm -f "${HOME}/.config/omarchy/windaase.json" "${HOME}/.config/omarchy/.windaase.lock"

  if [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
    rm -f \
      "${XDG_RUNTIME_DIR}/omarchy-windaase-snap.json" \
      "${XDG_RUNTIME_DIR}/omarchy-windaase-alttab.json" \
      "${XDG_RUNTIME_DIR}/omarchy-windaase-monitor-preview.json"
  fi
  CACHE_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}"
  rm -f \
    "${CACHE_DIR}/omarchy-windaase-snap.json" \
    "${CACHE_DIR}/omarchy-windaase-alttab.json" \
    "${CACHE_DIR}/omarchy-windaase-monitor-preview.json"

  # Step 5: Reload shell plugin catalog and Hyprland config.
  if command -v omarchy-shell >/dev/null 2>&1; then
    omarchy-shell -q shell rescanPlugins || true
  fi

  if command -v hyprctl >/dev/null 2>&1; then
    hyprctl reload >/dev/null || true
  fi

  echo "==> Omarchy-windåse uninstalled."
  exit 0
}

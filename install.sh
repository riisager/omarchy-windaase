#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="riisager.windaase"
PLUGIN_DEST="${HOME}/.config/omarchy/plugins/${PLUGIN_ID}"
HYPR_DIR="${HOME}/.config/hypr"
HYPRLAND_LUA="${HYPR_DIR}/hyprland.lua"

MODE="default"
BAR_HEIGHT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --shell-only) MODE="shell-only" ;;
    --full) MODE="full" ;;
    --bar-height)
      [[ $# -ge 2 ]] || { echo "Missing value for --bar-height" >&2; exit 1; }
      BAR_HEIGHT="$2"
      shift
      ;;
    --bar-height=*)
      BAR_HEIGHT="${1#--bar-height=}"
      ;;
    -h|--help)
      cat <<USAGE
Usage: ./install.sh [--shell-only | --full] [--bar-height <px>]

  (default)          Install the Omarchy-windåse shell plugin + Hyprland Lua module.
  --shell-only       Install only the Omarchy shell plugin (taskbar + Snap Layouts UI).
  --full             Default install PLUS bottom bar, disable omarchy.dock, and floating layout default.
  --bar-height <px>  Set [bar] size-horizontal in ~/.config/omarchy/shell.toml (24-64 px).
USAGE
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
  shift
done

if [[ -n "$BAR_HEIGHT" ]]; then
  if ! [[ "$BAR_HEIGHT" =~ ^[0-9]+$ ]] || (( BAR_HEIGHT < 24 || BAR_HEIGHT > 64 )); then
    echo "Invalid --bar-height '$BAR_HEIGHT' (expected integer between 24 and 64)" >&2
    exit 1
  fi
fi

STAGING_DIR=""
OLD_DIR=""
OLD_MOVED=0
SWAP_COMMITTED=0
WAS_INSTALLED=0
cleanup_temp_dirs() {
  if [[ "${OLD_MOVED}" -eq 1 && "${SWAP_COMMITTED}" -eq 0 && -n "${OLD_DIR}" && ( -e "${OLD_DIR}" || -L "${OLD_DIR}" ) ]]; then
    if [[ ! -e "${PLUGIN_DEST}" && ! -L "${PLUGIN_DEST}" ]] && mv "${OLD_DIR}" "${PLUGIN_DEST}" 2>/dev/null; then
      echo "Warning: installation failed; restored previous plugin at ${PLUGIN_DEST}" >&2
    else
      echo "Warning: installation failed; previous plugin preserved at ${OLD_DIR}" >&2
    fi
  elif [[ "${SWAP_COMMITTED}" -eq 1 && -n "${OLD_DIR}" && ( -e "${OLD_DIR}" || -L "${OLD_DIR}" ) ]]; then
    rm -rf "${OLD_DIR}"
  fi

  if [[ -n "${STAGING_DIR}" && ( -e "${STAGING_DIR}" || -L "${STAGING_DIR}" ) ]]; then
    rm -rf "${STAGING_DIR}"
  fi
}
trap cleanup_temp_dirs EXIT

mkdir -p "$(dirname "${PLUGIN_DEST}")"
SCRIPT_REAL="$(cd "${SCRIPT_DIR}" && pwd -P)"
DEST_PARENT_REAL="$(cd "$(dirname "${PLUGIN_DEST}")" && pwd -P)"
DEST_REAL="${DEST_PARENT_REAL}/$(basename "${PLUGIN_DEST}")"

if [[ "${SCRIPT_REAL}" == "${DEST_REAL}" ]]; then
  WAS_INSTALLED=1
  echo "==> Validating in-place Omarchy-windåse shell plugin at ${PLUGIN_DEST}"
  chmod +x "${PLUGIN_DEST}/windaase-config.py"
  omarchy plugin validate "${PLUGIN_DEST}"
  echo "==> Validated plugin: ${PLUGIN_ID}"
else
  echo "==> Staging and validating Omarchy-windåse shell plugin"
  STAGING_DIR="${PLUGIN_DEST}.staging.$$"
  OLD_DIR="${PLUGIN_DEST}.old.$$"

  mkdir -p "${STAGING_DIR}/i18n" "${STAGING_DIR}/nautilus"
  cp "${SCRIPT_DIR}/manifest.json" \
     "${SCRIPT_DIR}/layouts.json" \
     "${SCRIPT_DIR}/TaskbarModel.js" \
     "${SCRIPT_DIR}/BarWidget.qml" \
     "${SCRIPT_DIR}/WindowPickerCard.qml" \
     "${SCRIPT_DIR}/AppMenuCard.qml" \
     "${SCRIPT_DIR}/ProfileAvatar.qml" \
     "${SCRIPT_DIR}/SettingsCard.qml" \
     "${SCRIPT_DIR}/SnapAssistCard.qml" \
     "${SCRIPT_DIR}/AltTabSwitcher.qml" \
     "${SCRIPT_DIR}/Service.qml" \
     "${SCRIPT_DIR}/AppGrid.qml" \
     "${SCRIPT_DIR}/windaase-config.py" \
     "${SCRIPT_DIR}/LICENSE" \
     "${SCRIPT_DIR}/README.md" \
     "${STAGING_DIR}/"
  chmod +x "${STAGING_DIR}/windaase-config.py"
  cp "${SCRIPT_DIR}/i18n/"*.json "${STAGING_DIR}/i18n/"
  cp "${SCRIPT_DIR}/nautilus/windaase_context_menu.py" "${STAGING_DIR}/nautilus/"

  omarchy plugin validate "${STAGING_DIR}"
  echo "==> Validated plugin: ${PLUGIN_ID}"

  if [[ -e "${PLUGIN_DEST}" || -L "${PLUGIN_DEST}" ]]; then
    WAS_INSTALLED=1
    mv "${PLUGIN_DEST}" "${OLD_DIR}"
    OLD_MOVED=1
  fi
  if ! mv "${STAGING_DIR}" "${PLUGIN_DEST}"; then
    exit 1
  fi
  SWAP_COMMITTED=1
  STAGING_DIR=""
  if [[ "${OLD_MOVED}" -eq 1 && ( -e "${OLD_DIR}" || -L "${OLD_DIR}" ) ]]; then
    rm -rf "${OLD_DIR}"
    OLD_MOVED=0
  fi
  echo "==> Installed Omarchy-windåse shell plugin to ${PLUGIN_DEST}"
fi

if [[ "$(python3 "${PLUGIN_DEST}/windaase-config.py" nautilus-menu status 2>/dev/null || true)" == "installed" ]]; then
  if python3 "${PLUGIN_DEST}/windaase-config.py" nautilus-menu on; then
    echo "==> Refreshed opt-in Nautilus context menu extension"
  else
    echo "Warning: could not refresh opt-in Nautilus context menu extension; continuing install." >&2
  fi
fi

if [[ "$MODE" != "shell-only" ]]; then
  echo "==> Installing Hyprland Lua module to ${HYPR_DIR}/windaase*"
  mkdir -p "${HYPR_DIR}/windaase"
  cp "${SCRIPT_DIR}/hypr/windaase.lua" "${HYPR_DIR}/windaase.lua"
  cp "${SCRIPT_DIR}/hypr/windaase/"*.lua "${HYPR_DIR}/windaase/"
  cp "${SCRIPT_DIR}/layouts.json" "${HYPR_DIR}/windaase/layouts.json"

  if [[ -f "${HYPRLAND_LUA}" ]]; then
    if ! grep -qE 'require\(["'\'']hypr\.windaase["'\'']\)' "${HYPRLAND_LUA}"; then
      BACKUP="${HYPRLAND_LUA}.bak-$(date +%Y%m%d-%H%M%S)"
      cp "${HYPRLAND_LUA}" "${BACKUP}"
      echo "==> Backed up ${HYPRLAND_LUA} to ${BACKUP}"
      printf '\n-- Omarchy-windåse\nrequire("hypr.windaase").setup()\n' >> "${HYPRLAND_LUA}"
    else
      echo "==> ${HYPRLAND_LUA} already loads hypr.windaase"
    fi
  else
    echo "Warning: ${HYPRLAND_LUA} not found; add require(\"hypr.windaase\").setup() manually." >&2
  fi
fi

if [[ "$MODE" == "full" ]]; then
  echo "==> Applying full Windows desktop defaults (bottom bar, floating mode, disable omarchy.dock)"
  STATE_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/omarchy"
  LAYOUTS_DIR="${STATE_DIR}/workspace-layouts"
  LAYOUTS_BACKUP=""
  if [[ -d "${LAYOUTS_DIR}" ]] && compgen -G "${LAYOUTS_DIR}/*.lua" >/dev/null; then
    LAYOUTS_BACKUP="${STATE_DIR}/workspace-layouts.bak-$(date +%Y%m%d-%H%M%S)-$$"
    cp -a "${LAYOUTS_DIR}" "${LAYOUTS_BACKUP}"
    echo "==> Backed up ${LAYOUTS_DIR} to ${LAYOUTS_BACKUP}"
  fi

  SHELL_JSON="${HOME}/.config/omarchy/shell.json"
  if [[ -f "${SHELL_JSON}" ]]; then
    SHELL_JSON_BAK="${SHELL_JSON}.bak-$(date +%Y%m%d-%H%M%S)-$$"
    cp "${SHELL_JSON}" "${SHELL_JSON_BAK}"
    echo "==> Backed up ${SHELL_JSON} to ${SHELL_JSON_BAK}"
  fi

  omarchy-hyprland-workspace-layout-default floating || true

  if [[ -n "${LAYOUTS_BACKUP}" ]]; then
    RESTORED_OVERRIDES=0
    for saved_override in "${LAYOUTS_BACKUP}"/[0-9]*.lua; do
      [[ -f "${saved_override}" ]] || continue
      base="$(basename "${saved_override}")"
      if [[ ! -f "${LAYOUTS_DIR}/${base}" ]]; then
        cp -a "${saved_override}" "${LAYOUTS_DIR}/${base}"
        RESTORED_OVERRIDES=$((RESTORED_OVERRIDES + 1))
      fi
    done
    if (( RESTORED_OVERRIDES > 0 )); then
      echo "==> Preserved ${RESTORED_OVERRIDES} existing workspace layout override(s)"
      if command -v omarchy-shell >/dev/null 2>&1; then
        omarchy-shell -q omarchy.workspaces refresh || true
      fi
    fi
  fi

  omarchy plugin disable omarchy.dock || true
  omarchy bar position bottom || true
fi

if [[ -n "$BAR_HEIGHT" ]]; then
  SHELL_TOML="${HOME}/.config/omarchy/shell.toml"
  if [[ -f "${SHELL_TOML}" ]]; then
    TOML_BAK="${SHELL_TOML}.bak-$(date +%Y%m%d-%H%M%S)"
    cp "${SHELL_TOML}" "${TOML_BAK}"
    echo "==> Backed up ${SHELL_TOML} to ${TOML_BAK}"
  fi
  python3 "${SCRIPT_DIR}/windaase-config.py" bar-height "${BAR_HEIGHT}"
  echo "==> Set [bar] size-horizontal = ${BAR_HEIGHT} in ${SHELL_TOML}"
fi

if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell -q shell rescanPlugins || true
  if ! omarchy plugin enable "${PLUGIN_ID}" --section left --after omarchy.workspaces >/dev/null 2>&1; then
    omarchy plugin enable "${PLUGIN_ID}" --section left >/dev/null 2>&1 || omarchy plugin enable "${PLUGIN_ID}" || true
  fi
  if [[ "${WAS_INSTALLED}" -eq 1 ]]; then
    echo "==> Upgrading an active session? Run 'omarchy-restart-shell' so Qt6 reloads updated QML views."
  fi
fi

if [[ "$MODE" != "shell-only" ]] && command -v hyprctl >/dev/null 2>&1; then
  hyprctl reload >/dev/null || true
fi

echo "==> Omarchy-windåse installed (${MODE})."

#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="riisager.windaase"
PLUGIN_DEST="${HOME}/.config/omarchy/plugins/${PLUGIN_ID}"
HYPR_DIR="${HOME}/.config/hypr"
HYPRLAND_LUA="${HYPR_DIR}/hyprland.lua"

MODE="default"
for arg in "$@"; do
  case "$arg" in
    --shell-only) MODE="shell-only" ;;
    --full) MODE="full" ;;
    -h|--help)
      cat <<USAGE
Usage: ./install.sh [--shell-only | --full]

  (default)     Install the Omarchy-windåse shell plugin + Hyprland Lua module.
  --shell-only  Install only the Omarchy shell plugin (taskbar + Snap Layouts UI).
  --full        Default install PLUS bottom bar, disable omarchy.dock, and floating layout default.
USAGE
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      exit 1
      ;;
  esac
done

echo "==> Installing Omarchy-windåse shell plugin to ${PLUGIN_DEST}"
rm -rf "${PLUGIN_DEST}"
mkdir -p "${PLUGIN_DEST}/i18n"
cp "${SCRIPT_DIR}/manifest.json" \
   "${SCRIPT_DIR}/layouts.json" \
   "${SCRIPT_DIR}/TaskbarModel.js" \
   "${SCRIPT_DIR}/BarWidget.qml" \
   "${SCRIPT_DIR}/Service.qml" \
   "${SCRIPT_DIR}/LICENSE" \
   "${SCRIPT_DIR}/README.md" \
   "${PLUGIN_DEST}/"
cp "${SCRIPT_DIR}/i18n/"*.json "${PLUGIN_DEST}/i18n/"

omarchy plugin validate "${PLUGIN_DEST}"
echo "==> Validated plugin: ${PLUGIN_ID}"

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
  omarchy-hyprland-workspace-layout-default floating || true
  omarchy plugin disable omarchy.dock || true
  omarchy bar position bottom || true
fi

if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell -q shell rescanPlugins || true
  if ! omarchy plugin enable "${PLUGIN_ID}" --section left --after omarchy.workspaces >/dev/null 2>&1; then
    omarchy plugin enable "${PLUGIN_ID}" --section left >/dev/null 2>&1 || omarchy plugin enable "${PLUGIN_ID}" || true
  fi
fi

if [[ "$MODE" != "shell-only" ]] && command -v hyprctl >/dev/null 2>&1; then
  hyprctl reload >/dev/null || true
fi

echo "==> Omarchy-windåse installed (${MODE})."

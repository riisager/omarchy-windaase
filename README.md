# Omarchy-windåse

> *"Windåse"* is Danish slang/wordplay for *Windows* — literally *"wind-can"*.  
> A small, zero-bloat add-on for **Omarchy 4.5** that brings familiar Windows 11 desktop ergonomics to Hyprland floating mode without touching a single file in `/usr/share/omarchy/`.

## What it does

- **Single-bar Taskbar (`bar-widget`):** Pinned and running apps right inside the Omarchy bar (no separate dock stealing vertical space). Left-click focuses or minimizes, multi-window apps open an upward picker with workspace badges and close buttons, and middle-click opens a new window.
- **Per-window browser splitting + live profile menu:** Configure `uncombine` in `shell.json` to show each Chrome/Chromium/Brave window as its own icon with window-title tooltips. Right-click any supported Chromium browser icon to launch any profile from `Local State` with its avatar.
- **Windows 11 Snap Layouts (`service` + Lua):** Drag a floating window to the top edge of any monitor (or press `Super + Z`) for a live 6-layout grid (`50/50`, `65/35`, `50 | 25/25`, `33/33/33`, `2×2`, `100%`) plus Aero Snap via `Super + Arrows` or screen edges — pixel-accurate with `hyprbars` titlebars.
- **Soft-maximize & Windows stacking (`hypr.windaase`):** Replaces Hyprland's native `fullscreen = 1` on floating workspaces with edge-to-edge floating maximize (keeping `fullscreen = 2` true fullscreen untouched), eliminating the `hasfullscreen` click-trap underneath overlapping windows, and auto-raises floating windows on focus.
- **Hover-scroll (`follow_mouse = 2`):** Scroll whichever window your cursor is over without moving keyboard focus until you click.
- **In-process Show Desktop (`Super + D`):** Pure Lua toggle that minimizes/restores the active workspace cleanly with zero subprocesses or stale tags.
- **Localized (`i18n`):** Ships English (`en`) and Danish (`da`) catalogs via `Commons.Translations`, switching live with Omarchy Setup > Language.

## Quick start

### Option A — Full setup (Shell plugin + Hyprland ergonomics)

```bash
git clone <your-repo-url> omarchy-windaase
cd omarchy-windaase
./install.sh --full
```

Use `./install.sh` (without `--full`) if you want to keep your existing bar position, dock, and workspace tiling/floating defaults while adding the taskbar, Snap Layouts, and `hypr.windaase`.

### Option B — Shell plugin only (via Omarchy CLI)

```bash
omarchy plugin add <your-git-url> --enable
```

*(Shell-only gives you the Taskbar widget and Snap Layouts overlay host; `hypr.windaase` handles drag-snap, Aero Snap, soft-maximize, auto-raise, hover-scroll, and `Super + D`/`Super + Z`.)*

## Configuration

### Taskbar settings in `~/.config/omarchy/shell.json`

Move `"riisager.windaase"` in `bar.layout` (normally right after `"omarchy.workspaces"`) and optionally list desktop IDs to uncombine:

```json
{
  "bar": {
    "position": "bottom",
    "layout": {
      "left": [
        { "id": "omarchy.menu" },
        { "id": "omarchy.workspaces" },
        { "id": "riisager.windaase", "uncombine": ["google-chrome"] }
      ]
    }
  }
}
```

### Hyprland options in `~/.config/hypr/hyprland.lua`

```lua
require("hypr.windaase").setup({
  aero_snap = true,     -- Super + Arrow keys & edge-drag snap
  snap_layouts = true,  -- Top-edge drag Snap Layouts & Super + Z
  soft_maximize = true, -- Replace floating fullscreen=1 with soft maximize
  auto_raise = true,    -- Raise floating window to top on focus
  hover_scroll = true,  -- Set input.follow_mouse = 2 on floating workspaces
  shortcuts = true,     -- Alt + F4, Super + D (Show Desktop), Super + E (Files)
  gap_out = 8,
  gap_in = 8,
})
```

## Architecture

```
omarchy-windaase/
├── manifest.json            # Omarchy shell plugin manifest (service + bar-widget)
├── BarWidget.qml            # In-bar taskbar widget + Chromium profile menu
├── TaskbarModel.js          # Pure JS window grouping, ordering & profile parser
├── Service.qml              # Always-mapped click-through Snap Layouts overlay
├── layouts.json             # Single source of truth for Snap Layouts geometry
├── i18n/{en,da}.json        # Live Omarchy translations
├── hypr/
│   ├── windaase.lua         # Public entry point: require("hypr.windaase").setup()
│   └── windaase/
│       ├── geometry.lua     # JSON loader, monitor work-area math & frame insets
│       ├── snap.lua         # Aero Snap, soft-maximize & auto-raise
│       ├── snap_layouts.lua # Event-driven drag monitor (0% idle CPU) & Super+Z
│       ├── focus.lua        # follow_mouse = 2 enforcement
│       └── show_desktop.lua # In-process Super+D toggle
├── tests/                   # Node + Lua unit tests
├── install.sh
└── uninstall.sh
```

## Running tests & validation

```bash
node tests/taskbar_model.test.js
lua tests/geometry_test.lua
omarchy plugin validate ~/.config/omarchy/plugins/riisager.windaase
```

## Uninstall

```bash
./uninstall.sh                 # Remove Omarchy-windåse plugin & Hyprland Lua module
./uninstall.sh --restore-stock # Also re-enable omarchy.dock and move bar back to top
```

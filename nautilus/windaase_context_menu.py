# Managed by Omarchy-windåse (riisager.windaase)
"""Opt-in Windows-style right-click actions for Nautilus on Omarchy."""

import json
import os
import re
import shutil

MANAGED_MARKER = "# Managed by Omarchy-windåse (riisager.windaase)"

DEFAULT_LABELS = {
    "nautilus.copyPath": "Copy as path",
    "nautilus.copyPaths": "Copy paths",
    "nautilus.copyFolderPath": "Copy folder path",
    "nautilus.openTerminal": "Open in Terminal",
    "nautilus.openEditor": "Open in Editor",
    "nautilus.newTextDocument": "New Text Document",
}

_LOCALE_RE = re.compile(r"^[A-Za-z0-9_-]{1,16}$")


def _normalize_locale(raw):
    text = str(raw or "").strip()
    if not text:
        return ""
    text = text.split("@", 1)[0].split(".", 1)[0].replace("_", "-").strip()
    if not _LOCALE_RE.fullmatch(text):
        return ""
    if text in (".", ".."):
        return ""
    return text


def is_plugin_installed(home_dir=None):
    """Return True only while riisager.windaase is installed in ~/.config/omarchy/plugins."""
    home = os.path.expanduser(home_dir) if home_dir else os.path.expanduser("~")
    manifest = os.path.join(home, ".config", "omarchy", "plugins", "riisager.windaase", "manifest.json")
    return os.path.isfile(manifest)


def load_labels(home_dir=None, lang_env=None):
    """Load localized context-menu labels from the installed Windåse plugin."""
    labels = dict(DEFAULT_LABELS)
    home = os.path.expanduser(home_dir) if home_dir else os.path.expanduser("~")
    omarchy_cfg = os.path.join(home, ".config", "omarchy")

    raw_lang = ""
    lang_file = os.path.join(omarchy_cfg, "language")
    try:
        with open(lang_file, "r", encoding="utf-8", errors="ignore") as handle:
            raw_lang = handle.read().strip()
    except OSError:
        raw_lang = ""

    if not raw_lang:
        raw_lang = lang_env if lang_env is not None else os.environ.get("LANG", "")

    code = _normalize_locale(raw_lang)
    if not code:
        return labels

    candidates = [code]
    if "-" in code:
        base = code.split("-", 1)[0]
        if base and base not in candidates:
            candidates.append(base)

    i18n_dir = os.path.realpath(os.path.join(omarchy_cfg, "plugins", "riisager.windaase", "i18n"))
    for cand in candidates:
        cand_path = os.path.realpath(os.path.join(i18n_dir, f"{cand}.json"))
        if not cand_path.startswith(i18n_dir + os.sep):
            continue
        try:
            with open(cand_path, "r", encoding="utf-8") as handle:
                parsed = json.load(handle)
        except (OSError, ValueError):
            continue
        if isinstance(parsed, dict):
            for key in DEFAULT_LABELS:
                val = parsed.get(key)
                if isinstance(val, str) and val.strip():
                    labels[key] = val
            return labels

    return labels


def format_paths_payload(paths):
    """Deduplicate non-empty paths in selection order and join with newlines."""
    if not paths:
        return ""
    out = []
    seen = set()
    for p in paths:
        if not isinstance(p, str) or not p or not p.strip():
            continue
        if p not in seen:
            seen.add(p)
            out.append(p)
    return "\n".join(out)


def build_terminal_command(folder_path, which_fn=shutil.which):
    """Build argv to launch the configured terminal inside folder_path."""
    if not isinstance(folder_path, str) or not folder_path or "\x00" in folder_path:
        return None
    xdg_term = which_fn("xdg-terminal-exec")
    if not xdg_term:
        return None
    dir_arg = f"--dir={folder_path}"
    uwsm_app = which_fn("uwsm-app")
    if uwsm_app:
        return [uwsm_app, "--", xdg_term, dir_arg]
    return [xdg_term, dir_arg]


def build_editor_command(paths, which_fn=shutil.which):
    """Build argv to open paths with Omarchy's configured default editor."""
    if not paths:
        return None
    clean = [p for p in paths if isinstance(p, str) and p and "\x00" not in p]
    if not clean:
        return None
    launcher = which_fn("omarchy-launch-editor")
    if not launcher:
        return None
    return [launcher] + clean


def create_new_text_file(folder_path, base_name="Untitled", ext=".txt"):
    """Atomically create an empty text file without overwriting existing entries."""
    if not isinstance(folder_path, str) or not folder_path or not os.path.isdir(folder_path):
        return None
    if os.sep in base_name or os.sep in ext or (os.altsep and (os.altsep in base_name or os.altsep in ext)):
        return None

    for idx in range(1, 1000):
        name = f"{base_name}{ext}" if idx == 1 else f"{base_name} {idx}{ext}"
        candidate = os.path.join(folder_path, name)
        try:
            fd = os.open(candidate, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
            os.close(fd)
            return candidate
        except FileExistsError:
            continue
        except OSError:
            return None
    return None


try:
    from gi import require_version

    require_version("Nautilus", "4.1")
    from gi.repository import GObject, Gio, Nautilus

    _HAS_NAUTILUS = True
except (ImportError, ValueError):
    _HAS_NAUTILUS = False


if _HAS_NAUTILUS:

    class WindaaseContextMenuProvider(GObject.GObject, Nautilus.MenuProvider):
        """Provides Windows-style file and folder background actions in Nautilus."""

        def _finish_copy(self, proc, res):
            try:
                proc.communicate_utf8_finish(res)
            except Exception:
                pass

        def _copy_to_clipboard(self, text):
            if not text:
                return
            wl_copy = shutil.which("wl-copy")
            if not wl_copy:
                return
            try:
                proc = Gio.Subprocess.new([wl_copy, "-n"], Gio.SubprocessFlags.STDIN_PIPE)
                proc.communicate_utf8_async(text, None, self._finish_copy)
            except Exception:
                pass

        def _spawn(self, argv):
            if not argv:
                return
            try:
                Gio.Subprocess.new(argv, Gio.SubprocessFlags.NONE)
            except Exception:
                pass

        def _selected_paths(self, files):
            paths = []
            seen = set()
            for file_info in files or []:
                location = file_info.get_location()
                if not location:
                    continue
                path = location.get_path()
                if path and path not in seen:
                    seen.add(path)
                    paths.append(path)
            return paths

        def _make_item(self, item_id, label, icon_name, callback, *cb_args):
            item = Nautilus.MenuItem(
                name=f"WindaaseNautilus::{item_id}",
                label=label,
                icon=icon_name,
            )
            item.connect("activate", callback, *cb_args)
            return item

        def _on_copy_paths(self, _menu, payload):
            self._copy_to_clipboard(payload)

        def _on_open_terminal(self, _menu, folder_path):
            self._spawn(build_terminal_command(folder_path))

        def _on_open_editor(self, _menu, paths):
            self._spawn(build_editor_command(paths))

        def _on_new_text_file(self, _menu, folder_path):
            create_new_text_file(folder_path)

        def get_file_items(self, *args):
            if not is_plugin_installed():
                return []
            if not args:
                return []
            files = args[0] if len(args) == 1 else args[1]
            paths = self._selected_paths(files)
            if not paths:
                return []

            labels = load_labels()
            items = []

            payload = format_paths_payload(paths)
            if payload and shutil.which("wl-copy"):
                copy_label = labels["nautilus.copyPath"] if len(paths) == 1 else labels["nautilus.copyPaths"]
                items.append(
                    self._make_item("copy_path", copy_label, "edit-copy-symbolic", self._on_copy_paths, payload)
                )

            if len(paths) == 1 and os.path.isdir(paths[0]) and build_terminal_command(paths[0]):
                items.append(
                    self._make_item(
                        "open_terminal",
                        labels["nautilus.openTerminal"],
                        "utilities-terminal-symbolic",
                        self._on_open_terminal,
                        paths[0],
                    )
                )

            if 1 <= len(paths) <= 10 and build_editor_command(paths):
                items.append(
                    self._make_item(
                        "open_editor",
                        labels["nautilus.openEditor"],
                        "accessories-text-editor-symbolic",
                        self._on_open_editor,
                        paths,
                    )
                )

            return items

        def get_background_items(self, *args):
            if not is_plugin_installed():
                return []
            if not args:
                return []
            folder = args[0] if len(args) == 1 else args[1]
            if not folder:
                return []
            location = folder.get_location()
            if not location:
                return []
            folder_path = location.get_path()
            if not folder_path or not os.path.isdir(folder_path):
                return []

            labels = load_labels()
            items = []

            if shutil.which("wl-copy"):
                items.append(
                    self._make_item(
                        "bg_copy_path",
                        labels["nautilus.copyFolderPath"],
                        "edit-copy-symbolic",
                        self._on_copy_paths,
                        folder_path,
                    )
                )

            if build_terminal_command(folder_path):
                items.append(
                    self._make_item(
                        "bg_open_terminal",
                        labels["nautilus.openTerminal"],
                        "utilities-terminal-symbolic",
                        self._on_open_terminal,
                        folder_path,
                    )
                )

            if build_editor_command([folder_path]):
                items.append(
                    self._make_item(
                        "bg_open_editor",
                        labels["nautilus.openEditor"],
                        "accessories-text-editor-symbolic",
                        self._on_open_editor,
                        [folder_path],
                    )
                )

            if os.access(folder_path, os.W_OK):
                items.append(
                    self._make_item(
                        "bg_new_text_document",
                        labels["nautilus.newTextDocument"],
                        "document-new-symbolic",
                        self._on_new_text_file,
                        folder_path,
                    )
                )

            return items

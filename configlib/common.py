"""Shared filesystem, locking, and path helpers for Omarchy-windåse."""

import contextlib
import fcntl
import os
import tempfile

HYPR_OPTION_KEYS = (
    "aero_snap",
    "snap_layouts",
    "snap_assist",
    "snap_resize",
    "ultrawide_layout",
    "floating_only",
    "soft_maximize",
    "auto_raise",
    "hover_scroll",
    "shortcuts",
    "alt_tab",
)

NAUTILUS_EXT_MARKER = "# Managed by Omarchy-windåse (riisager.windaase)"

TWO_LINE_CLOCK_FORMAT = "HH:mm\ndd-MM-yyyy"
DEFAULT_CLOCK_FORMAT = "dddd HH:mm"


def atomic_write(path, content, mode=None):
    parent = os.path.dirname(os.path.abspath(path))
    os.makedirs(parent, exist_ok=True)
    if mode is None and os.path.exists(path) and not os.path.islink(path):
        mode = os.stat(path).st_mode & 0o777
    fd, tmp_path = tempfile.mkstemp(prefix=".windaase-", suffix=".tmp", dir=parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as handle:
            handle.write(content)
        if mode is not None:
            os.chmod(tmp_path, mode)
        os.replace(tmp_path, path)
    except Exception:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)
        raise


def omarchy_dir(home_dir=None):
    home = os.path.abspath(os.path.expanduser(home_dir)) if home_dir else os.path.expanduser("~")
    return os.path.join(home, ".config", "omarchy")


def state_omarchy_dir(home_dir=None, state_home=None):
    if state_home:
        base = os.path.abspath(os.path.expanduser(state_home))
    elif not home_dir and os.environ.get("XDG_STATE_HOME"):
        base = os.path.abspath(os.path.expanduser(os.environ["XDG_STATE_HOME"]))
    else:
        home = os.path.abspath(os.path.expanduser(home_dir)) if home_dir else os.path.expanduser("~")
        base = os.path.join(home, ".local", "state")
    return os.path.join(base, "omarchy")


def workspace_layouts_dir(home_dir=None, state_home=None):
    return os.path.join(state_omarchy_dir(home_dir=home_dir, state_home=state_home), "workspace-layouts")


@contextlib.contextmanager
def config_lock(home_dir=None):
    cfg_dir = omarchy_dir(home_dir=home_dir)
    os.makedirs(cfg_dir, exist_ok=True)
    lock_path = os.path.join(cfg_dir, ".windaase.lock")
    fd = os.open(lock_path, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)

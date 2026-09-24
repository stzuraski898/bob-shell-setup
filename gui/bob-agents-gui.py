#!/usr/bin/env python3
"""
Bob Agents GUI
──────────────
A Tkinter GUI front-end for launch-bob-agents.sh.

Features
  • Toggle flags: --local, --no-worktrees, --dry-run
  • Browse for any instructions file
  • Run Dry Run and see output live in the log panel
  • Launch agents (full run, no dry-run)
  • Config page — persistent settings saved to ~/.config/bob-agents-gui.json
  • Dark theme matching the reference screenshot
"""

import base64
import json
import os
import struct
import subprocess
import sys
import threading
import tkinter as tk
from tkinter import filedialog, font, scrolledtext

# ── colour palette ────────────────────────────────────────────────────────────
BG       = "#1e1e2e"   # main background
SURFACE  = "#2a2a3e"   # panel / header background
BORDER   = "#3a3a5c"   # separator / border lines
FG       = "#cdd6f4"   # primary text
MUTED    = "#7c7fa6"   # secondary / muted text
ACCENT   = "#89b4fa"   # blue accent (toggles on)
GREEN    = "#a6e3a1"
YELLOW   = "#f9e2af"
RED      = "#f38ba8"
BTN_RUN  = "#89b4fa"   # launch button fill
BTN_FG   = "#1e1e2e"   # launch button text

# ── per-AI-system themes ──────────────────────────────────────────────────────
THEMES = {
    "bob": {
        "surface": "#2a2a3e",
        "border":  "#3a3a5c",
        "accent":  "#89b4fa",   # blue
        "btn_run": "#89b4fa",
    },
    "claude": {
        "surface": "#2a2230",   # dark with a very subtle warm tint — matches Bob's darkness
        "border":  "#4a3a50",   # muted warm-purple border
        "accent":  "#f4b896",   # light peach-orange
        "btn_run": "#f4b896",
    },
}

# Resolve directory for bundled assets vs runtime directory
if getattr(sys, "frozen", False) and hasattr(sys, "_MEIPASS"):
    BUNDLE_DIR = getattr(sys, "_MEIPASS")
    SCRIPT_DIR = os.path.dirname(sys.executable)
    REPO_DIR   = SCRIPT_DIR
else:
    BUNDLE_DIR = os.path.dirname(os.path.abspath(__file__))
    SCRIPT_DIR = BUNDLE_DIR
    REPO_DIR   = os.path.dirname(BUNDLE_DIR)

def _resolve_resource(filename: str) -> str:
    """Find a resource file in BUNDLE_DIR, SCRIPT_DIR, or REPO_DIR."""
    for base in (BUNDLE_DIR, SCRIPT_DIR, REPO_DIR):
        p = os.path.join(base, filename)
        if os.path.exists(p):
            return p
    return os.path.join(BUNDLE_DIR, filename)

LAUNCH_SCRIPT = _resolve_resource("launch-bob-agents.sh")
CONFIG_PATH   = os.path.expanduser("~/.config/bob-agents-gui.json")

# ── default configuration ─────────────────────────────────────────────────────
DEFAULT_CONFIG = {
    # API keys (base64-encoded in storage to avoid plaintext on disk)
    "bobshell_api_key":         "",
    "ceph_tracker_api_key":     "",
    "ceph_tracker_username":    "",
    "ceph_tracker_password":    "",
    # Connection
    "remote_host":          "sockeni07",
    "remote_user":          "szuraski",
    # AI system — "bob" or "claude"
    "ai_system":            "bob",
    # Defaults for the Launch page toggles
    "default_local":        False,
    "default_no_worktrees": False,
    "default_dry_run":      True,
    "claude_trust":         True,   # pass --trust to each claude agent invocation
    # Paths — remote
    "remote_workspace_root": "/home/szuraski",
    "remote_main_dir":       "/home/szuraski/ceph",
    # Paths — local
    "local_workspace_root":  os.path.expanduser("~/Projects"),
    "local_main_dir":        os.path.expanduser("~/Projects/ceph"),
    # Instructions — can be a directory (new) or a legacy file
    "default_instructions":  "",
    # Quick-select presets (list of [label, path]) — dirs preferred, files OK
    "presets": [
        ["History",     os.path.join(REPO_DIR, "Inputs", "Prompts",
                                     "history-assessment")],
        ["Latent Bugs", os.path.join(REPO_DIR, "Inputs", "Prompts",
                                     "latent-bug-tests")],
        ["WB Defense",  os.path.join(REPO_DIR, "Inputs", "Prompts",
                                     "whiteboard-defense")],
    ],
}


# ── key encode/decode (base64 — not encryption, just avoids plaintext) ────────

def _encode_key(plaintext: str) -> str:
    return base64.b64encode(plaintext.encode()).decode() if plaintext else ""

def _decode_key(encoded: str) -> str:
    try:
        return base64.b64decode(encoded.encode()).decode() if encoded else ""
    except Exception:
        return ""


# ── config helpers ────────────────────────────────────────────────────────────

def load_config() -> dict:
    if os.path.isfile(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, "r") as fh:
                stored = json.load(fh)
            # Merge so new keys added in DEFAULT_CONFIG always have a value
            merged = dict(DEFAULT_CONFIG)
            merged.update(stored)
            return merged
        except Exception:
            pass
    return dict(DEFAULT_CONFIG)


def save_config(cfg: dict) -> None:
    os.makedirs(os.path.dirname(CONFIG_PATH), exist_ok=True)
    with open(CONFIG_PATH, "w") as fh:
        json.dump(cfg, fh, indent=2)


# ── colour helper ─────────────────────────────────────────────────────────────

def _tk_color(hex_color: str, lighten: float = 0.0) -> str:
    if lighten == 0:
        return hex_color
    r = int(hex_color[1:3], 16)
    g = int(hex_color[3:5], 16)
    b = int(hex_color[5:7], 16)
    r = min(255, int(r + (255 - r) * lighten))
    g = min(255, int(g + (255 - g) * lighten))
    b = min(255, int(b + (255 - b) * lighten))
    return f"#{r:02x}{g:02x}{b:02x}"


# ── shared widget helpers ─────────────────────────────────────────────────────

def make_entry(parent, textvariable, mono_font, width=48) -> tk.Entry:
    return tk.Entry(
        parent, textvariable=textvariable,
        bg="#11111b", fg=FG, insertbackground=FG,
        relief=tk.FLAT, highlightbackground=BORDER, highlightthickness=1,
        font=mono_font, width=width,
    )


def separator(parent) -> tk.Frame:
    return tk.Frame(parent, bg=BORDER, height=1)


# ── ToggleButton widget ───────────────────────────────────────────────────────

class ToggleButton(tk.Canvas):
    """A pill-shaped toggle switch."""
    W, H, RADIUS = 46, 24, 11

    def __init__(self, parent, variable: tk.BooleanVar, bg_color=SURFACE,
                 accent_color=ACCENT, border_color=BORDER, **kwargs):
        super().__init__(parent, width=self.W, height=self.H,
                         bg=bg_color, highlightthickness=0, **kwargs)
        self._var    = variable
        self._accent = accent_color
        self._border = border_color
        self._draw()
        self.bind("<Button-1>", self._toggle)
        variable.trace_add("write", lambda *_: self._draw())

    def _draw(self):
        self.delete("all")
        on = self._var.get()
        track = self._accent if on else self._border
        x0, y0, x1, y1 = 2, 2, self.W - 2, self.H - 2
        r = self.RADIUS
        self.create_oval(x0, y0, x0 + r * 2, y1, fill=track, outline="")
        self.create_oval(x1 - r * 2, y0, x1, y1, fill=track, outline="")
        self.create_rectangle(x0 + r, y0, x1 - r, y1, fill=track, outline="")
        knob_x = x1 - r if on else x0 + r
        self.create_oval(knob_x - r + 2, y0 + 2, knob_x + r - 2, y1 - 2,
                         fill="white", outline="")

    def _toggle(self, _=None):
        self._var.set(not self._var.get())


# ── Tab strip ─────────────────────────────────────────────────────────────────

class TabStrip(tk.Frame):
    """Simple horizontal tab strip. Calls on_switch(tab_name) on click."""

    def __init__(self, parent, tabs: list[str], on_switch, **kwargs):
        super().__init__(parent, bg=SURFACE, **kwargs)
        self._tabs = tabs
        self._on_switch = on_switch
        self._btns: dict[str, tk.Label] = {}
        self._active = tabs[0]
        lf = font.Font(family="Sans", size=10, weight="bold")
        for t in tabs:
            lbl = tk.Label(self, text=t, font=lf, bg=SURFACE, fg=MUTED,
                           padx=20, pady=10, cursor="hand2")
            lbl.pack(side=tk.LEFT)
            lbl.bind("<Button-1>", lambda e, name=t: self._click(name))
            self._btns[t] = lbl
        self._highlight(self._active)

    def _click(self, name: str):
        self._active = name
        self._highlight(name)
        self._on_switch(name)

    def _highlight(self, name: str):
        for t, lbl in self._btns.items():
            if t == name:
                lbl.config(fg=FG)
                # underline via a thin accent frame below the label
                if not hasattr(lbl, "_bar"):
                    lbl._bar = tk.Frame(self, bg=ACCENT, height=2)
                    lbl._bar.place(in_=lbl, relx=0, rely=1.0, relwidth=1, anchor="nw")
            else:
                lbl.config(fg=MUTED)
                if hasattr(lbl, "_bar"):
                    lbl._bar.place_forget()


# ── Config page ───────────────────────────────────────────────────────────────

class ConfigPage(tk.Frame):
    """Settings panel. Reads/writes the global config dict."""

    def __init__(self, parent, cfg: dict, on_saved, on_ai_system_change=None, **kwargs):
        super().__init__(parent, bg=BG, **kwargs)
        self._cfg     = cfg
        self._on_saved = on_saved
        self._on_ai_system_change = on_ai_system_change  # called live on change
        self._vars: dict[str, tk.Variable] = {}
        self._preset_rows: list[dict] = []  # [{label_var, path_var}, …]
        self._build()

    # ── build ─────────────────────────────────────────────────────────────────

    def _build(self):
        mono = font.Font(family="Monospace", size=10)
        lf   = font.Font(family="Sans", size=10)
        bf   = font.Font(family="Sans", size=10, weight="bold")

        # Scrollable canvas so the page works even at small window sizes
        canvas = tk.Canvas(self, bg=BG, highlightthickness=0)
        vsb    = tk.Scrollbar(self, orient=tk.VERTICAL, command=canvas.yview,
                              bg=SURFACE, troughcolor=BG)
        canvas.configure(yscrollcommand=vsb.set)
        vsb.pack(side=tk.RIGHT, fill=tk.Y)
        canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        inner = tk.Frame(canvas, bg=BG)
        win_id = canvas.create_window((0, 0), window=inner, anchor="nw")

        def _on_configure(e):
            canvas.configure(scrollregion=canvas.bbox("all"))
        def _on_canvas_resize(e):
            canvas.itemconfig(win_id, width=e.width)

        inner.bind("<Configure>", _on_configure)
        canvas.bind("<Configure>", _on_canvas_resize)
        # Mouse-wheel scrolling
        canvas.bind_all("<MouseWheel>",
                        lambda e: canvas.yview_scroll(-1 * (e.delta // 120), "units"))
        canvas.bind_all("<Button-4>",
                        lambda e: canvas.yview_scroll(-1, "units"))
        canvas.bind_all("<Button-5>",
                        lambda e: canvas.yview_scroll(1, "units"))

        xpad = {"padx": 28}

        def section(title: str):
            tk.Frame(inner, bg=BORDER, height=1).pack(fill=tk.X, padx=28, pady=(18, 0))
            tk.Label(inner, text=title, font=bf, bg=BG, fg=ACCENT
                     ).pack(anchor="w", padx=28, pady=(6, 2))

        def field(label: str, key: str, entry_width=44, tooltip=""):
            var = tk.StringVar(value=str(self._cfg.get(key, "")))
            self._vars[key] = var
            row = tk.Frame(inner, bg=BG)
            row.pack(fill=tk.X, padx=28, pady=3)
            tk.Label(row, text=label, font=lf, bg=BG, fg=FG,
                     width=26, anchor="w").pack(side=tk.LEFT)
            make_entry(row, var, mono, entry_width).pack(side=tk.LEFT)
            if tooltip:
                tk.Label(row, text=tooltip, font=font.Font(family="Sans", size=9),
                         bg=BG, fg=MUTED).pack(side=tk.LEFT, padx=(8, 0))
            return var

        def toggle_field(label: str, key: str, tooltip=""):
            var = tk.BooleanVar(value=bool(self._cfg.get(key, False)))
            self._vars[key] = var
            row = tk.Frame(inner, bg=BG)
            row.pack(fill=tk.X, padx=28, pady=3)
            ToggleButton(row, var, bg_color=BG).pack(side=tk.LEFT, padx=(0, 10))
            tk.Label(row, text=label, font=lf, bg=BG, fg=FG).pack(side=tk.LEFT)
            if tooltip:
                tk.Label(row, text=tooltip, font=font.Font(family="Sans", size=9),
                         bg=BG, fg=MUTED).pack(side=tk.LEFT, padx=(8, 0))
            return var

        def radio_field(label: str, key: str, choices: list[tuple[str, str]],
                        tooltip="", live_callback=None):
            """Horizontal radio-button selector. choices = [(display, value), …]
            live_callback(value) is fired immediately on every change."""
            var = tk.StringVar(value=str(self._cfg.get(key, choices[0][1])))
            self._vars[key] = var
            row = tk.Frame(inner, bg=BG)
            row.pack(fill=tk.X, padx=28, pady=3)
            tk.Label(row, text=label, font=lf, bg=BG, fg=FG,
                     width=26, anchor="w").pack(side=tk.LEFT)
            for display, value in choices:
                rb = tk.Radiobutton(
                    row, text=display, variable=var, value=value,
                    font=lf, bg=SURFACE, fg=FG,
                    selectcolor=ACCENT, activebackground=BG, activeforeground=ACCENT,
                    indicatoron=1,          # standard radio indicator — renders reliably
                    relief=tk.FLAT,
                    padx=6, pady=4, cursor="hand2",
                    highlightthickness=0,
                )
                rb.pack(side=tk.LEFT, padx=(0, 8))
                # Highlight the label of the selected choice
                def _refresh(v=var, r=rb, val=value):
                    r.config(fg=ACCENT if v.get() == val else FG)
                var.trace_add("write", lambda *_, refresh=_refresh: refresh())
                _refresh()
            if live_callback:
                var.trace_add("write", lambda *_: live_callback(var.get()))
            if tooltip:
                tk.Label(row, text=tooltip, font=font.Font(family="Sans", size=9),
                         bg=BG, fg=MUTED).pack(side=tk.LEFT, padx=(8, 0))
            return var

        def browse_field(label: str, key: str, entry_width=40, is_dir=False,
                         dir_or_file=False):
            """Browse field. is_dir=True → directory only. dir_or_file=True → try
            directory first, fall back to file picker if user cancels."""
            var = tk.StringVar(value=str(self._cfg.get(key, "")))
            self._vars[key] = var
            row = tk.Frame(inner, bg=BG)
            row.pack(fill=tk.X, padx=28, pady=3)
            tk.Label(row, text=label, font=lf, bg=BG, fg=FG,
                     width=26, anchor="w").pack(side=tk.LEFT)
            make_entry(row, var, mono, entry_width).pack(side=tk.LEFT)

            def _browse():
                initial = var.get() or REPO_DIR
                if os.path.isfile(initial):
                    initial = os.path.dirname(initial)
                if is_dir or dir_or_file:
                    p = filedialog.askdirectory(initialdir=initial,
                                                title="Select folder (or cancel to pick a file)")
                    if p:
                        var.set(p)
                        return
                if not is_dir:
                    p = filedialog.askopenfilename(
                        initialdir=initial,
                        filetypes=[("All files", "*"), ("Markdown", "*.md")])
                    if p:
                        var.set(p)

            tk.Button(row, text="Browse…", font=lf, bg=SURFACE, fg=ACCENT,
                      relief=tk.FLAT, activebackground=BORDER, activeforeground=ACCENT,
                      padx=8, pady=3, cursor="hand2",
                      highlightbackground=BORDER, highlightthickness=1,
                      command=_browse).pack(side=tk.LEFT, padx=(8, 0))
            return var

        # ── Section: API Keys ─────────────────────────────────────────────────
        section("API Keys")
        tk.Label(inner,
                 text="Keys are stored obfuscated (base64) in the config file. "
                      "Environment variables take precedence over stored values.",
                 font=font.Font(family="Sans", size=9), bg=BG, fg=MUTED,
                 ).pack(anchor="w", padx=28, pady=(0, 4))

        def secret_row(cfg_key: str, label: str, is_password: bool = True):
            """Password-style (or plain) entry with Show/Hide and Clear buttons."""
            decoded = _decode_key(self._cfg.get(cfg_key, "")) if is_password \
                      else self._cfg.get(cfg_key, "")
            var = tk.StringVar(value=decoded)
            self._vars[cfg_key] = var   # _collect() will encode if is_password

            row = tk.Frame(inner, bg=BG)
            row.pack(fill=tk.X, padx=28, pady=3)
            tk.Label(row, text=label, font=lf, bg=BG, fg=FG,
                     width=26, anchor="w").pack(side=tk.LEFT)
            entry = make_entry(row, var, mono, 40)
            if is_password:
                entry.config(show="●")
            entry.pack(side=tk.LEFT)

            if is_password:
                _visible = tk.BooleanVar(value=False)
                def _toggle(e=entry, v=_visible):
                    v.set(not v.get())
                    e.config(show="" if v.get() else "●")
                    btn.config(text="Hide" if v.get() else "Show")
                btn = tk.Button(row, text="Show", font=lf,
                                bg=SURFACE, fg=MUTED, relief=tk.FLAT,
                                activebackground=BORDER, activeforeground=FG,
                                padx=8, pady=3, cursor="hand2",
                                command=_toggle)
                btn.pack(side=tk.LEFT, padx=(8, 0))

            tk.Button(row, text="Clear", font=lf,
                      bg=SURFACE, fg=RED, relief=tk.FLAT,
                      activebackground=BORDER, activeforeground=RED,
                      padx=8, pady=3, cursor="hand2",
                      command=lambda v=var: v.set(""),
                      ).pack(side=tk.LEFT, padx=(4, 0))
            return var

        secret_row("bobshell_api_key",     "BOBSHELL_API_KEY")
        secret_row("ceph_tracker_api_key", "CEPH_TRACKER_API_KEY")

        tk.Label(inner,
                 text="  Redmine username + password are only used when no API key is set.",
                 font=font.Font(family="Sans", size=9), bg=BG, fg=MUTED,
                 ).pack(anchor="w", padx=28, pady=(2, 0))
        secret_row("ceph_tracker_username", "CEPH_TRACKER_USERNAME", is_password=False)
        secret_row("ceph_tracker_password", "CEPH_TRACKER_PASSWORD")

        # ── Section: Remote connection ────────────────────────────────────────
        section("Remote Connection")
        field("SSH host",     "remote_host",  tooltip="e.g. sockeni07")
        field("SSH user",     "remote_user",  tooltip="e.g. szuraski")

        # ── Section: Launch defaults ──────────────────────────────────────────
        section("Launch Defaults")
        radio_field("AI System", "ai_system",
                    [("Bob", "bob"), ("Claude Code", "claude")],
                    "Which AI agent CLI to use when launching",
                    live_callback=self._on_ai_system_change)
        toggle_field("Default: --local",        "default_local",
                     "Open Launch page with --local pre-checked")
        toggle_field("Default: --no-worktrees", "default_no_worktrees",
                     "Open Launch page with --no-worktrees pre-checked")
        toggle_field("Default: --dry-run",      "default_dry_run",
                     "Open Launch page with --dry-run pre-checked")
        toggle_field("Claude: auto-approve edits", "claude_trust",
                     "Passes --permission-mode acceptEdits (skips trust dialog, approves file edits)")

        # ── Section: Remote paths ─────────────────────────────────────────────
        section("Remote Paths")
        field("Workspace root", "remote_workspace_root", tooltip="e.g. /home/szuraski")
        field("Main repo dir",  "remote_main_dir",        tooltip="e.g. /home/szuraski/ceph")

        # ── Section: Local paths ──────────────────────────────────────────────
        section("Local Paths")
        browse_field("Workspace root", "local_workspace_root", is_dir=True)
        browse_field("Main repo dir",  "local_main_dir",        is_dir=True)

        # ── Section: Instructions ─────────────────────────────────────────────
        section("Instructions")
        browse_field("Default instructions Folder", "default_instructions",
                     entry_width=38, dir_or_file=True)

        # ── Section: Quick-select presets ─────────────────────────────────────
        section("Quick-Select Presets")
        tk.Label(inner, text="Label and path pairs shown as buttons on the Launch page.",
                 font=font.Font(family="Sans", size=9), bg=BG, fg=MUTED,
                 ).pack(anchor="w", padx=28, pady=(0, 6))

        self._presets_frame = tk.Frame(inner, bg=BG)
        self._presets_frame.pack(fill=tk.X, padx=28)

        for lbl, path in self._cfg.get("presets", []):
            self._add_preset_row(lbl, path)

        tk.Button(inner, text="+ Add preset", font=lf,
                  bg=SURFACE, fg=ACCENT, relief=tk.FLAT,
                  activebackground=BORDER, activeforeground=ACCENT,
                  padx=10, pady=4, cursor="hand2",
                  command=lambda: self._add_preset_row("", "")
                  ).pack(anchor="w", padx=28, pady=(6, 0))

        # ── Save button ───────────────────────────────────────────────────────
        tk.Frame(inner, bg=BORDER, height=1).pack(fill=tk.X, padx=28, pady=(18, 0))
        btn_row = tk.Frame(inner, bg=BG)
        btn_row.pack(fill=tk.X, padx=28, pady=12)

        self._save_status = tk.StringVar(value="")
        tk.Label(btn_row, textvariable=self._save_status,
                 font=font.Font(family="Sans", size=9), bg=BG, fg=GREEN
                 ).pack(side=tk.LEFT)

        tk.Button(btn_row, text="Save Settings", font=bf,
                  bg=BTN_RUN, fg=BTN_FG, relief=tk.FLAT,
                  activebackground=_tk_color(BTN_RUN, 0.15), activeforeground=BTN_FG,
                  padx=18, pady=6, cursor="hand2",
                  command=self._save).pack(side=tk.RIGHT)

        tk.Button(btn_row, text="Reset to defaults", font=lf,
                  bg=SURFACE, fg=MUTED, relief=tk.FLAT,
                  activebackground=BORDER, activeforeground=FG,
                  padx=12, pady=6, cursor="hand2",
                  command=self._reset).pack(side=tk.RIGHT, padx=(0, 8))

    # ── preset rows ───────────────────────────────────────────────────────────

    def _add_preset_row(self, label: str, path: str):
        mono = font.Font(family="Monospace", size=10)
        lf   = font.Font(family="Sans", size=10)

        row_data = {
            "label_var": tk.StringVar(value=label),
            "path_var":  tk.StringVar(value=path),
            "frame":     None,
        }
        row = tk.Frame(self._presets_frame, bg=BG)
        row.pack(fill=tk.X, pady=2)
        row_data["frame"] = row

        tk.Label(row, text="Label", font=lf, bg=BG, fg=MUTED,
                 width=6, anchor="w").pack(side=tk.LEFT)
        make_entry(row, row_data["label_var"], mono, 14).pack(side=tk.LEFT)

        tk.Label(row, text="  Path", font=lf, bg=BG, fg=MUTED,
                 anchor="w").pack(side=tk.LEFT)
        make_entry(row, row_data["path_var"], mono, 34).pack(side=tk.LEFT, padx=(4, 0))

        def _browse_preset():
            p = filedialog.askopenfilename(
                initialdir=REPO_DIR,
                filetypes=[("All files", "*"), ("Markdown", "*.md")])
            if p:
                row_data["path_var"].set(p)

        tk.Button(row, text="…", font=lf, bg=SURFACE, fg=ACCENT,
                  relief=tk.FLAT, activebackground=BORDER, activeforeground=ACCENT,
                  padx=6, pady=2, cursor="hand2",
                  command=_browse_preset).pack(side=tk.LEFT, padx=(6, 0))

        def _remove():
            self._preset_rows.remove(row_data)
            row.destroy()

        tk.Button(row, text="✕", font=lf, bg=SURFACE, fg=RED,
                  relief=tk.FLAT, activebackground=BORDER, activeforeground=RED,
                  padx=6, pady=2, cursor="hand2",
                  command=_remove).pack(side=tk.LEFT, padx=(4, 0))

        self._preset_rows.append(row_data)

    # ── save / reset ──────────────────────────────────────────────────────────

    def _collect(self) -> dict:
        """Pull current widget values into a dict."""
        out = dict(self._cfg)
        for key, var in self._vars.items():
            out[key] = var.get()
        # Encode password fields before persisting — store base64, not plaintext
        for _k in ("bobshell_api_key", "ceph_tracker_api_key", "ceph_tracker_password"):
            out[_k] = _encode_key(out.get(_k, ""))
        # Username is plain text — no encoding needed
        out["presets"] = [
            [r["label_var"].get(), r["path_var"].get()]
            for r in self._preset_rows
            if r["label_var"].get().strip()
        ]
        return out

    def _save(self):
        updated = self._collect()
        self._cfg.update(updated)
        save_config(self._cfg)
        self._save_status.set("✓ Saved")
        self.after(3000, lambda: self._save_status.set(""))
        self._on_saved(self._cfg)

    def _reset(self):
        if tk.messagebox.askyesno("Reset config",
                                   "Reset all settings to defaults?",
                                   parent=self):
            self._cfg.update(DEFAULT_CONFIG)
            save_config(self._cfg)
            self._on_saved(self._cfg)
            # Rebuild the page with fresh defaults
            for w in self.winfo_children():
                w.destroy()
            self._vars.clear()
            self._preset_rows.clear()
            self._build()


# ── Launch page ───────────────────────────────────────────────────────────────

class LaunchPage(tk.Frame):
    """The original launch UI, now seeded from config."""

    def __init__(self, parent, cfg: dict, **kwargs):
        super().__init__(parent, bg=BG, **kwargs)
        self._cfg  = cfg
        self._proc = None

        self.var_local        = tk.BooleanVar(value=cfg.get("default_local", False))
        self.var_no_worktree  = tk.BooleanVar(value=cfg.get("default_no_worktrees", False))
        self.var_dry_run      = tk.BooleanVar(value=cfg.get("default_dry_run", True))
        self.var_claude_trust = tk.BooleanVar(value=cfg.get("claude_trust", True))
        self.instructions    = tk.StringVar(value=cfg.get("default_instructions", ""))
        self._ai_system      = cfg.get("ai_system", "bob")
        self._build()
        self.apply_theme(self._ai_system)

    def apply_config(self, cfg: dict):
        """Called when config is saved — refreshes tooltips, presets, and AI system."""
        self._cfg = cfg
        self._ai_system = cfg.get("ai_system", "bob")
        self.apply_theme(self._ai_system)
        self._refresh_run_button()
        # Rebuild the presets strip
        for w in self._presets_frame.winfo_children():
            w.destroy()
        self._build_presets()

    def apply_theme(self, ai_system: str):
        """Re-colour all surface/accent/border widgets to the chosen palette."""
        t = THEMES.get(ai_system, THEMES["bob"])
        surface = t["surface"]
        accent  = t["accent"]
        border  = t["border"]

        # Surface-coloured frames and labels
        for w in self._surface_widgets:
            try:
                w.config(bg=surface)
            except tk.TclError:
                pass

        # Accent-coloured buttons (Browse…, preset buttons)
        for w in self._accent_widgets:
            try:
                w.config(fg=accent, activeforeground=accent,
                         highlightbackground=border, activebackground=border)
            except tk.TclError:
                pass

        # ToggleButton: update accent/border colours and redraw
        for w in self._surface_widgets:
            if isinstance(w, ToggleButton):
                w._accent = accent
                w._border = border
                w.config(bg=surface)
                w._draw()

        # Separator lines
        for w in self._separator_widgets:
            try:
                w.config(bg=border)
            except tk.TclError:
                pass

        # Log terminal: border highlight and header tag colour
        self.log.config(highlightbackground=border,
                        selectbackground=border)
        self.log.tag_config("header", foreground=accent)

        # Clear button active colours
        self._clear_btn.config(activebackground=border)

        # Preset buttons (rebuilt each time, so re-apply accent via rebuild)
        for btn in self._presets_frame.winfo_children():
            try:
                btn.config(highlightbackground=border)
            except tk.TclError:
                pass

    # ── build ─────────────────────────────────────────────────────────────────

    def _build(self):
        mono = font.Font(family="Monospace", size=10)
        lf   = font.Font(family="Sans", size=10)

        # Widgets whose bg must track the theme surface colour
        self._surface_widgets:   list[tk.Widget] = []
        # Widgets whose fg/highlightbackground must track the theme accent colour
        self._accent_widgets:    list[tk.Widget] = []
        # Separator frames whose bg must track the theme border colour
        self._separator_widgets: list[tk.Widget] = []

        def _sw(w):
            """Register a widget as a surface-coloured widget and return it."""
            self._surface_widgets.append(w)
            return w

        def _sep():
            """Create a themed separator and register it."""
            s = tk.Frame(self, bg=BORDER, height=1)
            s.pack(fill=tk.X)
            self._separator_widgets.append(s)

        def toggle_row(parent, label_text, var, tooltip=""):
            row = _sw(tk.Frame(parent, bg=SURFACE, pady=4))
            row.pack(fill=tk.X)
            tb = ToggleButton(row, var, bg_color=SURFACE)
            tb.pack(side=tk.LEFT, padx=(0, 10))
            self._surface_widgets.append(tb)
            tk.Label(row, text=label_text, bg=SURFACE, fg=FG, font=lf).pack(side=tk.LEFT)
            self._surface_widgets.append(row.winfo_children()[-1])
            if tooltip:
                tk.Label(row, text=tooltip, bg=SURFACE, fg=MUTED,
                         font=font.Font(family="Sans", size=9)).pack(side=tk.LEFT, padx=(8, 0))
                self._surface_widgets.append(row.winfo_children()[-1])

        # ── options ────────────────────────────────────────────────────────────
        opts = _sw(tk.Frame(self, bg=SURFACE, padx=18, pady=12))
        opts.pack(fill=tk.X)
        _sep()

        remote_host = self._cfg.get("remote_host", "sockeni07")
        remote_user = self._cfg.get("remote_user", "szuraski")
        remote_str  = f"{remote_user}@{remote_host}"

        toggle_row(opts, "--local",        self.var_local,
                   f"Run agents locally instead of via SSH to {remote_str}")
        toggle_row(opts, "--no-worktrees", self.var_no_worktree,
                   "Use a single workspace instead of per-agent git worktrees")
        toggle_row(opts, "--dry-run",      self.var_dry_run,
                   "Print plan without starting any agents or writing files")

        _sep()

        # ── instructions file ──────────────────────────────────────────────────
        file_row = _sw(tk.Frame(self, bg=SURFACE, padx=18, pady=10))
        file_row.pack(fill=tk.X)

        lbl_inst = tk.Label(file_row, text="Instructions file:", bg=SURFACE, fg=FG, font=lf)
        lbl_inst.pack(side=tk.LEFT)
        self._surface_widgets.append(lbl_inst)

        tk.Entry(
            file_row, textvariable=self.instructions,
            bg="#11111b", fg=FG, insertbackground=FG, relief=tk.FLAT,
            highlightbackground=BORDER, highlightthickness=1,
            font=mono, width=52,
        ).pack(side=tk.LEFT, padx=(10, 8), ipady=4, fill=tk.X, expand=True)

        self._browse_btn = tk.Button(
            file_row, text="Browse…", font=lf,
            bg=SURFACE, fg=ACCENT, relief=tk.FLAT,
            activebackground=BORDER, activeforeground=ACCENT,
            padx=10, pady=4, cursor="hand2",
            highlightbackground=BORDER, highlightthickness=1,
            command=self._browse_instructions,
        )
        self._browse_btn.pack(side=tk.LEFT)
        self._surface_widgets.append(self._browse_btn)
        self._accent_widgets.append(self._browse_btn)

        # Quick-select presets strip
        self._presets_frame = _sw(tk.Frame(file_row, bg=SURFACE))
        self._presets_frame.pack(side=tk.LEFT, padx=(8, 0))
        self._build_presets()

        _sep()

        # ── run / stop buttons ─────────────────────────────────────────────────
        self._btn_bar = _sw(tk.Frame(self, bg=SURFACE, padx=18, pady=8))
        self._btn_bar.pack(fill=tk.X)

        self.btn_run = tk.Button(
            self._btn_bar, font=lf, bg=BTN_RUN, fg=BTN_FG, relief=tk.FLAT,
            activebackground=_tk_color(BTN_RUN, 0.15), activeforeground=BTN_FG,
            padx=16, pady=6, cursor="hand2", command=self._on_run,
        )
        self.btn_run.pack(side=tk.LEFT)

        self.btn_stop = tk.Button(
            self._btn_bar, text="■  Stop", font=lf,
            bg=RED, fg=BTN_FG, relief=tk.FLAT,
            activebackground=_tk_color(RED, 0.15), activeforeground=BTN_FG,
            padx=12, pady=6, cursor="hand2",
            command=self._on_stop, state=tk.DISABLED,
        )
        self.btn_stop.pack(side=tk.LEFT, padx=(8, 0))

        self.cmd_preview = tk.StringVar(value="")
        self._cmd_preview_lbl = tk.Label(
            self._btn_bar, textvariable=self.cmd_preview, bg=SURFACE, fg=MUTED,
            font=font.Font(family="Monospace", size=9))
        self._cmd_preview_lbl.pack(side=tk.LEFT, padx=(16, 0))
        self._surface_widgets.append(self._cmd_preview_lbl)

        self._refresh_run_button()
        self.var_dry_run.trace_add("write", lambda *_: self._refresh_run_button())
        self.var_local.trace_add("write", lambda *_: self._refresh_run_button())
        self.var_no_worktree.trace_add("write", lambda *_: self._refresh_run_button())
        self.instructions.trace_add("write", lambda *_: self._refresh_run_button())

        _sep()

        # ── log panel ─────────────────────────────────────────────────────────
        self._log_header = _sw(tk.Frame(self, bg=SURFACE, padx=18, pady=6))
        self._log_header.pack(fill=tk.X)
        self._log_header_lbl = tk.Label(
            self._log_header, text="⬛ Output", bg=SURFACE, fg=MUTED,
            font=font.Font(family="Sans", size=10, weight="bold"))
        self._log_header_lbl.pack(side=tk.LEFT)
        self._surface_widgets.append(self._log_header_lbl)
        self._clear_btn = tk.Button(
            self._log_header, text="Clear", font=font.Font(family="Sans", size=9),
            bg=SURFACE, fg=MUTED, relief=tk.FLAT,
            activebackground=BORDER, activeforeground=FG,
            padx=8, pady=2, cursor="hand2",
            command=self._clear_log)
        self._clear_btn.pack(side=tk.RIGHT)
        self._surface_widgets.append(self._clear_btn)

        log_frame = tk.Frame(self, bg=BG, padx=10, pady=8)
        log_frame.pack(fill=tk.BOTH, expand=True)

        self.log = scrolledtext.ScrolledText(
            log_frame, bg="#11111b", fg=FG, font=mono,
            relief=tk.FLAT, insertbackground=FG,
            selectbackground=BORDER, selectforeground=FG,
            wrap=tk.WORD, state=tk.DISABLED,
            highlightbackground=BORDER, highlightthickness=1,
        )
        self.log.pack(fill=tk.BOTH, expand=True)

        for tag, color in [("info", FG), ("success", GREEN), ("warn", YELLOW),
                            ("error", RED), ("muted", MUTED), ("header", ACCENT)]:
            self.log.tag_config(tag, foreground=color)

    def _build_presets(self):
        lf = font.Font(family="Sans", size=10)
        for lbl, path in self._cfg.get("presets", []):
            t = THEMES.get(self._ai_system, THEMES["bob"])
            tk.Button(
                self._presets_frame, text=lbl, font=lf,
                bg=t["border"], fg=FG, relief=tk.FLAT,
                activebackground=_tk_color(t["border"], 0.15), activeforeground=FG,
                padx=8, pady=4, cursor="hand2",
                command=lambda p=path: self.instructions.set(p),
            ).pack(side=tk.LEFT, padx=(4, 0))

    # ── helpers ───────────────────────────────────────────────────────────────

    def _build_cmd(self) -> list[str]:
        """Only used for the Bob path — Claude uses _launch_claude_agents directly."""
        cmd = ["bash", LAUNCH_SCRIPT]
        if self.var_local.get():
            cmd.append("--local")
        if self.var_no_worktree.get():
            cmd.append("--no-worktrees")
        if self.var_dry_run.get():
            cmd.append("--dry-run")
        p = self.instructions.get().strip()
        if p:
            cmd += ["--instructions", p]
        return cmd

    def _launch_claude_agents(self):
        """Write per-agent wrapper scripts and open each in a Tilix tab,
        mirroring exactly what launch-bob-agents.sh does for Bob."""
        import glob as _glob
        import shlex
        import tempfile

        is_local  = self.var_local.get()
        no_wt     = self.var_no_worktree.get()
        instr     = self.instructions.get().strip()

        remote_host = (f"{self._cfg.get('remote_user', 'szuraski')}@"
                       f"{self._cfg.get('remote_host', 'sockeni07')}")

        if is_local:
            workspace = self._cfg.get("local_workspace_root",
                                      DEFAULT_CONFIG["local_workspace_root"])
            main_dir  = self._cfg.get("local_main_dir",
                                      DEFAULT_CONFIG["local_main_dir"])
        else:
            workspace = self._cfg.get("remote_workspace_root",
                                      DEFAULT_CONFIG["remote_workspace_root"])
            main_dir  = self._cfg.get("remote_main_dir",
                                      DEFAULT_CONFIG["remote_main_dir"])

        # Collect (label, prompt_body) pairs — one per agent
        agents: list[tuple[str, str]] = []
        if instr and os.path.isdir(instr):
            for f in sorted(_glob.glob(os.path.join(instr, "*.md"))):
                body = self._resolve_prompt(f)
                agents.append((os.path.basename(f), body))
        elif instr and os.path.isfile(instr):
            body = self._resolve_prompt(instr)
            agents.append((os.path.basename(instr), body))

        if not agents:
            agents = [("interactive", "")]   # no instructions → plain claude session

        def log(msg, tag="info"):
            self.after(0, self._append_log, msg, tag)

        log(f"Launching {len(agents)} Claude Code agent(s) "
            f"{'locally' if is_local else 'on ' + remote_host}"
            f" from: {instr or '(interactive)'}\n\n")

        script_paths: list[str] = []

        for i, (label, prompt) in enumerate(agents, 1):
            if no_wt:
                wdir = main_dir
            else:
                wdir = f"{main_dir}-agent-{i}"
                # Fall back to main_dir if the worktree doesn't exist locally
                if is_local and not os.path.isdir(wdir):
                    log(f"  Agent #{i}: worktree {wdir} not found — using {main_dir}\n", "warn")
                    wdir = main_dir

            # Interactive TUI session — prompt is a positional arg so Claude opens
            # the TUI with it pre-submitted.
            # --permission-mode acceptEdits auto-approves file edits and skips the
            # folder trust dialog without bypassing shell-command permissions.
            perm_flag = "--permission-mode acceptEdits " if self.var_claude_trust.get() else ""
            if prompt:
                claude_cmd = f"claude {perm_flag}{shlex.quote(prompt)}"
            else:
                claude_cmd = f"claude {perm_flag}".rstrip()

            script_body = (
                "#!/usr/bin/env bash\n"
                f"cd {shlex.quote(wdir)}\n"
                f"{claude_cmd}\n"
                "exec bash\n"
            )

            script_path = f"/tmp/claude-agent-{i}.sh"

            if is_local:
                with open(script_path, "w") as fh:
                    fh.write(script_body)
                os.chmod(script_path, 0o700)
                log(f"  Agent #{i} ({label}): {script_path}\n", "muted")
            else:
                try:
                    result = subprocess.run(
                        ["ssh", remote_host,
                         f"cat > {shlex.quote(script_path)} && chmod +x {shlex.quote(script_path)}"],
                        input=script_body, text=True, capture_output=True,
                    )
                    if result.returncode != 0:
                        log(f"  Agent #{i}: failed to copy script — {result.stderr.strip()}\n",
                            "error")
                        continue
                    log(f"  Agent #{i} ({label}): {remote_host}:{script_path}\n", "muted")
                except Exception as exc:
                    log(f"  Agent #{i}: {exc}\n", "error")
                    continue

            script_paths.append((i, script_path))

        if not script_paths:
            log("\nNo agent scripts written — aborting.\n", "error")
            return

        # Open first agent in a new Tilix window, remaining in new sessions
        def tab_cmd(script: str) -> str:
            if is_local:
                return f"bash {shlex.quote(script)}"
            return f"ssh -t {shlex.quote(remote_host)} bash {shlex.quote(script)}"

        import time
        first_idx, first_script = script_paths[0]
        subprocess.Popen(
            ["tilix", "--action=app-new-window",
             "-e", f"bash -c {shlex.quote(tab_cmd(first_script))}"]
        )
        log(f"\nOpened Tilix window for Agent #{first_idx}\n", "success")

        for idx, script in script_paths[1:]:
            time.sleep(0.5)
            subprocess.Popen(
                ["tilix", "--action=app-new-session",
                 "-e", f"bash -c {shlex.quote(tab_cmd(script))}"]
            )
            log(f"Opened Tilix session for Agent #{idx}\n", "success")

        log("\n✓ All agents launched.\n", "success")

    def _resolve_prompt(self, path: str) -> str:
        """Return body text from a file or the first *.md in a directory.

        Strips YAML-style frontmatter (--- … ---) matching the same logic
        as launch-bob-agents.sh so the raw tracker/metadata block is never
        passed to the AI CLI.
        """
        import glob as _glob

        def _strip_frontmatter(text: str) -> str:
            lines = text.splitlines()
            if not lines or lines[0].strip() != "---":
                return text.strip()
            # Find closing ---
            for i, line in enumerate(lines[1:], 1):
                if line.strip() == "---":
                    body = "\n".join(lines[i + 1:]).strip()
                    return body
            return text.strip()  # no closing fence — return as-is

        def _read(filepath: str) -> str:
            try:
                with open(filepath) as fh:
                    return _strip_frontmatter(fh.read())
            except Exception:
                return ""

        if not path:
            return ""
        if os.path.isfile(path):
            return _read(path)
        if os.path.isdir(path):
            for f in sorted(_glob.glob(os.path.join(path, "*.md"))):
                text = _read(f)
                if text:
                    return text
        return ""

    def _refresh_run_button(self):
        cmd = self._build_cmd()
        is_claude = self._ai_system == "claude"
        t = THEMES.get(self._ai_system, THEMES["bob"])
        if self.var_dry_run.get():
            label = "▶  Run Dry-Run"
            self.btn_run.config(text=label, bg=t["btn_run"], fg=BTN_FG,
                                activebackground=_tk_color(t["btn_run"], 0.15))
        else:
            label = "🤖  Launch Claude Agents" if is_claude else "🚀  Launch Bob Agents"
            color = t["btn_run"] if is_claude else GREEN
            self.btn_run.config(text=label, bg=color, fg=BTN_FG,
                                activebackground=_tk_color(color, 0.15))
        # Show compact command preview
        short = " ".join(os.path.basename(c) if i == 1 else c
                         for i, c in enumerate(cmd))
        self.cmd_preview.set(short)

    def _browse_instructions(self):
        current = self.instructions.get().strip()
        initial = current if os.path.isdir(current) else (
            os.path.dirname(current) if current else REPO_DIR)
        # Prefer directory selection (one folder = N agents)
        path = filedialog.askdirectory(
            initialdir=initial,
            title="Select prompts folder (each .md = one agent)",
        )
        if not path:
            # Fall back to single-file for legacy formats
            path = filedialog.askopenfilename(
                initialdir=initial,
                title="Select instructions file (legacy)",
                filetypes=[("All files", "*"), ("Markdown", "*.md"), ("Text", "*.txt")],
            )
        if path:
            self.instructions.set(path)

    def _clear_log(self):
        self.log.config(state=tk.NORMAL)
        self.log.delete("1.0", tk.END)
        self.log.config(state=tk.DISABLED)

    def _append_log(self, text: str, tag: str = "info"):
        self.log.config(state=tk.NORMAL)
        self.log.insert(tk.END, text, tag)
        self.log.see(tk.END)
        self.log.config(state=tk.DISABLED)

    def _set_busy(self, busy: bool):
        self.btn_run.config(state=tk.DISABLED if busy else tk.NORMAL)
        self.btn_stop.config(state=tk.NORMAL if busy else tk.DISABLED)

    # ── actions ───────────────────────────────────────────────────────────────

    def _on_stop(self):
        if self._proc and self._proc.poll() is None:
            self._proc.terminate()
            self._append_log("\n[Stopped by user]\n", "warn")

    def _on_run(self):
        self._clear_log()
        self._set_busy(True)

        # Dry-run: print plan in-process for both AI systems so the output
        # always clearly states which tool would be used.
        if self.var_dry_run.get():
            self._print_dry_run()
            self._set_busy(False)
            return

        if self._ai_system == "claude":
            # Claude: write wrapper scripts and open Tilix tabs directly
            threading.Thread(target=self._launch_claude_agents_thread, daemon=True).start()
        else:
            # Bob: run launch-bob-agents.sh via subprocess
            cmd = self._build_cmd()
            self._append_log("$ " + " ".join(cmd) + "\n\n", "muted")

            env = os.environ.copy()

            # Inject stored credentials — env vars already set take precedence
            def _inject(env_var: str, cfg_key: str, is_password: bool = True):
                if not env.get(env_var):
                    val = _decode_key(self._cfg.get(cfg_key, "")) if is_password \
                          else self._cfg.get(cfg_key, "")
                    if val:
                        env[env_var] = val

            _inject("BOBSHELL_API_KEY",      "bobshell_api_key")
            _inject("CEPH_TRACKER_API_KEY",   "ceph_tracker_api_key")
            _inject("CEPH_TRACKER_USERNAME",  "ceph_tracker_username", is_password=False)
            _inject("CEPH_TRACKER_PASSWORD",  "ceph_tracker_password")

            # Push remote_host / remote_user into the script's environment
            env["BOB_REMOTE_HOST"] = (
                f"{self._cfg.get('remote_user', 'szuraski')}@"
                f"{self._cfg.get('remote_host', 'sockeni07')}"
            )

            threading.Thread(target=self._run_process, args=(cmd, env), daemon=True).start()

    def _launch_claude_agents_thread(self):
        """Thread wrapper for _launch_claude_agents — restores busy state when done."""
        try:
            self._launch_claude_agents()
        except Exception as exc:
            self.after(0, self._append_log, f"\n[Error] {exc}\n", "error")
        finally:
            self.after(0, self._set_busy, False)

    def _print_dry_run(self):
        """Print a human-readable dry-run plan to the log, naming the AI system."""
        import glob as _glob

        ai      = self._ai_system          # "bob" or "claude"
        is_local = self.var_local.get()
        no_wt    = self.var_no_worktree.get()
        instr    = self.instructions.get().strip()

        remote_host = (f"{self._cfg.get('remote_user', 'szuraski')}@"
                       f"{self._cfg.get('remote_host', 'sockeni07')}")

        if is_local:
            workspace = self._cfg.get("local_workspace_root",
                                       DEFAULT_CONFIG["local_workspace_root"])
            main_dir  = self._cfg.get("local_main_dir",
                                       DEFAULT_CONFIG["local_main_dir"])
            mode_str  = "Local (no SSH)"
        else:
            workspace = self._cfg.get("remote_workspace_root",
                                       DEFAULT_CONFIG["remote_workspace_root"])
            main_dir  = self._cfg.get("remote_main_dir",
                                       DEFAULT_CONFIG["remote_main_dir"])
            mode_str  = f"Remote ({remote_host})"

        # Collect prompt files (reuse _resolve_prompt's frontmatter stripping)
        agents: list[tuple[str, str]] = []  # [(label, prompt_body), …]
        if instr and os.path.isdir(instr):
            for f in sorted(_glob.glob(os.path.join(instr, "*.md"))):
                body = self._resolve_prompt(f) or "(unreadable)"
                agents.append((os.path.basename(f), body))
        elif instr and os.path.isfile(instr):
            body = self._resolve_prompt(instr) or "(unreadable)"
            agents.append((os.path.basename(instr), body))

        if not agents:
            agents = [("(interactive)", "")]

        ai_label = "Claude Code  (claude)" if ai == "claude" else "Bob  (bob run / bob chat)"
        w_str    = "Disabled (single workspace)" if no_wt else "Enabled (agent-1..N)"
        src_str  = ("Directory  " + instr if os.path.isdir(instr)
                    else "File  " + instr if instr else "(none)")

        sep  = "=" * 60
        dash = "-" * 60

        lines = [
            (sep, "header"),
            (f"  DRY RUN — Agent Orchestration Plan", "warn"),
            (sep, "header"),
            (f"  AI System:         {ai_label}", "info"),
            (f"  Mode:              {mode_str}", "info"),
            (f"  Worktrees:         {w_str}", "info"),
            (f"  Instructions:      {src_str}", "info"),
            (f"  Total Agents:      {len(agents)}", "info"),
            (f"  Workspace Root:    {workspace}", "info"),
            (f"  Main Directory:    {main_dir}", "info"),
            (sep, "header"),
            ("", "info"),
        ]

        for i, (label, prompt) in enumerate(agents, 1):
            if no_wt:
                wdir   = main_dir
                branch = "(n/a — no worktrees)"
            else:
                wdir   = f"{main_dir}-agent-{i}"
                branch = f"agent/{i}"

            preview = (prompt[:120] + "…") if len(prompt) > 120 else prompt
            if ai == "claude":
                perm_flag = "--permission-mode acceptEdits " if self.var_claude_trust.get() else ""
                cmd_str = (f"claude {perm_flag}'{prompt[:80]}…'"
                           if prompt else f"claude {perm_flag}# interactive".rstrip())
            else:
                cmd_str = (f"bob run --max-turns 10000 -w '{workspace}' -- '{prompt[:80]}…'"
                           if prompt else f"bob chat -w '{workspace}'")

            lines += [
                (dash, "header"),
                (f"  Agent #{i}  —  {label}", "info"),
                (dash, "header"),
                (f"  Working Dir:  {wdir}", "info"),
                (f"  Branch:       {branch}", "info"),
            ]
            if prompt:
                lines.append((f"  Prompt:       {preview}", "muted"))
            lines += [
                (f"  Command:      {cmd_str}", "muted"),
                ("", "info"),
            ]

        lines += [
            (sep, "header"),
            ("  Dry run complete. No processes started, no files written.", "warn"),
            ("", "info"),
        ]

        for text, tag in lines:
            self._append_log(text + "\n", tag)

    def _run_process(self, cmd: list, env: dict):
        try:
            self._proc = subprocess.Popen(
                cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, bufsize=1, env=env,
            )
            for line in self._proc.stdout:
                tag = self._classify(line)
                self.after(0, self._append_log, line, tag)
            self._proc.wait()
            rc = self._proc.returncode
            if rc == 0:
                self.after(0, self._append_log, "\n✓ Finished (exit 0)\n", "success")
            else:
                self.after(0, self._append_log, f"\n✗ Exited with code {rc}\n", "error")
        except Exception as exc:
            self.after(0, self._append_log, f"\n[Error] {exc}\n", "error")
        finally:
            self.after(0, self._set_busy, False)

    @staticmethod
    def _classify(line: str) -> str:
        s = line.strip()
        if s.startswith("=====") or s.startswith("-----"):
            return "header"
        if s.startswith("✓") or "complete" in s.lower():
            return "success"
        if s.startswith("Error") or s.startswith("✗"):
            return "error"
        if "DRY RUN" in s or s.startswith("Dry run"):
            return "warn"
        if s.startswith("#") or s.startswith("$"):
            return "muted"
        return "info"


# ── root window ───────────────────────────────────────────────────────────────

class BobAgentsGUI(tk.Tk):

    def __init__(self):
        super().__init__()
        self.title("Bob Agent Launcher")
        # WM_CLASS must match StartupWMClass in the .desktop file so GNOME
        # associates the running window with the right taskbar icon.
        self.tk.call("wm", "attributes", ".", "-type", "normal")
        self.wm_resizable(True, True)
        try:
            self.tk.call("tk", "appname", "bob-agents-gui")
        except Exception:
            pass
        self.configure(bg=BG)
        self.resizable(True, True)
        self.minsize(860, 600)

        self._cfg = load_config()
        self._build_ui()

        # Apply window icon immediately and re-apply after mapping
        self._apply_icon()
        self.after(100, self._apply_icon)

    def _apply_icon(self):
        """Set window icon via wm_iconphoto and _NET_WM_ICON via xprop (GNOME/X11)."""
        logo_path = _resolve_resource("logo.png")
        if not os.path.isfile(logo_path):
            logo_path = _resolve_resource("logo.gif")
        if not os.path.isfile(logo_path):
            return

        pil_img = None
        # ── wm_iconphoto (title-bar & dock decoration) ─────────────────────
        try:
            from PIL import Image, ImageTk
            pil_img = Image.open(logo_path).convert("RGBA")
            self._logo = ImageTk.PhotoImage(pil_img)
        except Exception:
            try:
                self._logo = tk.PhotoImage(file=logo_path)
            except Exception:
                self._logo = None
        if self._logo:
            try:
                self.wm_iconphoto(True, self._logo)
            except Exception:
                pass

        # ── _NET_WM_ICON via xprop (GNOME/X11 taskbar & alt-tab) ────────────
        if pil_img:
            try:
                icon = pil_img.resize((48, 48), Image.LANCZOS)
                w, h = icon.size
                raw = icon.tobytes()  # flat RGBA bytes, 4 bytes per pixel
                # _NET_WM_ICON format: width, height, then ARGB card32 values
                data = [w, h] + [
                    ((raw[i+3] << 24) | (raw[i] << 16) | (raw[i+1] << 8) | raw[i+2])
                    for i in range(0, len(raw), 4)
                ]
                wid = hex(self.winfo_id())
                csv = ",".join(str(v) for v in data)
                subprocess.Popen(
                    ["xprop", "-id", wid,
                     "-f", "_NET_WM_ICON", "32c",
                     "-set", "_NET_WM_ICON", csv],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                )
            except Exception:
                pass

    def _build_ui(self):
        tf = font.Font(family="Sans", size=16, weight="bold")
        uf = font.Font(family="Sans", size=10)

        # ── header ─────────────────────────────────────────────────────────────
        self._header_frame = tk.Frame(self, bg=SURFACE, pady=10, padx=18)
        self._header_frame.pack(fill=tk.X)
        self._header_label = tk.Label(self._header_frame, text="Bob Agent Launcher",
                                      font=tf, bg=SURFACE, fg=FG)
        self._header_label.pack(side=tk.LEFT)

        # ── tab strip ──────────────────────────────────────────────────────────
        self._tabs = TabStrip(self, ["Launch", "Config"], self._switch_tab)
        self._tabs.pack(fill=tk.X)
        self._tab_sep = tk.Frame(self, bg=BORDER, height=1)
        self._tab_sep.pack(fill=tk.X)

        # ── pages ──────────────────────────────────────────────────────────────
        self._launch_page = LaunchPage(self, self._cfg)
        self._config_page = ConfigPage(self, self._cfg, on_saved=self._on_config_saved,
                                       on_ai_system_change=self._on_ai_system_change)

        self._launch_page.pack(fill=tk.BOTH, expand=True)

        # ── status bar ─────────────────────────────────────────────────────────
        self._status = tk.StringVar(value=f"Config: {CONFIG_PATH}")
        self._status_bar = tk.Frame(self, bg=SURFACE, padx=18, pady=4)
        self._status_bar.pack(fill=tk.X, side=tk.BOTTOM)
        self._status_label = tk.Label(self._status_bar, textvariable=self._status,
                                      bg=SURFACE, fg=MUTED,
                                      font=font.Font(family="Sans", size=9))
        self._status_label.pack(side=tk.LEFT)

        self._active_tab = "Launch"

        # Apply initial theme in case config already has Claude selected
        self._apply_theme(self._cfg.get("ai_system", "bob"))

    def _apply_theme(self, ai_system: str):
        """Re-colour chrome widgets (header, tab strip, status bar) for the AI system."""
        t = THEMES.get(ai_system, THEMES["bob"])
        surface = t["surface"]
        accent  = t["accent"]
        border  = t["border"]

        for w in (self._header_frame, self._header_label,
                  self._tabs,
                  self._status_bar, self._status_label):
            try:
                w.config(bg=surface)
            except tk.TclError:
                pass

        # Tab strip button backgrounds and active tab underline bar
        for lbl in self._tabs._btns.values():
            lbl.config(bg=surface)
            if hasattr(lbl, "_bar"):
                lbl._bar.config(bg=accent)

        # Tab-to-content separator
        self._tab_sep.config(bg=border)

    def _switch_tab(self, name: str):
        if name == self._active_tab:
            return
        self._active_tab = name
        if name == "Launch":
            self._config_page.pack_forget()
            self._launch_page.pack(fill=tk.BOTH, expand=True)
        else:
            self._launch_page.pack_forget()
            self._config_page.pack(fill=tk.BOTH, expand=True)

    def _on_ai_system_change(self, value: str):
        """Called immediately when the AI System radio is toggled — no save needed."""
        self._cfg["ai_system"] = value
        self._launch_page.apply_config(self._cfg)
        self._apply_theme(value)

    def _on_config_saved(self, cfg: dict):
        self._cfg = cfg
        self._launch_page.apply_config(cfg)
        self._apply_theme(cfg.get("ai_system", "bob"))
        self._status.set(f"Config saved → {CONFIG_PATH}")
        self.after(4000, lambda: self._status.set(f"Config: {CONFIG_PATH}"))


# ── entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    app = BobAgentsGUI()
    app.mainloop()

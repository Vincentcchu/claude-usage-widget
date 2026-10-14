# PyInstaller recipe for the collector helper bundled in Claude Usage.app.
# Built by macos/build.sh; run from the repo root's build venv.
# -*- mode: python ; coding: utf-8 -*-
import os

from PyInstaller.utils.hooks import collect_data_files, collect_submodules

import claude_usage

here = os.path.abspath(SPECPATH)
bundle_id = os.environ.get("COLLECTOR_BUNDLE_ID", "dev.claudeusage.ClaudeUsage.Collector")

a = Analysis(
    [os.path.join(here, "collector_main.py")],
    datas=collect_data_files("claude_usage"),
    # Skins and other modules are imported by name at runtime.
    hiddenimports=collect_submodules("claude_usage"),
    # Qt modules the widget never touches; dropping them keeps the app small.
    excludes=["tkinter", "PySide6.QtNetwork", "PySide6.QtQml", "PySide6.QtQuick",
              "PySide6.QtSql", "PySide6.QtTest", "PySide6.QtOpenGL",
              "PySide6.QtDBus", "PySide6.QtConcurrent", "PySide6.QtXml"],
)
pyz = PYZ(a.pure)
exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="ClaudeUsageCollector",
    console=False,
    argv_emulation=False,
    codesign_identity=None,
)
coll = COLLECT(exe, a.binaries, a.datas, name="ClaudeUsageCollector")
app = BUNDLE(
    coll,
    name="ClaudeUsageCollector.app",
    bundle_identifier=bundle_id,
    version=claude_usage.__version__,
    info_plist={
        # Background helper: no Dock icon, no menu bar of its own.
        "LSUIElement": True,
        "NSHighResolutionCapable": True,
    },
)

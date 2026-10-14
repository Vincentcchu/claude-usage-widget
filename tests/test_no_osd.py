"""Tests for running the app without the overlay (``--no-osd``).

The macOS menu bar app runs the collector this way: everything works except
the overlay, which must never appear and must not have its saved visibility
changed. Uses Qt's offscreen platform so the tests run headless on CI.
"""

from __future__ import annotations

import os
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

import copy
import json

import pytest
from PySide6.QtWidgets import QApplication

from claude_usage import widget
from claude_usage.config import DEFAULT_CONFIG


@pytest.fixture
def app_factory(tmp_path, monkeypatch):
    """Build a ClaudeUsageApp with network work stubbed out and the config
    file redirected into tmp_path."""
    QApplication.instance() or QApplication([])
    monkeypatch.setenv("XDG_CONFIG_HOME", str(tmp_path / "config"))
    # No usage collection or GitHub release check from a unit test.
    monkeypatch.setattr(widget.ClaudeUsageApp, "_refresh_async", lambda self: None)
    monkeypatch.setattr(widget.ClaudeUsageApp, "_check_update", lambda self: None)
    # Quitting must not stop the shared QApplication other tests use.
    monkeypatch.setattr(QApplication, "quit", lambda *a: None)
    created = []

    def make(show_osd: bool, **overrides):
        cfg = copy.deepcopy(DEFAULT_CONFIG)
        cfg["claude_dir"] = str(tmp_path / "claude")
        cfg.update(overrides)
        app = widget.ClaudeUsageApp(cfg, show_osd=show_osd)
        created.append(app)
        return app

    yield make
    for app in created:
        app._alive = False
        app._timer.stop()
        app.overlay.hide()


def test_overlay_is_shown_by_default(app_factory):
    app = app_factory(show_osd=True)
    assert app.overlay.isVisible()


def test_no_osd_never_shows_the_overlay(app_factory):
    app = app_factory(show_osd=False)
    assert not app.overlay.isVisible()


def test_no_osd_quit_leaves_saved_visibility_alone(app_factory, tmp_path):
    app = app_factory(show_osd=False, osd_visible=True)
    app._on_quit()
    assert app.config["osd_visible"] is True
    # Nothing was written: a headless run has no overlay state to save.
    saved = tmp_path / "config" / "claude-usage" / "config.json"
    if saved.exists():
        assert json.loads(saved.read_text()).get("osd_visible", True) is True

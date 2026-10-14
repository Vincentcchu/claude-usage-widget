"""Entry point for the bundled collector inside Claude Usage.app.

The Swift app launches this helper in the background with ``--no-osd``: the
regular claude-usage collector, notifications and webhooks, with no overlay
and no Dock icon. Its localhost API server feeds the menu bar item and the
widget.
"""

import sys

from claude_usage.cli import main

if __name__ == "__main__":
    sys.exit(main())

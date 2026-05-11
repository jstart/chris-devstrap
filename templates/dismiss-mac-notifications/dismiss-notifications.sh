#!/usr/bin/env bash
# Runs JXA UI automation to dismiss visible Notification Center notifications.
# Grant Accessibility to Terminal, iTerm, Shortcuts, or Automator when prompted.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec osascript -l JavaScript "${SCRIPT_DIR}/dismiss-notifications.jxa"

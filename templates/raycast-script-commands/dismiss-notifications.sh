#!/bin/bash
#
# Raycast Script Command — calls the chris-devstrap dismiss helper installed by scripts/zsh.sh.
# Drop the parent directory into Raycast Settings → Extensions → Script Commands → User Folder.
# Recommended hotkey: ⌘⌃Z (Command + Control + Z). Assign in Raycast Settings.
#
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Dismiss Mac Notifications
# @raycast.mode silent
#
# Optional parameters:
# @raycast.icon 🔕
# @raycast.packageName chris-devstrap
# @raycast.description Dismiss every visible Notification Center notification via JXA UI automation. First run prompts for Accessibility permission for Raycast.
# @raycast.author chris-devstrap
# @raycast.authorURL https://github.com/jstart/chris-devstrap

set -euo pipefail
exec "${HOME}/bin/DismissMacNotifications/dismiss-notifications.sh"

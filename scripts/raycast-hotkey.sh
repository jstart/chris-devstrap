#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

step_start "Spotlight shortcut (free Cmd+Space for Raycast)"
PLIST="${HOME}/Library/Preferences/com.apple.symbolichotkeys.plist"

if [[ -f "$PLIST" ]]; then
  if /usr/libexec/PlistBuddy -c "Print :AppleSymbolicHotKeys:64:enabled" "$PLIST" &>/dev/null; then
    if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
      chris_run /usr/libexec/PlistBuddy -c "Set :AppleSymbolicHotKeys:64:enabled false" "$PLIST"
    else
      /usr/libexec/PlistBuddy -c "Set :AppleSymbolicHotKeys:64:enabled false" "$PLIST" 2>/dev/null || true
    fi
    step_ok "AppleSymbolicHotKeys:64 enabled → false (Spotlight search shortcut)."
  else
    step_warn "Shortcut plist present but key 64 not found — skip automated Spotlight disable."
    chris_manual_todo "Free ⌘Space for Raycast: System Settings → Keyboard → Keyboard Shortcuts → Spotlight (change or disable Show Spotlight search)."
  fi
else
  step_warn "No $PLIST yet — log in once, then re-run bootstrap or disable Spotlight shortcut manually."
  chris_manual_todo "After first login: System Settings → Keyboard → Keyboard Shortcuts → Spotlight so Raycast can use ⌘Space."
fi

step_start "Apply preference daemon refresh"
if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
  chris_run killall SystemUIServer
  chris_run killall cfprefsd
else
  killall SystemUIServer cfprefsd 2>/dev/null || true
fi

chris_manual_todo "Raycast → Settings → General → Hotkey → Command+Space."
chris_manual_todo "Raycast → Settings → AI → turn off the global switch (top right) to disable Raycast AI (no supported defaults key; use the app UI)."
chris_manual_todo "Raycast → Settings → Extensions: uncheck \"Enabled\" for extensions, groups, or commands you do not want (no supported CLI)."
chris_manual_todo "Screenshot shutter sound: System Settings → Sound → Sound Effects → turn off \"Play sound effects…\" (all UI sounds). Or run bootstrap with CHRIS_DEVSTRAP_SILENCE_UI_SOUNDS=1 to set the same via defaults."
chris_manual_todo "Raycast → Extensions → Window Management: Left Half ⌘⌃←, Right Half ⌘⌃→, Maximize ⌘⌃Space (names may vary)."
chris_manual_todo "Raycast → Extensions → Clipboard History: hotkey ⌘⇧C."
chris_manual_todo "System Settings → Privacy & Security: allow Raycast Accessibility (and Screen Recording if asked) for window commands."

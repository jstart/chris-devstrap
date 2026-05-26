#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

CHRIS_DEVSTRAP_DEFAULTS_CHANGED=0
export CHRIS_DEVSTRAP_DEFAULTS_CHANGED

step_start "Spotlight shortcut (free Cmd+Space for Raycast)"
PLIST="${HOME}/Library/Preferences/com.apple.symbolichotkeys.plist"

if [[ -f "$PLIST" ]]; then
  if /usr/libexec/PlistBuddy -c "Print :AppleSymbolicHotKeys:64:enabled" "$PLIST" &>/dev/null; then
    # A7: read current value before writing — skip plist mutation + daemon restart when already false.
    _chris_spotlight_enabled="$(/usr/libexec/PlistBuddy -c "Print :AppleSymbolicHotKeys:64:enabled" "$PLIST" 2>/dev/null || echo "")"
    if [[ "$_chris_spotlight_enabled" == "false" ]]; then
      step_ok "AppleSymbolicHotKeys:64 already disabled — skipping Spotlight write + daemon restart."
    else
      if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
        chris_run /usr/libexec/PlistBuddy -c "Set :AppleSymbolicHotKeys:64:enabled false" "$PLIST"
      else
        /usr/libexec/PlistBuddy -c "Set :AppleSymbolicHotKeys:64:enabled false" "$PLIST" 2>/dev/null || true
      fi
      CHRIS_DEVSTRAP_DEFAULTS_CHANGED=1
      step_ok "AppleSymbolicHotKeys:64 enabled → false (Spotlight search shortcut)."
    fi
  else
    step_warn "Shortcut plist present but key 64 not found — skip automated Spotlight disable."
    chris_manual_todo "Free ⌘Space for Raycast: System Settings → Keyboard → Keyboard Shortcuts → Spotlight (change or disable Show Spotlight search)."
  fi
else
  step_warn "No $PLIST yet — log in once, then re-run bootstrap or disable Spotlight shortcut manually."
  chris_manual_todo "After first login: System Settings → Keyboard → Keyboard Shortcuts → Spotlight so Raycast can use ⌘Space."
fi

# A2: only bounce SystemUIServer + cfprefsd when we actually wrote the plist.
chris_killall_if_changed SystemUIServer cfprefsd

chris_manual_todo_block "Raycast setup:" \
  "  General → Hotkey → ⌘Space" \
  "  AI → off (global switch)" \
  "  Extensions → disable rows you do not need" \
  "  Window Management: Left ⌘⌃← / Right ⌘⌃→ / Maximize ⌘⌃Space" \
  "  Clipboard History ⌘⇧C" \
  "  System Settings → Privacy & Security → Accessibility (+ Screen Recording if asked)" \
  "  UI sounds: silenced by bootstrap unless CHRIS_DEVSTRAP_SILENCE_UI_SOUNDS=0"

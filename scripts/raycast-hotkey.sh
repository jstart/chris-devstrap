#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

CHRIS_DEVSTRAP_DEFAULTS_CHANGED=0
export CHRIS_DEVSTRAP_DEFAULTS_CHANGED

step_start "Spotlight shortcut (free Cmd+Space for Raycast)"
PLIST="${HOME}/Library/Preferences/com.apple.symbolichotkeys.plist"

# Disable AppleSymbolicHotKeys:64 (Show Spotlight search). On a fresh Mac the key
# often does not exist until Keyboard settings are opened — create the full entry.
_chris_spotlight_disable_key64() {
  local plist="$1"
  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
    chris_run /usr/libexec/PlistBuddy -c "Set :AppleSymbolicHotKeys:64:enabled false" "$plist"
    return 0
  fi

  # Delete any partial/existing 64 entry, then add disabled Spotlight binding.
  # parameters (65535, 49, 1048576) match a disabled ⌘Space Spotlight entry.
  /usr/libexec/PlistBuddy -c "Delete :AppleSymbolicHotKeys:64" "$plist" >/dev/null 2>&1 || true
  if /usr/libexec/PlistBuddy \
    -c "Add :AppleSymbolicHotKeys:64 dict" \
    -c "Add :AppleSymbolicHotKeys:64:enabled bool false" \
    -c "Add :AppleSymbolicHotKeys:64:value dict" \
    -c "Add :AppleSymbolicHotKeys:64:value:parameters array" \
    -c "Add :AppleSymbolicHotKeys:64:value:parameters: integer 65535" \
    -c "Add :AppleSymbolicHotKeys:64:value:parameters: integer 49" \
    -c "Add :AppleSymbolicHotKeys:64:value:parameters: integer 1048576" \
    -c "Add :AppleSymbolicHotKeys:64:value:type string standard" \
    "$plist" 2>/dev/null; then
    return 0
  fi
  # Fallback: enabled-only entry (still frees the chord on many macOS versions).
  /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys:64:enabled bool false" "$plist" 2>/dev/null ||
    /usr/libexec/PlistBuddy -c "Set :AppleSymbolicHotKeys:64:enabled false" "$plist" 2>/dev/null
}

if [[ -f "$PLIST" ]]; then
  _chris_spotlight_enabled="$(/usr/libexec/PlistBuddy -c "Print :AppleSymbolicHotKeys:64:enabled" "$PLIST" 2>/dev/null || echo "")"
  if [[ "$_chris_spotlight_enabled" == "false" ]]; then
    step_ok "AppleSymbolicHotKeys:64 already disabled — skipping Spotlight write + daemon restart."
  else
    if [[ -z "$_chris_spotlight_enabled" ]]; then
      step_info "AppleSymbolicHotKeys:64 missing (common on fresh Mac) — creating disabled Spotlight entry."
    fi
    if _chris_spotlight_disable_key64 "$PLIST"; then
      CHRIS_DEVSTRAP_DEFAULTS_CHANGED=1
      step_ok "AppleSymbolicHotKeys:64 enabled → false (Spotlight search shortcut)."
    else
      step_warn "Could not write AppleSymbolicHotKeys:64 — disable Spotlight ⌘Space manually."
      chris_manual_todo "Free ⌘Space for Raycast: System Settings → Keyboard → Keyboard Shortcuts → Spotlight (change or disable Show Spotlight search)."
    fi
  fi
else
  step_warn "No $PLIST yet — creating plist with Spotlight ⌘Space disabled."
  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
    chris_run mkdir -p "$(dirname "$PLIST")"
    chris_run /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys dict" "$PLIST"
  else
    mkdir -p "$(dirname "$PLIST")"
    # Ensure parent dict exists for a brand-new plist.
    /usr/libexec/PlistBuddy -c "Add :AppleSymbolicHotKeys dict" "$PLIST" 2>/dev/null || true
    if _chris_spotlight_disable_key64 "$PLIST"; then
      CHRIS_DEVSTRAP_DEFAULTS_CHANGED=1
      step_ok "Created $PLIST with AppleSymbolicHotKeys:64 disabled."
    else
      step_warn "Could not create Spotlight hotkey entry — disable manually after first login."
      chris_manual_todo "After first login: System Settings → Keyboard → Keyboard Shortcuts → Spotlight so Raycast can use ⌘Space."
    fi
  fi
fi

# A2: only bounce SystemUIServer + cfprefsd when we actually wrote the plist.
chris_killall_if_changed SystemUIServer cfprefsd

# Best-effort apply without logout (private framework; ignore if missing).
if [[ "${CHRIS_DEVSTRAP_DEFAULTS_CHANGED:-0}" == "1" ]] && [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" != 1 ]]; then
  if [[ -x /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings ]]; then
    /System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u >/dev/null 2>&1 || true
  fi
fi

chris_manual_todo_block "Raycast setup:" \
  "  General → Hotkey → ⌘Space" \
  "  AI → off (global switch)" \
  "  Extensions → disable rows you do not need" \
  "  Window Management: Left ⌘⌃← / Right ⌘⌃→ / Maximize ⌘⌃Space" \
  "  Clipboard History ⌘⇧C" \
  "  System Settings → Privacy & Security → Accessibility (+ Screen Recording if asked)" \
  "  UI sounds: silenced by bootstrap unless CHRIS_DEVSTRAP_SILENCE_UI_SOUNDS=0"

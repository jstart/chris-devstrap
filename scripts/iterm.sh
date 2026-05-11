#!/usr/bin/env bash
# End of bootstrap: open Raycast, Cursor, iTerm (when installed) and print iTerm keybinding hints.
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

_open_app() {
  # Usage: _open_app "DisplayName" /path/To.app [path_passed_to_open]
  local name="$1" bundle="$2" pass="${3:-}"
  local app_name
  app_name="$(basename "$bundle" .app)"

  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
    if [[ -n "$pass" ]]; then
      chris_run open -a "$app_name" "$pass"
    else
      chris_run open -a "$app_name"
    fi
    return 0
  fi

  if [[ ! -d "$bundle" ]]; then
    step_warn "${name} not found at ${bundle} — skip open (install via Brewfile if expected)."
    chris_manual_todo "Install ${name} (brew bundle), then: open -a \"${app_name}\""
    return 0
  fi

  if [[ -n "$pass" ]]; then
    open -a "$app_name" "$pass" 2>/dev/null || open -a "$app_name"
  else
    open -a "$app_name" 2>/dev/null || true
  fi
  step_ok "Opened ${name}"
}

_main() {
  hr
  step_start "Open Raycast, Cursor, iTerm (end of bootstrap)"

  step_info "iTerm keybinding tips are listed under \"Manual follow-ups\" at the end of this bootstrap run."
  chris_manual_todo "iTerm2 — Natural Text Editing:"
  chris_manual_todo "  Settings (⌘,) → Profiles → [profile] → Keys → Key Bindings"
  chris_manual_todo "  Presets… → Natural Text Editing"
  chris_manual_todo "  https://iterm2.com/documentation-preferences-profiles-keys.html"
  chris_manual_todo "iTerm2 tab keys: add ⌘⌥← → Previous Tab and ⌘⌥→ → Next Tab under Key Mappings (remove conflicts first)."

  _open_app "Raycast" "/Applications/Raycast.app"
  _open_app "Cursor" "/Applications/Cursor.app"
  _open_app "iTerm" "/Applications/iTerm.app" "$ROOT"
}

_main "$@"

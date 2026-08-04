#!/usr/bin/env bash
# End of bootstrap: open Raycast, Cursor, iTerm (when installed) and print iTerm keybinding hints.
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# iTerm2 profile key "Custom Directory": No | Yes | Recycle | Advanced (see ITAddressBookMgr.h).
# "Recycle" = Preferences → Profiles → General → Initial directory → Reuse previous session's directory.
# Opt out: CHRIS_DEVSTRAP_SKIP_ITERM_REUSE_DIRECTORY=1
_chris_iterm_set_reuse_previous_directory() {
  [[ "${CHRIS_DEVSTRAP_SKIP_ITERM_REUSE_DIRECTORY:-0}" == "1" ]] && return 0
  local plist="${HOME}/Library/Preferences/com.googlecode.iterm2.plist"
  step_start "iTerm2 profiles — Initial directory → reuse previous session"
  if [[ ! -f "$plist" ]]; then
    step_info "No ${plist} yet (launch iTerm2 once to create it). Re-run bootstrap or set Profiles → General → Initial directory → Reuse previous session's directory."
    return 0
  fi
  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
    step_info "Dry-run: would set iTerm2 Profiles → General → Initial directory → Reuse previous session's directory (plist key Custom Directory=Recycle on each New Bookmarks profile)."
    return 0
  fi
  local n
  set +e
  n="$(python3 - "$plist" <<'PY'
import plistlib, pathlib, sys

plist_path = pathlib.Path(sys.argv[1])
try:
    with plist_path.open("rb") as f:
        data = plistlib.load(f)
except OSError:
    sys.stdout.write("0")
    sys.exit(1)
bookmarks = data.get("New Bookmarks")
if not isinstance(bookmarks, list):
    sys.stdout.write("0")
    sys.exit(0)
changed = 0
for bm in bookmarks:
    if isinstance(bm, dict) and bm.get("Custom Directory") != "Recycle":
        bm["Custom Directory"] = "Recycle"
        changed += 1
if changed:
    try:
        with plist_path.open("wb") as f:
            plistlib.dump(data, f)
    except OSError:
        sys.stdout.write("0")
        sys.exit(1)
sys.stdout.write(str(changed))
sys.exit(0)
PY
)"
  local rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    step_warn "Could not read or write iTerm2 preferences (quit iTerm2 and re-run, or check ${plist})."
    return 0
  fi
  [[ -n "$n" && "$n" =~ ^[0-9]+$ ]] || n=0
  if [[ "$n" -gt 0 ]]; then
    # A9: only bounce cfprefsd when we actually mutated the plist.
    killall cfprefsd 2>/dev/null || true
    step_ok "iTerm2: Initial directory → reuse previous session (${n} profile(s) updated)."
  else
    step_ok "iTerm2: Initial directory already set to reuse previous session."
  fi
}

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

  # A8: skip when the app is already running (avoid focus steal on re-runs).
  # CHRIS_DEVSTRAP_FORCE_OPEN_APPS=1 to always open (e.g. to pass an additional path).
  if [[ "${CHRIS_DEVSTRAP_FORCE_OPEN_APPS:-0}" != "1" ]] && pgrep -xq -- "$app_name"; then
    step_ok "${name} already running — skipping open."
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

  if [[ -d "/Applications/iTerm.app" ]]; then
    _chris_iterm_set_reuse_previous_directory
  fi

  step_info "iTerm Natural Text Editing is the first guided manual step at the end of this bootstrap run."
  chris_manual_todo_block_prio 10 "iTerm2 → Natural Text Editing:" \
    "  Settings (⌘,) → Profiles → [profile] → Keys → Key Bindings → Presets… → Natural Text Editing" \
    "  https://iterm2.com/documentation-preferences-profiles-keys.html" \
    "  Tab keys: add ⌘⌥← → Previous Tab and ⌘⌥→ → Next Tab under Key Mappings (remove conflicts first)"

  _open_app "Raycast" "/Applications/Raycast.app"
  _open_app "Cursor" "/Applications/Cursor.app"
  _open_app "iTerm" "/Applications/iTerm.app" "$ROOT"
}

_main "$@"

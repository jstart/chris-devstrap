#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# Reset change tracker for this script (chris_defaults_write_if_diff toggles to 1 on real writes).
CHRIS_DEVSTRAP_DEFAULTS_CHANGED=0
export CHRIS_DEVSTRAP_DEFAULTS_CHANGED

step_start "macOS defaults (appearance, Finder, trackpad, screenshots)"
hr

step_start "Dark mode + Finder"
# osascript talks to the live appearance daemon so the menu bar / Finder flip immediately.
# Falls back to `defaults` for fresh accounts where System Events is not yet wired up.
_chris_darkmode_osa_failed=0
_chris_interface_style_dark() {
  [[ "$(defaults read NSGlobalDomain AppleInterfaceStyle 2>/dev/null || echo "")" == "Dark" ]]
}
if _chris_interface_style_dark; then
  step_ok "Dark mode already enabled — skipping appearance toggle"
else
  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
    chris_run osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true'
  elif ! osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' >/dev/null 2>&1; then
    _chris_darkmode_osa_failed=1
  fi
  chris_defaults_write_if_diff NSGlobalDomain AppleInterfaceStyle -string Dark
  step_info "Dark mode: osascript (live) + defaults (fallback). First run may prompt for Automation permission (System Settings → Privacy & Security → Automation → your terminal → System Events); grant it once and future runs flip dark mode silently."
  if [[ "$_chris_darkmode_osa_failed" == 1 ]]; then
    step_warn "osascript dark-mode toggle failed (likely Automation permission). Defaults still written; menu bar may stay light until logout/login or until you grant Automation."
    chris_manual_todo_block "Dark mode — grant Automation permission:" \
      "  System Settings → Privacy & Security → Automation → your terminal → System Events" \
      "  Re-run: osascript -e 'tell application \"System Events\" to tell appearance preferences to set dark mode to true'"
  fi
fi
chris_defaults_write_if_diff com.apple.finder FXPreferredViewStyle -string clmv
chris_defaults_write_if_diff com.apple.finder ShowRecentTags -bool false
chris_defaults_write_if_diff com.apple.finder ShowPathbar -bool true
chris_defaults_write_if_diff com.apple.finder _FXShowPosixPathInTitle -bool true
chris_defaults_write_if_diff com.apple.finder FXEnableExtensionChangeWarning -bool false
chris_defaults_write_if_diff NSGlobalDomain AppleShowAllExtensions -bool true
chris_defaults_write_if_diff com.apple.finder ShowStatusBar -bool true
chris_defaults_write_if_diff NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false
chris_defaults_write_if_diff NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true

# Finder: new windows open in ~/Downloads; column view is already FXPreferredViewStyle=clmv above.
# Global NSNavLastRootDirectory seeds Cocoa NSOpenPanel/NSSavePanel when the calling app has
# no per-app override. We also scrub per-app overrides below so the global hint actually wins.
# Sort-by-date defaults + PlistBuddy paths vary by macOS; failures are ignored.
step_start "Finder: new window → Downloads; default sort date modified (best effort)"
_chris_downloads_uri="$(python3 -c 'import pathlib; print(pathlib.Path.home().joinpath("Downloads").as_uri())')"
chris_defaults_write_if_diff com.apple.finder NewWindowTarget -string PfLo
chris_defaults_write_if_diff com.apple.finder NewWindowTargetPath -string "$_chris_downloads_uri"
chris_defaults_write_if_diff NSGlobalDomain NSNavLastRootDirectory -string "${HOME}/Downloads"

# Cocoa file-chooser default: scrub per-app NSNavLastRootDirectory so apps that have already
# written their own value (e.g. you saved once to ~/Documents in Preview) fall back to the
# global ~/Downloads hint on next launch. Opt out with CHRIS_DEVSTRAP_KEEP_APP_NAV_DIRS=1 if
# you rely on per-app save-panel memory (e.g. Photoshop pinned to ~/Pictures).
if [[ "${CHRIS_DEVSTRAP_KEEP_APP_NAV_DIRS:-0}" != "1" ]]; then
  _chris_nav_scrubbed=0
  # `defaults find` is one syscall pass; iterating every domain takes ~40s on warm machines.
  # 'Apple Global Domain' is the display name for NSGlobalDomain (already set above) — skip it.
  while IFS= read -r _chris_dom; do
    [[ -z "$_chris_dom" ]] && continue
    [[ "$_chris_dom" == "Apple Global Domain" ]] && continue
    if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
      chris_run defaults delete "$_chris_dom" NSNavLastRootDirectory
    else
      if defaults delete "$_chris_dom" NSNavLastRootDirectory 2>/dev/null; then
        _chris_nav_scrubbed=$((_chris_nav_scrubbed + 1))
        CHRIS_DEVSTRAP_DEFAULTS_CHANGED=1
      fi
    fi
  done < <(defaults find NSNavLastRootDirectory 2>/dev/null | awk -F"'" '/^Found .* in domain / { print $2 }' | sort -u)
  if [[ "$_chris_nav_scrubbed" -gt 0 ]]; then
    step_ok "Scrubbed per-app NSNavLastRootDirectory from ${_chris_nav_scrubbed} domain(s); next launch → ~/Downloads."
  else
    step_ok "No per-app NSNavLastRootDirectory overrides found — global ~/Downloads already authoritative."
  fi
else
  step_info "CHRIS_DEVSTRAP_KEEP_APP_NAV_DIRS=1 — leaving per-app file-chooser defaults intact."
fi
chris_defaults_write_if_diff com.apple.finder FXArrangeGroupViewBy -string dateModified
chris_defaults_write_if_diff com.apple.finder FXPreferredGroupBy -string dateModified
chris_defaults_write_if_diff com.apple.finder FK_ArrangeBy -string dateModified
_finder_plist="${HOME}/Library/Preferences/com.apple.finder.plist"
if [[ -f "$_finder_plist" ]]; then
  # PlistBuddy: check current value first; only write when missing or different.
  _chris_pb_set_if_diff() {
    local path="$1" expected="$2"
    local cur
    cur="$(/usr/libexec/PlistBuddy -c "Print :$path" "$_finder_plist" 2>/dev/null || echo "__MISSING__")"
    [[ "$cur" == "$expected" ]] && return 0
    chris_run /usr/libexec/PlistBuddy -c "Set :$path $expected" "$_finder_plist" || return 0
    CHRIS_DEVSTRAP_DEFAULTS_CHANGED=1
  }
  for _chris_pb_path in \
    'StandardViewSettings:ExtendedListViewSettingsV2:sortColumn' \
    'StandardViewSettings:ExtendedListViewSettingsV2:arrangeBy' \
    'StandardViewSettings:ListViewSettings:sortColumn' \
    'StandardViewSettings:ListViewSettings:arrangeBy' \
    'StandardViewSettings:ExtendedListViewSettings:sortColumn' \
    'FK_DefaultListViewSettingsV2:sortColumn' \
    'FK_DefaultListViewSettingsV2:arrangeBy'; do
    _chris_pb_set_if_diff "$_chris_pb_path" dateModified
  done
fi
step_info "Per-folder .DS_Store can override sort; delete .DS_Store in a folder or use View → Show View Options → Use as Defaults. Many apps remember their own last path in open/save sheets."

step_start "Desktop & Dock: windows (tabs, save prompts, resume)"
# System Settings → Desktop & Dock → Windows
chris_defaults_write_if_diff NSGlobalDomain AppleWindowTabbingMode -string fullscreen
chris_defaults_write_if_diff NSGlobalDomain NSCloseAlwaysConfirmsChanges -bool true
# NSQuitAlwaysKeepsWindows true = "Close windows when quitting an application" OFF (Resume restores windows).
chris_defaults_write_if_diff NSGlobalDomain NSQuitAlwaysKeepsWindows -bool true
chris_defaults_write_if_diff com.apple.WindowManager StandardHideWidgets -bool true
step_info "If System Settings still shows old values, close System Settings and reopen; quit/reopen stubborn apps."

step_start "Trackpad: tap to click"
chris_defaults_write_if_diff com.apple.AppleMultitouchTrackpad Clicking -bool true
chris_defaults_write_if_diff com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
chris_defaults_write_if_diff -currentHost NSGlobalDomain com.apple.mouse.tapBehavior -int 1
chris_defaults_write_if_diff NSGlobalDomain com.apple.mouse.tapBehavior -int 1

step_start "Trackpad: firm press / Force Click + Look up"
# ForceSuppressed: avoid firm-press “Force Click” / pressure actions (often opens Dictionary or data detectors).
chris_defaults_write_if_diff com.apple.AppleMultitouchTrackpad ForceSuppressed -bool true
chris_defaults_write_if_diff com.apple.driver.AppleBluetoothMultitouch.trackpad ForceSuppressed -bool true
# Reduce three-finger “Look up & data detectors” tap (wording varies by OS).
chris_defaults_write_if_diff com.apple.AppleMultitouchTrackpad TrackpadThreeFingerTapGesture -int 0
chris_defaults_write_if_diff com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerTapGesture -int 0

step_start "Screenshots (macOS + iOS Simulator)"
SCREENSHOT_DIR="${HOME}/Screenshots"
if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
  chris_run mkdir -p "$SCREENSHOT_DIR"
else
  mkdir -p "$SCREENSHOT_DIR"
fi
chris_defaults_write_if_diff com.apple.screencapture type -string png
chris_defaults_write_if_diff com.apple.screencapture disable-shadow -bool true
chris_defaults_write_if_diff com.apple.screencapture location -string "$SCREENSHOT_DIR"
chris_defaults_write_if_diff com.apple.iphonesimulator ScreenShotSaveLocation -string "$SCREENSHOT_DIR"

# Default: silence UI sounds unless CHRIS_DEVSTRAP_SILENCE_UI_SOUNDS=0
if [[ "${CHRIS_DEVSTRAP_SILENCE_UI_SOUNDS:-1}" != "0" ]]; then
  step_start "UI sound effects (default off — includes screenshot shutter)"
  step_info "Unset or non-zero disables UI sounds (set CHRIS_DEVSTRAP_SILENCE_UI_SOUNDS=0 to keep system UI sounds). Apple has no screenshot-only toggle."
  chris_defaults_write_if_diff com.apple.systemsound "com.apple.sound.uiaudio.enabled" -int 0
  # Some macOS builds map the Sound → Sound Effects toggle to NSGlobalDomain; mirror so ⌘⇧3/4 respects the same intent.
  chris_defaults_write_if_diff NSGlobalDomain com.apple.sound.uiaudio.enabled -int 0
fi

step_start "Spotlight menu bar icon"
chris_defaults_write_if_diff -currentHost com.apple.Spotlight MenuItemHidden -int 1

# System Settings → Control Center → Sound → "Always Show" in menu bar (undocumented; 18 = show, 24 = hide — see nix-darwin controlcenter).
step_start "Control Center: Sound icon always in menu bar"
_cc_byhost="${HOME}/Library/Preferences/ByHost"
_cc_plist="${_cc_byhost}/com.apple.controlcenter.plist"
if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" != 1 ]]; then
  mkdir -p "$_cc_byhost"
fi
chris_defaults_write_if_diff "$_cc_plist" Sound -int 18
step_info "Apple can change Control Center plist keys; if Sound does not stay visible, set Control Center → Sound → Always Show once in System Settings."

step_start "Default browser (${CHRIS_DEVSTRAP_DEFAULT_BROWSER:-chrome})"
if [[ "${CHRIS_DEVSTRAP_SKIP_DEFAULT_BROWSER:-0}" == "1" ]]; then
  step_info "Skipping default browser (CHRIS_DEVSTRAP_SKIP_DEFAULT_BROWSER=1)."
elif [[ -d "/Applications/Google Chrome.app" ]]; then
  # A6: skip when Chrome is already the default HTTP handler (LaunchServices).
  _chris_chrome_is_default_http() {
    local plist="${HOME}/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist"
    [[ -f "$plist" ]] || return 1
    /usr/libexec/PlistBuddy -c 'Print :LSHandlers' "$plist" 2>/dev/null \
      | awk '/LSHandlerURLScheme = "?http"?;/{in_http=1} in_http && /LSHandlerRoleAll/{print; exit}' \
      | grep -qi 'com.google.chrome'
  }
  if _chris_chrome_is_default_http; then
    step_ok "Chrome already default HTTP handler — skipping defaultbrowser change."
  elif command -v defaultbrowser &>/dev/null; then
    step_info "Setting default HTTP browser via defaultbrowser ${CHRIS_DEVSTRAP_DEFAULT_BROWSER:-chrome} (confirm if macOS prompts)..."
    chris_run defaultbrowser "${CHRIS_DEVSTRAP_DEFAULT_BROWSER:-chrome}" || true
    chris_manual_todo "If macOS prompted, confirm the default browser in System Settings."
  else
    step_info "Opening Chrome to offer \"Set as default browser\" (install Homebrew defaultbrowser to automate next time)..."
    chris_run open -a "Google Chrome" --args --make-default-browser || true
    chris_manual_todo "In Chrome, complete \"Set as default browser\" if shown (or install Homebrew defaultbrowser for automation next time)."
  fi
fi

step_start "Misc (LaunchServices quarantine, ~/Library visibility)"
chris_defaults_write_if_diff com.apple.LaunchServices LSQuarantine -bool false
# chflags is cheap and the read is fragile across macOS versions; keep unconditional.
chris_run chflags nohidden "$HOME/Library" || true

# Hot corners live under com.apple.dock (modifier 0 = no key required).
# Corner action ints: 1 = disabled, 10 = Put Display to Sleep (see Apple/nix-darwin hot-corner tables).
step_start "Hot corners (top: sleep display; bottom: off)"
chris_defaults_write_if_diff com.apple.dock wvous-tl-corner -int 10
chris_defaults_write_if_diff com.apple.dock wvous-tl-modifier -int 0
chris_defaults_write_if_diff com.apple.dock wvous-tr-corner -int 10
chris_defaults_write_if_diff com.apple.dock wvous-tr-modifier -int 0
chris_defaults_write_if_diff com.apple.dock wvous-bl-corner -int 1
chris_defaults_write_if_diff com.apple.dock wvous-bl-modifier -int 0
chris_defaults_write_if_diff com.apple.dock wvous-br-corner -int 1
chris_defaults_write_if_diff com.apple.dock wvous-br-modifier -int 0

step_start "Restart Finder + menu bar (only when something changed)"
# Defer Dock restart to scripts/dock.sh so we don't double-bounce it.
chris_killall_if_changed Finder SystemUIServer


#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

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
  chris_run defaults write NSGlobalDomain AppleInterfaceStyle -string Dark || true
  chris_run defaults write -g AppleInterfaceStyle -string Dark || true
  step_info "Dark mode: osascript (live) + defaults (fallback). First run may prompt for Automation permission (System Settings → Privacy & Security → Automation → your terminal → System Events); grant it once and future runs flip dark mode silently."
  if [[ "$_chris_darkmode_osa_failed" == 1 ]]; then
    step_warn "osascript dark-mode toggle failed (likely Automation permission). Defaults still written; menu bar may stay light until logout/login or until you grant Automation."
    chris_manual_todo_block "Dark mode — grant Automation permission:" \
      "  System Settings → Privacy & Security → Automation → your terminal → System Events" \
      "  Re-run: osascript -e 'tell application \"System Events\" to tell appearance preferences to set dark mode to true'"
  fi
fi
chris_run defaults write com.apple.finder FXPreferredViewStyle -string clmv || true
chris_run defaults write com.apple.finder ShowRecentTags -bool false || true
chris_run defaults write com.apple.finder ShowPathbar -bool true || true
chris_run defaults write com.apple.finder _FXShowPosixPathInTitle -bool true || true
chris_run defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false || true
chris_run defaults write NSGlobalDomain AppleShowAllExtensions -bool true || true
chris_run defaults write com.apple.finder ShowStatusBar -bool true || true
chris_run defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false || true
chris_run defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true || true

# Finder: new windows open in ~/Downloads; column view is already FXPreferredViewStyle=clmv above.
# Global NSNavLastRootDirectory is a best-effort hint for some Cocoa save/open panels (not universal).
# Sort-by-date defaults + PlistBuddy paths vary by macOS; failures are ignored.
step_start "Finder: new window → Downloads; default sort date modified (best effort)"
_chris_downloads_uri="$(python3 -c 'import pathlib; print(pathlib.Path.home().joinpath("Downloads").as_uri())')"
chris_run defaults write com.apple.finder NewWindowTarget -string PfLo || true
chris_run defaults write com.apple.finder NewWindowTargetPath -string "$_chris_downloads_uri" || true
chris_run defaults write NSGlobalDomain NSNavLastRootDirectory -string "${HOME}/Downloads" || true
chris_run defaults write com.apple.finder FXArrangeGroupViewBy -string dateModified || true
chris_run defaults write com.apple.finder FXPreferredGroupBy -string dateModified || true
chris_run defaults write com.apple.finder FK_ArrangeBy -string dateModified || true
_finder_plist="${HOME}/Library/Preferences/com.apple.finder.plist"
if [[ -f "$_finder_plist" ]]; then
  for _chris_pb in \
    'Set :StandardViewSettings:ExtendedListViewSettingsV2:sortColumn dateModified' \
    'Set :StandardViewSettings:ExtendedListViewSettingsV2:arrangeBy dateModified' \
    'Set :StandardViewSettings:ListViewSettings:sortColumn dateModified' \
    'Set :StandardViewSettings:ListViewSettings:arrangeBy dateModified' \
    'Set :StandardViewSettings:ExtendedListViewSettings:sortColumn dateModified' \
    'Set :FK_DefaultListViewSettingsV2:sortColumn dateModified' \
    'Set :FK_DefaultListViewSettingsV2:arrangeBy dateModified'; do
    chris_run /usr/libexec/PlistBuddy -c "$_chris_pb" "$_finder_plist" || true
  done
fi
step_info "Per-folder .DS_Store can override sort; delete .DS_Store in a folder or use View → Show View Options → Use as Defaults. Many apps remember their own last path in open/save sheets."

step_start "Desktop & Dock: windows (tabs, save prompts, resume)"
# System Settings → Desktop & Dock → Windows
chris_run defaults write NSGlobalDomain AppleWindowTabbingMode -string fullscreen || true
chris_run defaults write NSGlobalDomain NSCloseAlwaysConfirmsChanges -bool true || true
# NSQuitAlwaysKeepsWindows true = "Close windows when quitting an application" OFF (Resume restores windows).
chris_run defaults write NSGlobalDomain NSQuitAlwaysKeepsWindows -bool true || true
chris_run defaults write com.apple.WindowManager StandardHideWidgets -bool true || true
step_info "If System Settings still shows old values, close System Settings and reopen; quit/reopen stubborn apps."

step_start "Trackpad: tap to click"
chris_run defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true || true
chris_run defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true || true
chris_run defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1 || true
chris_run defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1 || true

step_start "Trackpad: firm press / Force Click + Look up"
# ForceSuppressed: avoid firm-press “Force Click” / pressure actions (often opens Dictionary or data detectors).
chris_run defaults write com.apple.AppleMultitouchTrackpad ForceSuppressed -bool true || true
chris_run defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad ForceSuppressed -bool true || true
# Reduce three-finger “Look up & data detectors” tap (wording varies by OS).
chris_run defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerTapGesture -int 0 || true
chris_run defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad TrackpadThreeFingerTapGesture -int 0 || true

step_start "Screenshots (macOS + iOS Simulator)"
SCREENSHOT_DIR="${HOME}/Screenshots"
if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
  chris_run mkdir -p "$SCREENSHOT_DIR"
else
  mkdir -p "$SCREENSHOT_DIR"
fi
chris_run defaults write com.apple.screencapture type -string png || true
chris_run defaults write com.apple.screencapture disable-shadow -bool true || true
chris_run defaults write com.apple.screencapture location -string "$SCREENSHOT_DIR" || true
chris_run defaults write com.apple.iphonesimulator ScreenShotSaveLocation -string "$SCREENSHOT_DIR" || true

# Default: silence UI sounds unless CHRIS_DEVSTRAP_SILENCE_UI_SOUNDS=0
if [[ "${CHRIS_DEVSTRAP_SILENCE_UI_SOUNDS:-1}" != "0" ]]; then
  step_start "UI sound effects (default off — includes screenshot shutter)"
  step_info "Unset or non-zero disables UI sounds (set CHRIS_DEVSTRAP_SILENCE_UI_SOUNDS=0 to keep system UI sounds). Apple has no screenshot-only toggle."
  chris_run defaults write com.apple.systemsound "com.apple.sound.uiaudio.enabled" -int 0 || true
  # Some macOS builds map the Sound → Sound Effects toggle to NSGlobalDomain; mirror so ⌘⇧3/4 respects the same intent.
  chris_run defaults write -g com.apple.sound.uiaudio.enabled -int 0 || true
fi

step_start "Spotlight menu bar icon"
chris_run defaults -currentHost write com.apple.Spotlight MenuItemHidden -int 1 || true

# System Settings → Control Center → Sound → "Always Show" in menu bar (undocumented; 18 = show, 24 = hide — see nix-darwin controlcenter).
step_start "Control Center: Sound icon always in menu bar"
_cc_byhost="${HOME}/Library/Preferences/ByHost"
_cc_plist="${_cc_byhost}/com.apple.controlcenter.plist"
if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" != 1 ]]; then
  mkdir -p "$_cc_byhost"
fi
chris_run defaults write "$_cc_plist" Sound -int 18 || true
step_info "Apple can change Control Center plist keys; if Sound does not stay visible, set Control Center → Sound → Always Show once in System Settings."

step_start "Default browser (${CHRIS_DEVSTRAP_DEFAULT_BROWSER:-chrome})"
if [[ "${CHRIS_DEVSTRAP_SKIP_DEFAULT_BROWSER:-0}" == "1" ]]; then
  step_info "Skipping default browser (CHRIS_DEVSTRAP_SKIP_DEFAULT_BROWSER=1)."
elif [[ -d "/Applications/Google Chrome.app" ]]; then
  if command -v defaultbrowser &>/dev/null; then
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
chris_run defaults write com.apple.LaunchServices LSQuarantine -bool false || true
chris_run chflags nohidden "$HOME/Library" || true

# Hot corners live under com.apple.dock (modifier 0 = no key required).
# Corner action ints: 1 = disabled, 10 = Put Display to Sleep (see Apple/nix-darwin hot-corner tables).
step_start "Hot corners (top: sleep display; bottom: off)"
chris_run defaults write com.apple.dock wvous-tl-corner -int 10
chris_run defaults write com.apple.dock wvous-tl-modifier -int 0
chris_run defaults write com.apple.dock wvous-tr-corner -int 10
chris_run defaults write com.apple.dock wvous-tr-modifier -int 0
chris_run defaults write com.apple.dock wvous-bl-corner -int 1
chris_run defaults write com.apple.dock wvous-bl-modifier -int 0
chris_run defaults write com.apple.dock wvous-br-corner -int 1
chris_run defaults write com.apple.dock wvous-br-modifier -int 0

step_start "Restart Finder + menu bar + Dock"
if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
  chris_run killall Finder
  chris_run killall SystemUIServer
  chris_run killall Dock
else
  killall Finder 2>/dev/null || true
  killall SystemUIServer 2>/dev/null || true
  killall Dock 2>/dev/null || true
fi


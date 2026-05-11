#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

step_start "macOS defaults (appearance, Finder, trackpad, screenshots)"
hr

step_start "Dark mode + Finder"
chris_run defaults write NSGlobalDomain AppleInterfaceStyle -string Dark || true
chris_run defaults write -g AppleInterfaceStyle -string Dark || true
step_info "Dark mode uses defaults; if the menu bar stays light, toggle once in System Settings → Appearance, or log out/in — some macOS builds defer until then."
chris_run defaults write com.apple.finder FXPreferredViewStyle -string clmv || true
chris_run defaults write com.apple.finder ShowRecentTags -bool false || true
chris_run defaults write com.apple.finder ShowPathbar -bool true || true
chris_run defaults write com.apple.finder _FXShowPosixPathInTitle -bool true || true
chris_run defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false || true
chris_run defaults write NSGlobalDomain AppleShowAllExtensions -bool true || true
chris_run defaults write com.apple.finder ShowStatusBar -bool true || true
chris_run defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false || true
chris_run defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true || true

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

if [[ "${CHRIS_DEVSTRAP_SILENCE_UI_SOUNDS:-}" == "1" ]]; then
  step_start "UI sound effects (optional — includes screenshot shutter)"
  step_info "CHRIS_DEVSTRAP_SILENCE_UI_SOUNDS=1 disables all macOS UI sound effects (Apple does not offer screenshot-only)."
  chris_run defaults write com.apple.systemsound "com.apple.sound.uiaudio.enabled" -int 0 || true
  # Some macOS builds map the Sound → Sound Effects toggle to NSGlobalDomain; mirror so ⌘⇧3/4 respects the same intent.
  chris_run defaults write -g com.apple.sound.uiaudio.enabled -int 0 || true
fi

step_start "Spotlight menu bar icon"
chris_run defaults -currentHost write com.apple.Spotlight MenuItemHidden -int 1 || true

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

if command -v xcodebuild &>/dev/null; then
  if ! xcodebuild -license status 2>/dev/null | grep -qi 'agreed'; then
    chris_manual_todo "Full Xcode: accept the license with sudo xcodebuild -license accept"
  fi
fi


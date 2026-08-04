#!/usr/bin/env bash
# Best-effort: Xcode license, first-launch packages + iOS Simulator runtime (full Xcode only).
# See README: "Xcode iOS SDK and predictive completion". CLT-only machines are skipped.
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

chris_xcode_manual_todos() {
  local license_line="  License: accepted automatically when sudo is available (else: sudo xcodebuild -license accept)"
  if [[ "${CHRIS_XCODE_LICENSE_OK:-0}" != "1" ]]; then
    license_line="  sudo xcodebuild -license accept   # required — git/clang will refuse until this runs"
  fi
  chris_manual_todo_block "Xcode (after install):" \
    "$license_line" \
    "  Settings → Text Editing → download predictive completion when offered" \
    "  Settings → Components → iOS Simulator runtime if CLI download failed"
}

if [[ "$(uname -s 2>/dev/null || true)" != "Darwin" ]]; then
  step_info "Skipping Xcode components: not macOS."
  exit 0
fi

if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == "1" ]]; then
  step_info "Skipping Xcode components: dry-run."
  exit 0
fi

_chris_configure_xcodebuild() {
  if [[ -d "/Applications/Xcode.app" ]]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
  else
    DEVELOPER_DIR="$(xcode-select -p)"
    export DEVELOPER_DIR
  fi
  CHRIS_XCODEBUILD="${DEVELOPER_DIR}/usr/bin/xcodebuild"
  if [[ ! -x "$CHRIS_XCODEBUILD" ]]; then
    step_warn "No executable xcodebuild at ${CHRIS_XCODEBUILD} — skipping Xcode components."
    return 1
  fi
  return 0
}

# Point active developer dir at full Xcode when present (avoids CLT-only path after mas install).
_chris_xcode_select_app() {
  [[ -d "/Applications/Xcode.app/Contents/Developer" ]] || return 0
  local cur
  cur="$(xcode-select -p 2>/dev/null || true)"
  if [[ "$cur" == "/Applications/Xcode.app/Contents/Developer" ]]; then
    step_ok "xcode-select already points at Xcode.app"
    return 0
  fi
  step_start "xcode-select -s Xcode.app"
  if sudo -n xcode-select -s /Applications/Xcode.app/Contents/Developer 2>/dev/null; then
    step_ok "Active developer directory → /Applications/Xcode.app/Contents/Developer"
    return 0
  fi
  if [[ -r /dev/tty && -w /dev/tty ]] && sudo xcode-select -s /Applications/Xcode.app/Contents/Developer </dev/tty 2>/dev/tty; then
    step_ok "Active developer directory → /Applications/Xcode.app/Contents/Developer"
    return 0
  fi
  step_warn "Could not switch xcode-select to Xcode.app — run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  return 1
}

# Accept the Xcode/SDK license non-interactively. Without this, new shells print:
#   You have not agreed to the Xcode license agreements...
_chris_xcode_accept_license() {
  CHRIS_XCODE_LICENSE_OK=0
  step_start "Xcode license (sudo xcodebuild -license accept)"

  # Already accepted? xcodebuild -license check / -checkFirstLaunchStatus varies by version;
  # probe with a cheap license-gated command.
  if "$CHRIS_XCODEBUILD" -version >/dev/null 2>&1; then
    step_ok "Xcode license already accepted (xcodebuild -version ok)"
    CHRIS_XCODE_LICENSE_OK=1
    return 0
  fi

  local out=""
  if sudo -n "$CHRIS_XCODEBUILD" -license accept >/dev/null 2>&1; then
    :
  elif [[ -r /dev/tty && -w /dev/tty ]]; then
    step_info "Accepting Xcode license (uses primed sudo / may prompt once)…"
    if ! sudo "$CHRIS_XCODEBUILD" -license accept </dev/tty 2>/dev/tty; then
      step_warn "sudo xcodebuild -license accept failed."
      chris_manual_todo "Run: sudo xcodebuild -license accept"
      return 1
    fi
  else
    step_warn "Cannot accept Xcode license — no sudo ticket and no /dev/tty."
    chris_manual_todo "Run: sudo xcodebuild -license accept"
    return 1
  fi

  if "$CHRIS_XCODEBUILD" -version >/dev/null 2>&1; then
    step_ok "Xcode license accepted"
    CHRIS_XCODE_LICENSE_OK=1
    return 0
  fi

  # Some installs still need -runFirstLaunch before -version is clean; treat accept as done.
  out="$("$CHRIS_XCODEBUILD" -version 2>&1 || true)"
  if [[ "$out" == *"license"* ]]; then
    step_warn "License still blocking after accept: ${out}"
    chris_manual_todo "Run: sudo xcodebuild -license accept"
    return 1
  fi
  step_ok "Xcode license accept command finished"
  CHRIS_XCODE_LICENSE_OK=1
  return 0
}

if ! chris_xcode_app_installed; then
  step_info "Skipping Xcode components: no /Applications/Xcode.app and active developer dir is not an Xcode.app bundle (Command Line Tools or Xcode not selected)."
  exit 0
fi

if ! _chris_configure_xcodebuild; then
  exit 0
fi

step_start "Xcode components (license + first launch + iOS Simulator runtime)"
step_info "Using DEVELOPER_DIR=${DEVELOPER_DIR}"
step_info "Reference: https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components"

_chris_xcode_select_app || true
# Re-resolve paths after xcode-select may have changed.
_chris_configure_xcodebuild || exit 0
_chris_xcode_accept_license || true

# Exits non-zero when first-launch work is still needed — not treated as a bootstrap failure.
if "$CHRIS_XCODEBUILD" -checkFirstLaunchStatus; then
  step_ok "xcodebuild -checkFirstLaunchStatus: satisfied — skipping -runFirstLaunch"
else
  step_info "xcodebuild -checkFirstLaunchStatus: non-zero exit (first-launch work may be pending) — continuing with -runFirstLaunch."
  if ! "$CHRIS_XCODEBUILD" -runFirstLaunch; then
    step_warn "xcodebuild -runFirstLaunch failed (license, network, or disk). Try: sudo xcodebuild -license accept — then open Xcode once or re-run bootstrap."
  fi

  if ! "$CHRIS_XCODEBUILD" -runFirstLaunch -checkForNewerComponents; then
    step_warn "xcodebuild -runFirstLaunch -checkForNewerComponents failed — optional between-release updates; try Xcode → Settings → Components."
  fi
fi

# A4: skip the (often slow) download when an iOS Simulator runtime is already installed.
_chris_ios_runtime_installed() {
  command -v xcrun >/dev/null 2>&1 || return 1
  xcrun simctl list runtimes 2>/dev/null | grep -Eq '^iOS [0-9]'
}
if _chris_ios_runtime_installed; then
  step_ok "iOS Simulator runtime already installed — skipping -downloadPlatform iOS."
elif ! "$CHRIS_XCODEBUILD" -downloadPlatform iOS; then
  step_warn "xcodebuild -downloadPlatform iOS failed — install/update the iOS Simulator runtime under Xcode → Settings → Components (or Platforms)."
fi

# Dock runs earlier in bootstrap (before heavy mas install). Pin Xcode now when it
# just appeared — same slot as config/dock-add.tsv (after Cursor, before iTerm).
_chris_dock_add_xcode() {
  local app="/Applications/Xcode.app"
  [[ -d "$app" ]] || return 0
  if ! command -v dockutil >/dev/null 2>&1; then
    step_warn "dockutil not on PATH — skip Dock pin for Xcode (re-run ./scripts/dock.sh after brew bundle)."
    return 0
  fi
  if dockutil --find Xcode &>/dev/null; then
    step_ok "Xcode already on Dock"
    return 0
  fi
  step_start "Add Xcode to Dock"
  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
    chris_run dockutil --add "$app" --label Xcode --after Cursor --no-restart
    return 0
  fi
  local added=0
  if dockutil --find Cursor &>/dev/null &&
    dockutil --add "$app" --label Xcode --after Cursor --no-restart 2>/dev/null; then
    added=1
  elif dockutil --find iTerm &>/dev/null &&
    dockutil --add "$app" --label Xcode --before iTerm --no-restart 2>/dev/null; then
    added=1
  elif dockutil --add "$app" --label Xcode --no-restart 2>/dev/null; then
    added=1
  fi
  if [[ "$added" == "1" ]]; then
    killall Dock 2>/dev/null || true
    step_ok "Xcode pinned to Dock (matches config/dock-add.tsv order when Cursor/iTerm are present)"
  else
    step_warn "Could not add Xcode to Dock — run: dockutil --add /Applications/Xcode.app --label Xcode"
  fi
}
_chris_dock_add_xcode

chris_xcode_manual_todos
step_ok "Xcode components step finished (warnings above are non-fatal)."

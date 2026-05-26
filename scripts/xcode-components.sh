#!/usr/bin/env bash
# Best-effort: Xcode first-launch packages + iOS Simulator runtime (full Xcode only).
# See README: "Xcode iOS SDK and predictive completion". CLT-only machines are skipped.
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

chris_xcode_manual_todos() {
  chris_manual_todo_block "Xcode (after install):" \
    "  sudo xcodebuild -license accept when prompted" \
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

if ! chris_xcode_app_installed; then
  step_info "Skipping Xcode components: no /Applications/Xcode.app and active developer dir is not an Xcode.app bundle (Command Line Tools or Xcode not selected)."
  exit 0
fi

if ! _chris_configure_xcodebuild; then
  exit 0
fi

step_start "Xcode components (first launch + iOS Simulator runtime)"
step_info "Using DEVELOPER_DIR=${DEVELOPER_DIR}"
step_info "Reference: https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components"

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

chris_xcode_manual_todos
step_ok "Xcode components step finished (warnings above are non-fatal)."

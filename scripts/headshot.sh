#!/usr/bin/env bash
# Copy repo headshot to ~/Downloads and set the macOS local user login picture (dscl).
# Requires assets/headshot.png in the repo. Apple ID / Chrome / etc. avatars are manual (see assets/README.md).
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

if [[ "$(uname -s)" != "Darwin" ]]; then
  exit 0
fi

if [[ "${CHRIS_DEVSTRAP_SKIP_HEADSHOT:-0}" == "1" ]]; then
  step_info "Skipping headshot (CHRIS_DEVSTRAP_SKIP_HEADSHOT=1)."
  exit 0
fi

SRC="${CHRIS_DEVSTRAP_ROOT}/assets/headshot.png"
if [[ ! -f "$SRC" ]]; then
  step_info "No assets/headshot.png — skipping headshot (see assets/README.md)."
  exit 0
fi

_support_dir="${HOME}/Library/Application Support/chris-devstrap"
_support_img="${_support_dir}/headshot.jpg"
_support_png="${_support_dir}/headshot.png"
_downloads_copy="${HOME}/Downloads/headshot.png"
_u="/Users/$(whoami)"

step_start "Headshot → Downloads + macOS user picture"

if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
  step_info "Would: sips → ${_support_img} (or ${_support_png}), cp → ${_downloads_copy}, sudo dscl Picture for ${_u}, refresh SystemUIServer/Finder."
  chris_run sips -s format jpeg "$SRC" --out "$_support_img"
  chris_run cp -f "$SRC" "$_downloads_copy"
  chris_run sudo dscl . -delete "${_u}" JPEGPhoto
  chris_run sudo dscl . -delete "${_u}" Picture
  chris_run sudo dscl . -create "${_u}" Picture "${_support_img}"
  chris_run killall SystemUIServer
  chris_run killall Finder
  exit 0
fi

mkdir -p "$_support_dir"
chris_run mkdir -p "${HOME}/Downloads"

if sips -s format jpeg "$SRC" --out "$_support_img" &>/dev/null; then
  :
else
  step_warn "sips could not convert to JPEG — using PNG for dscl Picture path."
  chris_run cp -f "$SRC" "$_support_png"
  _support_img="$_support_png"
fi

chris_run cp -f "$SRC" "$_downloads_copy"
step_ok "Copied headshot to ${_downloads_copy}"

step_info "Updating local user picture (sudo may prompt once)…"
set +e
sudo dscl . -delete "${_u}" JPEGPhoto 2>/dev/null
sudo dscl . -delete "${_u}" Picture 2>/dev/null
dscl_ok=0
sudo dscl . -create "${_u}" Picture "${_support_img}" || dscl_ok=$?
set -e
if [[ "$dscl_ok" -ne 0 ]]; then
  step_warn "dscl Picture update failed — set manually: System Settings → Users & Groups."
  chris_manual_todo "Users & Groups: drag ${HOME}/Downloads/headshot.png onto your user avatar."
else
  step_ok "macOS user picture (dscl Picture) → ${_support_img}"
fi

chris_run killall SystemUIServer || true
chris_run killall Finder || true

chris_manual_todo "Apple ID / iCloud avatar: appleid.apple.com or System Settings → Apple ID → your picture (no supported repo automation)."
chris_manual_todo "Google Chrome profile photo: Chrome → Settings → You and Google."
chris_manual_todo "Messages / other apps: set profile images inside each app if you want them to match."

exit 0

#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

CONFIG="${ROOT}/config"
REMOVE_FILE="${CONFIG}/dock-remove.txt"
ADD_FILE="${CONFIG}/dock-add.tsv"

step_start "Dock (defaults + dockutil)"
step_info "Config: $CONFIG"

if ! command -v dockutil &>/dev/null; then
  step_warn "dockutil not found; run brew bundle first."
  exit 1
fi

step_start "Dock appearance & behavior (defaults)"
# tilesize / largesize: macOS slider max is typically 128pt; many pinned apps still get scaled down to fit the screen width.
chris_run defaults write com.apple.dock autohide -bool true
chris_run defaults write com.apple.dock autohide-delay -float 0.15
chris_run defaults write com.apple.dock autohide-time-modifier -float 0.4
chris_run defaults write com.apple.dock magnification -bool true
chris_run defaults write com.apple.dock largesize -int 128
chris_run defaults write com.apple.dock tilesize -int 128
chris_run defaults write com.apple.dock show-recents -bool false

step_start "Remove Dock items (--remove all, then dock-remove.txt)"
if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
  chris_run dockutil --remove all --no-restart
else
  dockutil --remove all --no-restart 2>/dev/null || true
fi
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line//$'\r'/}"
  [[ -z "${line//[[:space:]]/}" ]] && continue
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  item="${line#"${line%%[![:space:]]*}"}"
  item="${item%"${item##*[![:space:]]}"}"
  [[ -z "$item" ]] && continue
  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
    chris_run dockutil --remove "$item" --no-restart
  else
    dockutil --remove "$item" --no-restart 2>/dev/null || true
  fi
done <"$REMOVE_FILE"

step_start "Add Dock items (dock-add.tsv)"
dock_add_once() {
  local label="$1" path="$2"
  if [[ "$label" == "Messages" && ! -d "$path" ]]; then
    if [[ -d "/System/Applications/Messages.app" ]]; then
      path="/System/Applications/Messages.app"
    elif [[ -d "/Applications/Messages.app" ]]; then
      path="/Applications/Messages.app"
    fi
  fi
  if [[ "$label" == "Notes" && ! -d "$path" ]]; then
    if [[ -d "/System/Applications/Notes.app" ]]; then
      path="/System/Applications/Notes.app"
    elif [[ -d "/Applications/Notes.app" ]]; then
      path="/Applications/Notes.app"
    fi
  fi
  [[ -d "$path" ]] || return 0
  if dockutil --find "$label" &>/dev/null; then
    return 0
  fi
  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
    chris_run dockutil --add "$path" --label "$label" --no-restart
    return 0
  fi
  dockutil --add "$path" --label "$label" --no-restart 2>/dev/null || \
    dockutil --add "$path" --no-restart 2>/dev/null || true
}

while IFS=$'\t' read -r label path || [[ -n "${label:-}" ]]; do
  label="${label//$'\r'/}"
  path="${path//$'\r'/}"
  [[ -z "${label//[[:space:]]/}" ]] && continue
  [[ "$label" =~ ^[[:space:]]*# ]] && continue
  label="${label#"${label%%[![:space:]]*}"}"
  label="${label%"${label##*[![:space:]]}"}"
  path="${path#"${path%%[![:space:]]*}"}"
  path="${path%"${path##*[![:space:]]}"}"
  [[ -z "$label" ]] && continue
  [[ -z "$path" ]] && continue
  dock_add_once "$label" "$path"
done <"$ADD_FILE"

step_start "Add Downloads folder (fan, date modified)"
downloads="${HOME}/Downloads"
if [[ ! -d "$downloads" ]]; then
  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
    chris_run mkdir -p "$downloads"
  else
    mkdir -p "$downloads" 2>/dev/null || true
  fi
fi
if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
  chris_run dockutil --add "$downloads" --view fan --display folder --sort datemodified --section others --label Downloads --no-restart
else
  if dockutil --find Downloads &>/dev/null; then
    :
  else
    dockutil --add "$downloads" --view fan --display folder --sort datemodified --section others --label Downloads --no-restart 2>/dev/null || \
      step_warn "Could not add Downloads to the Dock (dockutil)."
  fi
fi

step_start "Restart Dock"
if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
  chris_run killall Dock
else
  killall Dock 2>/dev/null || true
fi
step_ok "Dock updated."

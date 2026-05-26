#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

CONFIG="${ROOT}/config"
REMOVE_FILE="${CONFIG}/dock-remove.txt"
ADD_FILE="${CONFIG}/dock-add.tsv"

# macos-defaults.sh deferred its Dock restart to us. Inherit its "changed" flag so a
# defaults-only change there still bounces the Dock here.
: "${CHRIS_DEVSTRAP_DEFAULTS_CHANGED:=0}"

step_start "Dock (defaults + dockutil)"
step_info "Config: $CONFIG"

if ! command -v dockutil &>/dev/null; then
  step_warn "dockutil not found; run brew bundle first."
  exit 1
fi

step_start "Dock appearance & behavior (defaults)"
# tilesize / largesize: macOS slider max is typically 128pt; many pinned apps still get scaled down to fit the screen width.
chris_defaults_write_if_diff com.apple.dock autohide -bool true
chris_defaults_write_if_diff com.apple.dock autohide-delay -float 0.15
chris_defaults_write_if_diff com.apple.dock autohide-time-modifier -float 0.4
chris_defaults_write_if_diff com.apple.dock magnification -bool true
chris_defaults_write_if_diff com.apple.dock largesize -int 128
chris_defaults_write_if_diff com.apple.dock tilesize -int 128
chris_defaults_write_if_diff com.apple.dock show-recents -bool false

# Build the desired persistent-apps label list (in order) from dock-add.tsv.
_chris_desired_app_labels() {
  while IFS=$'\t' read -r label _ || [[ -n "${label:-}" ]]; do
    label="${label//$'\r'/}"
    [[ -z "${label//[[:space:]]/}" ]] && continue
    [[ "$label" =~ ^[[:space:]]*# ]] && continue
    label="${label#"${label%%[![:space:]]*}"}"
    label="${label%"${label##*[![:space:]]}"}"
    [[ -z "$label" ]] && continue
    printf '%s\n' "$label"
  done <"$ADD_FILE"
}

# A3: skip the destructive --remove all + rebuild when the current Dock already
# matches dock-add.tsv (persistentApps in order + Downloads in persistentOthers).
# dockutil --list columns: 1=Label  2=URL  3=Section  4=Plist  5=BundleID
# Section tokens are persistentApps / persistentOthers (no hyphen).
# Override with CHRIS_DEVSTRAP_FORCE_DOCK=1 to rebuild even when matched.
_chris_dock_layout_matches() {
  [[ "${CHRIS_DEVSTRAP_FORCE_DOCK:-0}" == "1" ]] && return 1
  local listing
  listing="$(dockutil --list 2>/dev/null || true)"
  [[ -z "$listing" ]] && return 1

  local actual_apps desired_apps
  actual_apps="$(printf '%s\n' "$listing" | awk -F'\t' '$3 == "persistentApps" { print $1 }')"
  desired_apps="$(_chris_desired_app_labels)"
  [[ "$actual_apps" != "$desired_apps" ]] && return 1

  printf '%s\n' "$listing" \
    | awk -F'\t' '$1 == "Downloads" && $3 == "persistentOthers" { found=1 } END { exit (found ? 0 : 1) }'
}

if _chris_dock_layout_matches; then
  step_ok "Dock layout already matches config/dock-add.tsv + Downloads — skipping --remove all (CHRIS_DEVSTRAP_FORCE_DOCK=1 to rebuild)."
else
  step_start "Remove Dock items (--remove all, then dock-remove.txt)"
  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
    chris_run dockutil --remove all --no-restart
  else
    dockutil --remove all --no-restart 2>/dev/null || true
  fi
  CHRIS_DEVSTRAP_DEFAULTS_CHANGED=1
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
fi

# Restart Dock once at the end — only when this script (or macos-defaults.sh) changed something.
chris_killall_if_changed Dock
step_ok "Dock updated."

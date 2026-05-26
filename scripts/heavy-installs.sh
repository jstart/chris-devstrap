#!/usr/bin/env bash
# Heavy / interactive installs (deferred to the last bootstrap step).
# Apple ID + App Store sign-in is covered in the guided manual checklist (queued earlier in bootstrap).
#
# Env:
#   CHRIS_DEVSTRAP_SKIP_HEAVY=1           Skip entirely (queues a re-run command in the manual checklist).
#   CHRIS_DEVSTRAP_HEAVY_NONINTERACTIVE=1 Start downloads without Enter prompt (assumes signed in).
#   CHRIS_DEVSTRAP_DRY_RUN=1              Print what would happen; do not invoke brew bundle.
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

if [[ "$(uname -s)" != "Darwin" ]]; then
  step_info "Skipping heavy installs: not macOS."
  exit 0
fi

HEAVY_FILE="${CHRIS_DEVSTRAP_ROOT}/Brewfile.heavy"
if [[ ! -f "$HEAVY_FILE" ]]; then
  step_info "No Brewfile.heavy — skipping heavy installs."
  exit 0
fi

if [[ "${CHRIS_DEVSTRAP_SKIP_HEAVY:-0}" == "1" ]]; then
  step_info "Skipping heavy installs (CHRIS_DEVSTRAP_SKIP_HEAVY=1)."
  chris_manual_todo "$(chris_heavy_install_manual_msg "$HEAVY_FILE")"
  exit 0
fi

step_start "Heavy / interactive installs (Xcode via mas, Android Studio, …)"
step_info "These can total ~15 GB. They run last so the rest of bootstrap finished while you were active."
step_info "Brewfile.heavy:"
sed 's/^/  /' "$HEAVY_FILE"

if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-0}" == "1" ]]; then
  step_info "Dry-run: would prompt to start heavy downloads, then: brew bundle install --no-upgrade --file=$HEAVY_FILE"
  exit 0
fi

_chris_heavy_interactive=0
if [[ "${CHRIS_DEVSTRAP_HEAVY_NONINTERACTIVE:-0}" != "1" ]] \
  && [[ "${CHRIS_DEVSTRAP_INTERACTIVE:-0}" == "1" ]] \
  && [[ -r /dev/tty ]]; then
  _chris_heavy_interactive=1
fi

if [[ "$_chris_heavy_interactive" == "1" ]]; then
  hr
  printf '%sPress Enter to start heavy downloads, or type s then Enter to skip.%s\n' "$UI_DIM" "$UI_RESET"
  reply=""
  IFS= read -r reply </dev/tty || {
    step_info "Skipping heavy installs (read interrupted)."
    chris_manual_todo "$(chris_heavy_install_manual_msg "$HEAVY_FILE")"
    exit 0
  }
  reply_lc="$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]')"
  case "$reply_lc" in
    s | skip | n | no)
      step_info "Skipping heavy installs for this run."
      chris_manual_todo "$(chris_heavy_install_manual_msg "$HEAVY_FILE")"
      exit 0
      ;;
  esac
else
  step_info "Non-interactive run — starting heavy downloads. Set CHRIS_DEVSTRAP_SKIP_HEAVY=1 to skip."
fi

if ! brew bundle install --no-upgrade --file="$HEAVY_FILE"; then
  step_warn "brew bundle install for $HEAVY_FILE reported failures (see output above)."
  chris_manual_todo "$(chris_heavy_install_manual_msg "$HEAVY_FILE")"
  exit 0
fi

step_ok "Heavy installs finished."

if [[ -d "/Applications/Xcode.app" ]] || xcode-select -p 2>/dev/null | grep -Fq '.app/Contents/Developer'; then
  step_info "Xcode present after heavy install — running first-launch components…"
  bash "${CHRIS_DEVSTRAP_SCRIPTS_DIR}/xcode-components.sh" || true
fi

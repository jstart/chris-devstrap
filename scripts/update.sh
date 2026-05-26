#!/usr/bin/env bash
# Update Homebrew and re-apply Brewfile from repo root.
# Brewfile.dev is installed when present (see chris_brew_bundle_dev_maybe in lib.sh); skip with CHRIS_DEVSTRAP_SKIP_DEV_BUNDLE=1.
# Optional: CHRIS_DEVSTRAP_CLEANUP=1 runs brew cleanup afterward.
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
cd "$CHRIS_DEVSTRAP_ROOT"

export CHRIS_DEVSTRAP_INTERACTIVE="${CHRIS_DEVSTRAP_INTERACTIVE:-0}"
[[ -t 1 ]] && CHRIS_DEVSTRAP_INTERACTIVE=1

_main() {
  banner "chris-devstrap update — $(date '+%Y-%m-%d %H:%M:%S')"
  step_info "Repo root: $CHRIS_DEVSTRAP_ROOT"
  hr

  if ! chris_eval_brew_shellenv; then
    step_warn "Homebrew not found at /opt/homebrew/bin/brew or /usr/local/bin/brew"
    exit 1
  fi

  step_start "brew update"
  brew update

  step_start "brew upgrade (all outdated formulae/casks)"
  brew upgrade

  step_start "brew bundle install — $CHRIS_DEVSTRAP_ROOT/Brewfile (--no-upgrade after brew upgrade)"
  brew bundle install --no-upgrade --file="$CHRIS_DEVSTRAP_ROOT/Brewfile"
  chris_brew_bundle_dev_maybe

  if [[ "${CHRIS_DEVSTRAP_INCLUDE_HEAVY:-0}" == "1" ]] && [[ -f "${CHRIS_DEVSTRAP_ROOT}/Brewfile.heavy" ]]; then
    step_start "brew bundle install — Brewfile.heavy (--no-upgrade)"
    brew bundle install --no-upgrade --file="${CHRIS_DEVSTRAP_ROOT}/Brewfile.heavy"
  fi

  if [[ "${CHRIS_DEVSTRAP_CLEANUP:-0}" == "1" ]]; then
    step_start "brew cleanup (CHRIS_DEVSTRAP_CLEANUP=1)"
    brew cleanup
  else
    step_info "Skipping brew cleanup (set CHRIS_DEVSTRAP_CLEANUP=1 to enable)"
  fi

  hr
  step_ok "Update complete"
}

_main "$@"

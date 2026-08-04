#!/usr/bin/env bash
# Update Homebrew and re-apply Brewfile from repo root.
# Brewfile.dev is installed when present (see chris_brew_bundle_dev_maybe in lib.sh); skip with CHRIS_DEVSTRAP_SKIP_DEV_BUNDLE=1.
#
# Env:
#   CHRIS_DEVSTRAP_DRY_RUN=1       Print actions without running brew update/upgrade/bundle.
#   CHRIS_DEVSTRAP_INCLUDE_HEAVY=1 Also reconcile Brewfile.heavy (check then install).
#   CHRIS_DEVSTRAP_REFRESH=1       After brew, re-run idempotent config scripts so repo
#                                  drift (defaults / dock / sidebar / git-config /
#                                  raycast / iterm) propagates without a full bootstrap.
#                                  Never touches git-ssh-setup, headshot, heavy-installs,
#                                  or xcode-components.
#   CHRIS_DEVSTRAP_CLEANUP=1       brew cleanup after bundle.
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
cd "$CHRIS_DEVSTRAP_ROOT"

chris_export_interactive_if_tty
export CHRIS_DEVSTRAP_DRY_RUN="${CHRIS_DEVSTRAP_DRY_RUN:-0}"

_main() {
  banner "chris-devstrap update — $(date '+%Y-%m-%d %H:%M:%S')"
  step_info "Repo root: $CHRIS_DEVSTRAP_ROOT"
  step_info "dry_run=${CHRIS_DEVSTRAP_DRY_RUN}; refresh=${CHRIS_DEVSTRAP_REFRESH:-0}"
  hr

  if ! chris_eval_brew_shellenv; then
    step_warn "Homebrew not found at /opt/homebrew/bin/brew or /usr/local/bin/brew"
    exit 1
  fi

  if [[ "$CHRIS_DEVSTRAP_DRY_RUN" == 1 ]]; then
    step_info "Dry-run: would run brew update, brew upgrade, then bundle check/install."
  else
    chris_raise_open_files_limit

    step_start "brew update"
    brew update

    step_start "brew upgrade (all outdated formulae/casks)"
    brew upgrade
  fi

  # D1: use chris_brew_bundle_if_needed so re-runs without drift skip install.
  chris_brew_bundle_if_needed "$CHRIS_DEVSTRAP_ROOT/Brewfile" "Brewfile"
  chris_brew_bundle_dev_maybe

  if [[ "${CHRIS_DEVSTRAP_INCLUDE_HEAVY:-0}" == "1" ]] && [[ -f "${CHRIS_DEVSTRAP_ROOT}/Brewfile.heavy" ]]; then
    chris_brew_bundle_if_needed "${CHRIS_DEVSTRAP_ROOT}/Brewfile.heavy" "Brewfile.heavy"
  fi

  if [[ "${CHRIS_DEVSTRAP_CLEANUP:-0}" == "1" ]]; then
    if [[ "$CHRIS_DEVSTRAP_DRY_RUN" == 1 ]]; then
      step_info "Dry-run: would run brew cleanup"
    else
      step_start "brew cleanup (CHRIS_DEVSTRAP_CLEANUP=1)"
      brew cleanup
    fi
  else
    step_info "Skipping brew cleanup (set CHRIS_DEVSTRAP_CLEANUP=1 to enable)"
  fi

  # D2: opt-in refresh — re-run idempotent config scripts so repo changes
  # (Brewfile, dock-add.tsv, macos-defaults.sh, etc.) propagate after a git pull
  # without forcing a full bootstrap. Skips interactive / destructive / multi-GB scripts.
  if [[ "${CHRIS_DEVSTRAP_REFRESH:-0}" == "1" ]]; then
    hr
    step_start "Refresh: re-run idempotent config scripts (CHRIS_DEVSTRAP_REFRESH=1)"
    local refresh_scripts=(
      git-config.sh
      gh-extensions.sh
      macos-defaults.sh
      finder-sidebar.sh
      dock.sh
      raycast-hotkey.sh
      raycast-script-commands.sh
      iterm.sh
    )
    local s
    for s in "${refresh_scripts[@]}"; do
      hr
      step_info "refresh → ${s}"
      bash "${CHRIS_DEVSTRAP_SCRIPTS_DIR}/${s}" || step_warn "${s} exited non-zero (continuing)"
    done
  else
    step_info "Skipping config refresh (set CHRIS_DEVSTRAP_REFRESH=1 to re-run defaults/dock/sidebar/git-config/raycast/iterm)."
  fi

  hr
  step_ok "Update complete"
}

_main "$@"

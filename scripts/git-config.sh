#!/usr/bin/env bash
# Recommended global Git defaults (idempotent). Does not set user.name / user.email.
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

_git_set_if_missing() {
  local key="$1" value="$2"
  if git config --global --get "$key" >/dev/null 2>&1; then
    step_info "git config --global ${key} already set — skipping"
    return 0
  fi
  chris_run git config --global "$key" "$value"
}

_main() {
  hr
  step_start "Git global defaults (chris-devstrap)"
  if ! command -v git &>/dev/null; then
    step_warn "git not on PATH — skipping git-config"
    return 0
  fi

  _git_set_if_missing init.defaultBranch main
  _git_set_if_missing fetch.prune true
  # Integrate remote branches with merge on pull (not rebase) when this key was never set.
  _git_set_if_missing pull.rebase false
  _git_set_if_missing rerere.enabled true

  chris_manual_todo "git config --global user.name '…' and user.email '…' when ready (not set by this script)."
  chris_manual_todo "Commit signing (SSH or GPG): https://docs.github.com/en/authentication/managing-commit-signature-verification"
  step_ok "Git global defaults applied (where missing)"
}

_main "$@"

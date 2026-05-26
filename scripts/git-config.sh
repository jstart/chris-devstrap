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
  # zdiff3 shows the original "ancestor" hunk inside conflict markers (Git 2.35+, pairs well with delta).
  _git_set_if_missing merge.conflictStyle zdiff3

  # delta (git-delta): syntax-aware pager. Idempotent via _git_set_if_missing — users who
  # already have core.pager / interactive.diffFilter set keep their existing config.
  if command -v delta &>/dev/null; then
    step_info "git-delta detected — wiring core.pager + delta.* (only where unset)"
    _git_set_if_missing core.pager delta
    _git_set_if_missing interactive.diffFilter 'delta --color-only'
    _git_set_if_missing delta.navigate true
    _git_set_if_missing delta.side-by-side true
    _git_set_if_missing delta.line-numbers true
  else
    step_info "git-delta not on PATH — skipping delta.* git config (install via Brewfile)"
  fi

  chris_manual_todo_block "Git identity:" \
    "  git config --global user.name '…' and user.email '…' when ready (not set by this script)" \
    "  Commit signing (SSH or GPG): https://docs.github.com/en/authentication/managing-commit-signature-verification"
  step_ok "Git global defaults applied (where missing)"
}

_main "$@"

#!/usr/bin/env bash
# Recommended global Git defaults (idempotent). Always sets user.name (default: Christopher Truman).
# user.email is collected in the guided checklist via a pre-filled iTerm tab.
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

  # Always set display name (override with CHRIS_DEVSTRAP_GIT_USER_NAME).
  local desired_name="${CHRIS_DEVSTRAP_GIT_USER_NAME:-Christopher Truman}"
  local cur_name=""
  cur_name="$(git config --global --get user.name 2>/dev/null || true)"
  if [[ "$cur_name" == "$desired_name" ]]; then
    step_ok "git user.name already '${desired_name}'"
  else
    chris_run git config --global user.name "$desired_name"
    step_ok "git user.name → '${desired_name}'"
  fi

  # Guided checklist step 3 (prio 30): open iTerm tab with email command ready.
  # Skip the email prompt when already set unless CHRIS_DEVSTRAP_FORCE_GIT_EMAIL=1.
  local cur_email=""
  cur_email="$(git config --global --get user.email 2>/dev/null || true)"
  if [[ -n "$cur_email" && "${CHRIS_DEVSTRAP_FORCE_GIT_EMAIL:-0}" != "1" ]]; then
    step_ok "git user.email already set (${cur_email}) — skipping email checklist step"
  else
    chris_manual_todo_block_prio 30 ACTION=iterm_git_email \
      "Git identity — set user.email:" \
      "  user.name is already '${desired_name}'" \
      "  A new iTerm tab opens with: git config --global user.email " \
      "  Type your email, press Enter in that tab, then continue here" \
      "  Commit signing (SSH or GPG): https://docs.github.com/en/authentication/managing-commit-signature-verification"
  fi

  step_ok "Git global defaults applied (where missing)"
}

_main "$@"

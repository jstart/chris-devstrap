#!/usr/bin/env bash
# Shared helpers for chris-devstrap (sourced by other scripts; do not execute directly).
# shellcheck shell=bash

CHRIS_DEVSTRAP_SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHRIS_DEVSTRAP_ROOT="$(cd "$CHRIS_DEVSTRAP_SCRIPTS_DIR/.." && pwd)"
# shellcheck disable=SC2034
ROOT="${CHRIS_DEVSTRAP_ROOT}"

# shellcheck source=ui.sh
source "$CHRIS_DEVSTRAP_SCRIPTS_DIR/ui.sh"

# Print Homebrew prefix (/opt/homebrew or /usr/local) or return 1 if brew is missing.
chris_brew_prefix_path() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    printf '%s\n' /opt/homebrew
    return 0
  fi
  if [[ -x /usr/local/bin/brew ]]; then
    printf '%s\n' /usr/local
    return 0
  fi
  return 1
}

# Put brew on PATH in the current shell (eval shellenv). Returns 1 if brew is missing.
chris_eval_brew_shellenv() {
  local p
  if ! p="$(chris_brew_prefix_path)"; then
    return 1
  fi
  eval "$("${p}/bin/brew" shellenv)"
}

# When Brewfile.dev exists in the repo, run brew bundle install for it unless opted out.
# Opt out: CHRIS_DEVSTRAP_SKIP_DEV_BUNDLE=1
chris_brew_bundle_dev_maybe() {
  local dev_file="${CHRIS_DEVSTRAP_ROOT}/Brewfile.dev"
  [[ -f "$dev_file" ]] || return 0
  if [[ "${CHRIS_DEVSTRAP_SKIP_DEV_BUNDLE:-0}" == "1" ]]; then
    step_info "Brewfile.dev skipped (CHRIS_DEVSTRAP_SKIP_DEV_BUNDLE=1)"
    return 0
  fi
  step_start "brew bundle install — Brewfile.dev (--no-upgrade)"
  brew bundle install --no-upgrade --file="$dev_file"
}

# Run a command, or print it when CHRIS_DEVSTRAP_DRY_RUN=1 (bootstrap exports this).
chris_run() {
  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
    if _chris_ui_use_color; then
      printf '%s[dry-run]%s' "$UI_YELLOW" "$UI_RESET"
    else
      printf '[dry-run]'
    fi
    for a in "$@"; do printf ' %q' "$a"; done
    printf '\n'
    return 0
  fi
  "$@"
}

# One line for the end-of-bootstrap checklist (bootstrap sets CHRIS_DEVSTRAP_MANUAL_TODOS_FILE).
chris_manual_todo() {
  local msg="$*"
  [[ -z "$msg" ]] && return 0
  [[ -z "${CHRIS_DEVSTRAP_MANUAL_TODOS_FILE:-}" ]] && return 0
  if [[ -f "$CHRIS_DEVSTRAP_MANUAL_TODOS_FILE" ]] && grep -qFx "$msg" "$CHRIS_DEVSTRAP_MANUAL_TODOS_FILE" 2>/dev/null; then
    return 0
  fi
  printf '%s\n' "$msg" >>"$CHRIS_DEVSTRAP_MANUAL_TODOS_FILE"
}

chris_print_manual_todos() {
  [[ -n "${CHRIS_DEVSTRAP_MANUAL_TODOS_FILE:-}" && -s "$CHRIS_DEVSTRAP_MANUAL_TODOS_FILE" ]] || return 0
  hr
  step_start "Manual follow-ups (todo)"
  while IFS= read -r line || [[ -n "${line:-}" ]]; do
    [[ -z "${line// }" ]] && continue
    step_info "Next: $line"
  done <"$CHRIS_DEVSTRAP_MANUAL_TODOS_FILE"
  rm -f "$CHRIS_DEVSTRAP_MANUAL_TODOS_FILE"
}

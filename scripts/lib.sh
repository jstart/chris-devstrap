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

# Queue a title plus indented continuation lines (folded into one guided step).
chris_manual_todo_block() {
  [[ $# -lt 1 ]] && return 0
  chris_manual_todo "$1"
  shift
  local line
  for line in "$@"; do
    chris_manual_todo "$line"
  done
}

# Shared re-run command for Brewfile.heavy failures / skips.
chris_heavy_install_manual_msg() {
  local heavy_file="${1:-${CHRIS_DEVSTRAP_ROOT}/Brewfile.heavy}"
  printf 'Heavy installs deferred. After signing into Apple ID + Mac App Store, run: brew bundle install --no-upgrade --file=%s' "$heavy_file"
}

# Print queued manual steps. When interactive (TTY bootstrap, not dry-run), walks the user
# through each line and waits for Enter on /dev/tty before the next (done or skipped for now).
# Opt out: CHRIS_DEVSTRAP_SKIP_MANUAL_GUIDE=1 (prints the same list as before, no pauses).
chris_print_manual_todos() {
  [[ -n "${CHRIS_DEVSTRAP_MANUAL_TODOS_FILE:-}" && -s "$CHRIS_DEVSTRAP_MANUAL_TODOS_FILE" ]] || return 0

  local tmp="$CHRIS_DEVSTRAP_MANUAL_TODOS_FILE"
  local use_guide=1
  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]] ||
    [[ "${CHRIS_DEVSTRAP_INTERACTIVE:-0}" != 1 ]] ||
    [[ "${CHRIS_DEVSTRAP_SKIP_MANUAL_GUIDE:-0}" == 1 ]] ||
    [[ ! -r /dev/tty ]]; then
    use_guide=0
  fi

  # Fold indented continuation lines into the previous item so a single logical
  # follow-up (e.g. "iTerm2 → Natural Text Editing:" with sub-bullets) is one
  # checklist step instead of N. Continuation = leading whitespace.
  local -a items=()
  local cur=""
  while IFS= read -r line || [[ -n "${line:-}" ]]; do
    [[ -z "${line// }" ]] && continue
    if [[ -n "$cur" && "$line" =~ ^[[:space:]] ]]; then
      cur+=$'\n'"$line"
      continue
    fi
    [[ -n "$cur" ]] && items+=("$cur")
    cur="$line"
  done <"$tmp"
  [[ -n "$cur" ]] && items+=("$cur")
  rm -f "$tmp"

  local n="${#items[@]}"
  [[ "$n" -eq 0 ]] && return 0

  if [[ "$use_guide" != 1 ]]; then
    hr
    step_start "Manual follow-ups (todo)"
    local line
    for line in "${items[@]}"; do
      step_info "Next: $line"
    done
    return 0
  fi

  hr
  step_start "Manual follow-ups — guided checklist (${n} step(s))"
  step_info "Press Enter after each step when you are done, or to skip it for now."
  local i
  for ((i = 0; i < n; i++)); do
    hr
    printf '%sStep %s of %s%s\n' "$UI_CYAN" "$((i + 1))" "$n" "$UI_RESET"
    printf '%s\n\n' "${items[$i]}"
    printf '%sPress Enter to continue…%s\n' "$UI_DIM" "$UI_RESET"
    read -r _ </dev/tty || true
  done
  hr
  step_ok "Manual follow-ups acknowledged (${n} step(s))."
}

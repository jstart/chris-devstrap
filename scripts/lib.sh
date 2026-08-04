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

# True when /Applications/Xcode.app exists, OR active developer dir is an Xcode bundle
# (xcode-select -p points inside .app/Contents/Developer). CLT-only Macs return false.
chris_xcode_app_installed() {
  [[ -d "/Applications/Xcode.app" ]] && return 0
  local p
  p="$(xcode-select -p 2>/dev/null || true)"
  [[ -n "$p" && "$p" == *".app/Contents/Developer"* ]]
}

# Tracks whether any defaults_write_if_diff actually wrote in this script run.
# Scripts set this to 0 at the start (or rely on the unset default of "0") and pass it
# to chris_killall_if_changed to gate UI restarts.
: "${CHRIS_DEVSTRAP_DEFAULTS_CHANGED:=0}"
export CHRIS_DEVSTRAP_DEFAULTS_CHANGED

# defaults read | normalize-to-string; "__MISSING__" sentinel for unset keys.
_chris_defaults_read_normalized() {
  local args=("$@") raw
  if ! raw="$(defaults "${args[@]}" 2>/dev/null)"; then
    printf '__MISSING__'
    return 0
  fi
  # `defaults read` returns floats like "0.15" and ints like "1" / strings unquoted.
  # Strip leading/trailing whitespace and trailing newline; leave the value as-is.
  printf '%s' "${raw%$'\n'}"
}

# Compare current `defaults read` value to expected; write only if different.
# Usage:
#   chris_defaults_write_if_diff <domain> <key> <-type|--> <expected>
#   chris_defaults_write_if_diff -currentHost <domain> <key> <-type|--> <expected>
# Type tokens map to defaults: -string|-bool|-int|-float|-data|-array|-dict|--
# Bools normalize to "0"/"1" before compare. Sets CHRIS_DEVSTRAP_DEFAULTS_CHANGED=1
# whenever a write happens. Honors CHRIS_DEVSTRAP_DRY_RUN via chris_run.
chris_defaults_write_if_diff() {
  local prefix=""
  if [[ "$1" == "-currentHost" || "$1" == "-host" ]]; then
    prefix="$1"
    shift
  fi
  local domain="$1" key="$2" type="$3" expected="$4"

  local read_args=()
  [[ -n "$prefix" ]] && read_args+=("$prefix")
  read_args+=(read "$domain" "$key")

  local cur normalized_expected="$expected"
  cur="$(_chris_defaults_read_normalized "${read_args[@]}")"

  # Bool comparison: 1/0 ↔ true/false/YES/NO
  case "$type" in
    -bool)
      case "$expected" in true | TRUE | YES | yes | 1) normalized_expected=1 ;; *) normalized_expected=0 ;; esac
      case "$cur" in true | TRUE | YES | yes | 1) cur=1 ;; false | FALSE | NO | no | 0) cur=0 ;; esac
      ;;
  esac

  if [[ "$cur" == "$normalized_expected" ]]; then
    return 0
  fi

  local write_args=()
  [[ -n "$prefix" ]] && write_args+=("$prefix")
  write_args+=(write "$domain" "$key")
  [[ "$type" != "--" ]] && write_args+=("$type")
  write_args+=("$expected")

  chris_run defaults "${write_args[@]}" || return 0
  CHRIS_DEVSTRAP_DEFAULTS_CHANGED=1
  export CHRIS_DEVSTRAP_DEFAULTS_CHANGED
}

# killall apps only when CHRIS_DEVSTRAP_DEFAULTS_CHANGED=1. Reset after.
# Usage: chris_killall_if_changed Finder SystemUIServer Dock
chris_killall_if_changed() {
  [[ "${CHRIS_DEVSTRAP_DEFAULTS_CHANGED:-0}" == "1" ]] || {
    step_info "Skipping ${*} restart — no defaults changed in this script."
    return 0
  }
  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
    local app
    for app in "$@"; do chris_run killall "$app"; done
  else
    local app
    for app in "$@"; do killall "$app" 2>/dev/null || true; done
  fi
}

# Set + export CHRIS_DEVSTRAP_INTERACTIVE based on a usable terminal.
# Honors a pre-set value. curl|bash leaves stdin as the pipe, and bootstrap later
# tees stdout — so also treat a usable /dev/tty (controlling terminal) as interactive.
chris_export_interactive_if_tty() {
  if [[ -n "${CHRIS_DEVSTRAP_INTERACTIVE:-}" ]]; then
    export CHRIS_DEVSTRAP_INTERACTIVE
    return 0
  fi
  CHRIS_DEVSTRAP_INTERACTIVE=0
  if [[ -t 1 ]] || [[ -t 0 ]] || { [[ -r /dev/tty ]] && [[ -w /dev/tty ]]; }; then
    CHRIS_DEVSTRAP_INTERACTIVE=1
  fi
  export CHRIS_DEVSTRAP_INTERACTIVE
}

# Raise the soft open-files limit when it is below target.
# Fresh macOS shells often start at 256; brew bundle / upgrade open many FDs and hit
# "Too many open files". Best-effort — never fails the caller. Override target with
# CHRIS_DEVSTRAP_OPEN_FILES_LIMIT (default 10240).
chris_raise_open_files_limit() {
  local target="${CHRIS_DEVSTRAP_OPEN_FILES_LIMIT:-10240}"
  local cur hard

  cur="$(ulimit -n 2>/dev/null || printf '0')"
  if [[ "$cur" == "unlimited" ]]; then
    return 0
  fi
  if [[ "$cur" =~ ^[0-9]+$ ]] && ((cur >= target)); then
    return 0
  fi

  if ulimit -n "$target" 2>/dev/null; then
    if declare -f step_info &>/dev/null; then
      step_info "Raised open-files soft limit: ${cur} → $(ulimit -n) (avoids brew 'Too many open files')"
    fi
    return 0
  fi

  hard="$(ulimit -Hn 2>/dev/null || printf '0')"
  if [[ "$hard" == "unlimited" ]]; then
    hard="$target"
  fi
  if [[ "$hard" =~ ^[0-9]+$ ]] && ((hard > cur)) && ulimit -n "$hard" 2>/dev/null; then
    if declare -f step_info &>/dev/null; then
      step_info "Raised open-files soft limit: ${cur} → $(ulimit -n) (hard cap; target was ${target})"
    fi
    return 0
  fi

  if declare -f step_warn &>/dev/null; then
    step_warn "Could not raise open-files limit (ulimit -n=${cur}); brew may hit 'Too many open files'."
  fi
  return 0
}

# Run `brew bundle check --no-upgrade`; install only when something from the file is missing.
# On a fresh Mac the check fails and install runs; on re-runs satisfied bundles are skipped.
chris_brew_bundle_if_needed() {
  local file="$1"
  local label="${2:-$(basename "$file")}"

  chris_raise_open_files_limit

  step_start "brew bundle check (--no-upgrade): ${label}"
  if brew bundle check --no-upgrade --file="$file" --verbose; then
    step_ok "${label} satisfied — nothing to install"
    return 0
  fi

  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
    step_info "Dry-run: would run brew bundle install --no-upgrade --file=${file}"
    return 0
  fi

  step_start "brew bundle install (--no-upgrade): ${label}"
  brew bundle install --no-upgrade --file="$file"
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
  chris_brew_bundle_if_needed "$dev_file" "Brewfile.dev"
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

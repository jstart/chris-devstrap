#!/usr/bin/env bash
# chris-devstrap — one-shot macOS bootstrap (see README.md)
# Usage: ./bootstrap.sh [--dry-run] [--help] [subcommand]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

CHRIS_DEVSTRAP_DRY_RUN=0
SUBCOMMAND=""

_usage() {
  cat <<EOF
Usage: $0 [--dry-run] [--verbose] [--help] [subcommand]

  --dry-run   Print commands for brew bundle / defaults / dockutil / etc. without
              applying. Skips brew bundle install and GitHub SSH setup.
  --verbose   Trace shell commands (set -x) during this bootstrap run.

Subcommands:
  (none)       Full bootstrap (safe to re-run; see README).
  rerun        Same as no subcommand — full bootstrap again.
  doctor       brew doctor (if brew is on PATH) + same checks as healthcheck.
  healthcheck  Run ${ROOT}/scripts/healthcheck.sh
  update       Run ${ROOT}/scripts/update.sh (brew update / upgrade / bundle).

Examples:
  $0
  $0 --dry-run
  $0 --verbose
  $0 doctor
  $0 healthcheck
  $0 update
EOF
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) CHRIS_DEVSTRAP_DRY_RUN=1 ;;
    --verbose) export CHRIS_DEVSTRAP_VERBOSE=1 ;;
    -h | --help)
      _usage
      exit 0
      ;;
    doctor | healthcheck | update | rerun)
      if [[ -n "$SUBCOMMAND" && "$SUBCOMMAND" != "$arg" ]]; then
        printf 'Only one subcommand allowed (got %s and %s).\n' "$SUBCOMMAND" "$arg" >&2
        exit 1
      fi
      SUBCOMMAND="$arg"
      ;;
    *)
      printf 'Unknown argument: %s\n\n' "$arg" >&2
      _usage >&2
      exit 1
      ;;
  esac
done

case "${SUBCOMMAND:-}" in
  doctor)
    export CHRIS_DEVSTRAP_INTERACTIVE=0
    [[ -t 1 ]] && export CHRIS_DEVSTRAP_INTERACTIVE=1
    # shellcheck source=scripts/lib.sh
    source "$ROOT/scripts/lib.sh"
    if [[ "${CHRIS_DEVSTRAP_VERBOSE:-0}" == "1" ]]; then
      set -x
    fi
    banner "doctor — $(date '+%Y-%m-%d %H:%M:%S')"
    if chris_eval_brew_shellenv; then
      step_start "brew doctor (informational — warnings are normal)"
      set +e
      brew doctor || true
      set -e
    else
      step_warn "brew not on PATH — skipping brew doctor (install Homebrew or run from a login shell with shellenv)."
    fi
    step_info "Running healthcheck next — see README.md » Troubleshooting if anything fails."
    exec bash "$ROOT/scripts/healthcheck.sh"
    ;;
  healthcheck) exec bash "$ROOT/scripts/healthcheck.sh" ;;
  update) exec bash "$ROOT/scripts/update.sh" ;;
  rerun | "") ;; # fall through to full bootstrap
  *)
    printf 'Unknown subcommand: %s\n' "$SUBCOMMAND" >&2
    exit 1
    ;;
esac

export CHRIS_DEVSTRAP_DRY_RUN
export CHRIS_DEVSTRAP_VERBOSE="${CHRIS_DEVSTRAP_VERBOSE:-0}"

export CHRIS_DEVSTRAP_INTERACTIVE=0
[[ -t 1 ]] && CHRIS_DEVSTRAP_INTERACTIVE=1
export CHRIS_DEVSTRAP_INTERACTIVE

# shellcheck source=scripts/lib.sh
source "$ROOT/scripts/lib.sh"
if [[ "$CHRIS_DEVSTRAP_VERBOSE" == "1" ]]; then
  set -x
fi
# shellcheck source=scripts/sudo-keepalive.sh
source "$ROOT/scripts/sudo-keepalive.sh"

CHRIS_DEVSTRAP_MANUAL_TODOS_FILE="${TMPDIR:-/tmp}/chris-devstrap-manual-$$.txt"
export CHRIS_DEVSTRAP_MANUAL_TODOS_FILE
: >"$CHRIS_DEVSTRAP_MANUAL_TODOS_FILE"

_should_run_git_ssh_setup() {
  local want="${CHRIS_DEVSTRAP_GIT_SSH_URL:-git@github.com:jstart/chris-devstrap.git}"

  [[ "${CHRIS_DEVSTRAP_SKIP_SSH:-0}" == "1" ]] && return 1
  [[ "${CHRIS_DEVSTRAP_FORCE_SSH_SETUP:-0}" == "1" ]] && return 0

  if [[ ! -d "$ROOT/.git" ]]; then
    return 0
  fi

  if ! git -C "$ROOT" remote get-url origin >/dev/null 2>&1; then
    return 0
  fi

  local cur
  cur="$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)"
  [[ -z "$cur" ]] && return 0

  if [[ "$cur" == "$want" ]]; then
    return 1
  fi

  if [[ "$cur" == git@* ]] || [[ "$cur" == ssh://* ]]; then
    return 0
  fi

  return 0
}

LOG_DIR="${HOME}/Library/Logs"
LOG_FILE="${LOG_DIR}/chris-devstrap.log"
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

CHRIS_DEVSTRAP_BOOT_START_SEC="$(date +%s)"

banner "macOS bootstrap — $(date '+%Y-%m-%d %H:%M:%S')"
step_info "Log file: $LOG_FILE"
step_info "dry_run=${CHRIS_DEVSTRAP_DRY_RUN}"
hr

step_progress 1 9 "Homebrew (Xcode CLT, install, shellenv)"
bash "$ROOT/scripts/brew.sh"

if ! chris_eval_brew_shellenv; then
  if [[ "$CHRIS_DEVSTRAP_DRY_RUN" == 1 ]]; then
    step_warn "Homebrew not on PATH after brew.sh — skipping brew bundle and remaining scripts."
    chris_manual_todo "Install Homebrew or fix PATH, then re-run ./bootstrap.sh (or run brew.sh and open a new shell)."
    chris_print_manual_todos
    exit 0
  fi
  step_warn "Homebrew not found after brew.sh; aborting."
  exit 1
fi

chris_devstrap_sudo_prime_and_keepalive

step_progress 2 9 "brew bundle (check + install)"
step_start "brew bundle check (--no-upgrade: presence, not latest)"
brew bundle check --no-upgrade --file="$ROOT/Brewfile" --verbose || true

if [[ "$CHRIS_DEVSTRAP_DRY_RUN" == 1 ]]; then
  step_info "Skipping brew bundle install in dry-run (run without --dry-run to apply)."
  chris_manual_todo "Re-run without --dry-run to apply brew bundle, defaults, Dock, and GitHub SSH."
else
  step_start "brew bundle install (--no-upgrade: install missing only)"
  brew bundle install --no-upgrade --file="$ROOT/Brewfile"
  chris_brew_bundle_dev_maybe
fi

step_progress 3 9 "Zsh + Oh My Zsh"
bash "$ROOT/scripts/zsh.sh"
bash "$ROOT/scripts/git-config.sh"

step_progress 4 9 "macOS defaults (Finder, trackpad, screenshots, …)"
bash "$ROOT/scripts/macos-defaults.sh"

step_progress 5 9 "Xcode (first launch + iOS Simulator runtime)"
if [[ "$CHRIS_DEVSTRAP_DRY_RUN" == 1 ]]; then
  step_info "Skipping Xcode components: dry-run (full Xcode only; see README: Xcode → Settings → Components)."
elif [[ -d "/Applications/Xcode.app" ]] || xcode-select -p 2>/dev/null | grep -Fq '.app/Contents/Developer'; then
  bash "$ROOT/scripts/xcode-components.sh" || true
else
  step_info "Skipping Xcode components: no /Applications/Xcode.app and active developer dir is not an Xcode.app bundle (CLT-only is normal until you install full Xcode)."
fi

step_progress 6 9 "Developer layout + Finder sidebar"
bash "$ROOT/scripts/finder-sidebar.sh"

step_progress 7 9 "Dock (defaults + dockutil)"
bash "$ROOT/scripts/dock.sh"

step_progress 8 9 "Raycast / Spotlight hotkey prep"
bash "$ROOT/scripts/raycast-hotkey.sh"

step_progress 9 9 "GitHub SSH + git origin"
if [[ "$CHRIS_DEVSTRAP_DRY_RUN" == 1 ]]; then
  step_info "Dry-run: skipping GitHub SSH setup. Full runs invoke ./scripts/git-ssh-setup.sh when needed (see README: idempotent rerun + CHRIS_DEVSTRAP_FORCE_SSH_SETUP)."
  chris_manual_todo "Run ./bootstrap.sh without --dry-run for GitHub SSH + origin when you are ready."
elif _should_run_git_ssh_setup; then
  bash "$ROOT/scripts/git-ssh-setup.sh"
else
  step_info "Skipping GitHub SSH setup: .git present and origin already matches CHRIS_DEVSTRAP_GIT_SSH_URL. To force: CHRIS_DEVSTRAP_FORCE_SSH_SETUP=1 ./bootstrap.sh"
fi

hr
banner "Bootstrap complete"
_elapsed_sec=$(( $(date +%s) - CHRIS_DEVSTRAP_BOOT_START_SEC ))
step_info "Bootstrap wall time: ${_elapsed_sec}s"
step_ok "Open a new terminal (or run: exec zsh) and review README.md for manual steps."

bash "$ROOT/scripts/iterm.sh"

chris_print_manual_todos

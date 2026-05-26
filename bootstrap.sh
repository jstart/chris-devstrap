#!/usr/bin/env bash
# chris-devstrap — one-shot macOS bootstrap (see README.md)
# Usage: ./bootstrap.sh [--dry-run] [--help] [subcommand]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

CHRIS_DEVSTRAP_BOOT_STEPS=10

CHRIS_DEVSTRAP_DRY_RUN=0
SUBCOMMAND=""

_usage() {
  cat <<EOF
Usage: $0 [--dry-run] [--verbose] [--help] [subcommand]

  --dry-run   Print commands for brew bundle / defaults / dockutil / etc. without
              applying. Skips brew bundle install and GitHub SSH setup.
  --verbose   Trace shell commands (set -x) during this bootstrap run.

Environment:
  CHRIS_DEVSTRAP_SKIP_MANUAL_GUIDE=1   At the end, print manual follow-ups as a list only
              (no Enter-to-continue prompts). CI / non-TTY runs behave this way automatically.

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
    --dry-run) export CHRIS_DEVSTRAP_DRY_RUN=1 ;;
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
    # shellcheck source=scripts/lib.sh
    source "$ROOT/scripts/lib.sh"
    chris_export_interactive_if_tty
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
export CHRIS_DEVSTRAP_SILENCE_UI_SOUNDS="${CHRIS_DEVSTRAP_SILENCE_UI_SOUNDS:-1}"

# shellcheck source=scripts/lib.sh
source "$ROOT/scripts/lib.sh"
chris_export_interactive_if_tty
if [[ "$CHRIS_DEVSTRAP_VERBOSE" == "1" ]]; then
  set -x
fi
# shellcheck source=scripts/sudo-keepalive.sh
source "$ROOT/scripts/sudo-keepalive.sh"

CHRIS_DEVSTRAP_MANUAL_TODOS_FILE="${TMPDIR:-/tmp}/chris-devstrap-manual-$$.txt"
export CHRIS_DEVSTRAP_MANUAL_TODOS_FILE
: >"$CHRIS_DEVSTRAP_MANUAL_TODOS_FILE"

CHRIS_DEVSTRAP_XCODE_AT_START=0
if chris_xcode_app_installed; then
  CHRIS_DEVSTRAP_XCODE_AT_START=1
fi

LOG_DIR="${HOME}/Library/Logs"
LOG_FILE="${LOG_DIR}/chris-devstrap.log"
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

CHRIS_DEVSTRAP_BOOT_START_SEC="$(date +%s)"

banner "macOS bootstrap — $(date '+%Y-%m-%d %H:%M:%S')"
step_info "Log file: $LOG_FILE"
step_info "dry_run=${CHRIS_DEVSTRAP_DRY_RUN}"
hr

step_progress 1 "$CHRIS_DEVSTRAP_BOOT_STEPS" "Command Line Tools + Homebrew (shellenv)"
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

step_progress 2 "$CHRIS_DEVSTRAP_BOOT_STEPS" "brew bundle (check + install)"
chris_brew_bundle_if_needed "$ROOT/Brewfile" "Brewfile"
if [[ "$CHRIS_DEVSTRAP_DRY_RUN" == 1 ]]; then
  chris_manual_todo "Re-run without --dry-run to apply brew bundle, defaults, Dock, and GitHub SSH."
else
  chris_brew_bundle_dev_maybe
fi

if [[ -f "$ROOT/Brewfile.heavy" ]] && [[ "${CHRIS_DEVSTRAP_SKIP_HEAVY:-0}" != "1" ]]; then
  chris_manual_todo_block "Apple ID + Mac App Store — required for Xcode via mas:" \
    "  System Settings → Apple Account → Sign In" \
    "  Open the App Store app and sign in — mas signin is not supported on modern macOS"
fi

step_progress 3 "$CHRIS_DEVSTRAP_BOOT_STEPS" "Zsh + Oh My Zsh + git defaults + gh extensions"
bash "$ROOT/scripts/zsh.sh"
bash "$ROOT/scripts/git-config.sh"
bash "$ROOT/scripts/gh-extensions.sh"

step_progress 4 "$CHRIS_DEVSTRAP_BOOT_STEPS" "macOS defaults (Finder, trackpad, screenshots, …) + user picture"
bash "$ROOT/scripts/macos-defaults.sh"

# headshot is grouped under step 4 (also writes user-visible config); intentionally not its own numbered step.
bash "$ROOT/scripts/headshot.sh"

step_progress 5 "$CHRIS_DEVSTRAP_BOOT_STEPS" "Xcode (first launch + iOS Simulator runtime)"
if [[ "$CHRIS_DEVSTRAP_DRY_RUN" == 1 ]]; then
  step_info "Skipping Xcode components: dry-run (full Xcode only; see README: Xcode → Settings → Components)."
elif [[ "$CHRIS_DEVSTRAP_XCODE_AT_START" == "1" ]]; then
  bash "$ROOT/scripts/xcode-components.sh" || true
else
  step_info "Skipping Xcode components for now — Xcode not installed yet; runs after heavy install in step ${CHRIS_DEVSTRAP_BOOT_STEPS}, or re-run bootstrap."
fi

step_progress 6 "$CHRIS_DEVSTRAP_BOOT_STEPS" "Developer layout + Finder sidebar"
bash "$ROOT/scripts/finder-sidebar.sh"

step_progress 7 "$CHRIS_DEVSTRAP_BOOT_STEPS" "Dock (defaults + dockutil)"
bash "$ROOT/scripts/dock.sh"

step_progress 8 "$CHRIS_DEVSTRAP_BOOT_STEPS" "Raycast / Spotlight hotkey prep + Script Commands"
bash "$ROOT/scripts/raycast-hotkey.sh"
bash "$ROOT/scripts/raycast-script-commands.sh"

step_progress 9 "$CHRIS_DEVSTRAP_BOOT_STEPS" "GitHub SSH + git origin"
if [[ "$CHRIS_DEVSTRAP_DRY_RUN" == 1 ]]; then
  step_info "Dry-run: skipping GitHub SSH setup. Full runs always invoke ./scripts/git-ssh-setup.sh (it skips when origin + ssh -T already pass)."
  step_info "See README for CHRIS_DEVSTRAP_FORCE_SSH_SETUP."
  chris_manual_todo "Run ./bootstrap.sh without --dry-run for GitHub SSH + origin when you are ready."
else
  bash "$ROOT/scripts/git-ssh-setup.sh"
fi

bash "$ROOT/scripts/iterm.sh"

if [[ ! -f "${HOME}/.ssh/id_ed25519" ]] && [[ ! -f "${HOME}/.ssh/id_ed25519.pub" ]]; then
  chris_manual_todo "Primary GitHub account: run ./scripts/github-account-add.sh for ~/.ssh/id_ed25519 as your default git@github.com identity."
fi

chris_print_manual_todos

step_progress "$CHRIS_DEVSTRAP_BOOT_STEPS" "$CHRIS_DEVSTRAP_BOOT_STEPS" "Heavy installs (Xcode via mas, Android Studio) — runs last so long downloads do not block earlier setup"
bash "$ROOT/scripts/heavy-installs.sh"

hr
banner "Bootstrap complete"
_elapsed_sec=$(( $(date +%s) - CHRIS_DEVSTRAP_BOOT_START_SEC ))
step_info "Bootstrap wall time: ${_elapsed_sec}s"
step_ok "Open a new terminal (or run: exec zsh) and review README.md for manual steps."

#!/usr/bin/env bash
# Heavy / interactive installs (deferred to the last bootstrap step).
# Apple ID + App Store sign-in is covered in the guided manual checklist (queued earlier in bootstrap).
#
# Env:
#   CHRIS_DEVSTRAP_SKIP_HEAVY=1           Skip entirely (queues a re-run command in the manual checklist).
#   CHRIS_DEVSTRAP_HEAVY_NONINTERACTIVE=1 Start downloads without Enter prompt (assumes signed in).
#   CHRIS_DEVSTRAP_DRY_RUN=1              Print what would happen; do not invoke brew bundle.
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# Xcode Mac App Store id (mas "Xcode", id: 497799835).
CHRIS_HEAVY_XCODE_MAS_ID="${CHRIS_HEAVY_XCODE_MAS_ID:-497799835}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  step_info "Skipping heavy installs: not macOS."
  exit 0
fi

HEAVY_FILE="${CHRIS_DEVSTRAP_ROOT}/Brewfile.heavy"
if [[ ! -f "$HEAVY_FILE" ]]; then
  step_info "No Brewfile.heavy — skipping heavy installs."
  exit 0
fi

if [[ "${CHRIS_DEVSTRAP_SKIP_HEAVY:-0}" == "1" ]]; then
  step_info "Skipping heavy installs (CHRIS_DEVSTRAP_SKIP_HEAVY=1)."
  chris_manual_todo "$(chris_heavy_install_manual_msg "$HEAVY_FILE")"
  exit 0
fi

_chris_fmt_elapsed() {
  local s="$1"
  if [[ "$s" -lt 60 ]]; then
    printf '%ds' "$s"
  else
    printf '%dm %ds' "$((s / 60))" "$((s % 60))"
  fi
}

# Run a long download with live progress when possible.
# bootstrap.sh does `exec > >(tee -a log)`, so stdout is not a TTY — that hides
# mas/brew progress bars. Attach the installer to /dev/tty when available.
_chris_heavy_run() {
  local label="$1"
  shift
  local start_sec end_sec st=0 hb_pid=""

  step_start "$label"
  start_sec="$(date +%s)"
  step_info "Started $(date '+%H:%M:%S') — leave this running (large download)."

  if [[ -r /dev/tty && -w /dev/tty ]]; then
    step_info "Live progress on this terminal (mas/brew progress bar)."
    # No elapsed heartbeat here — it would interleave with the in-place progress bar
    # via bootstrap's tee. mas/brew redraw the bar on /dev/tty directly.
    set +e
    "$@" </dev/tty >/dev/tty 2>/dev/tty
    st=$?
    set -e
  else
    step_info "No /dev/tty — showing elapsed-time updates (installer progress bars need a real terminal)."
    (
      local n=0
      while true; do
        sleep 20
        n=$((n + 20))
        step_info "… still running: ${label} ($(_chris_fmt_elapsed "$n") elapsed)"
      done
    ) &
    hb_pid=$!
    set +e
    "$@"
    st=$?
    set -e
    kill "$hb_pid" 2>/dev/null || true
    wait "$hb_pid" 2>/dev/null || true
  fi

  end_sec="$(date +%s)"
  if [[ "$st" -eq 0 ]]; then
    step_ok "${label} finished in $(_chris_fmt_elapsed "$((end_sec - start_sec))")"
  else
    step_warn "${label} failed (exit ${st}) after $(_chris_fmt_elapsed "$((end_sec - start_sec))")"
  fi
  return "$st"
}

_chris_need_xcode() {
  ! chris_xcode_app_installed
}

_chris_need_android_studio() {
  [[ ! -d "/Applications/Android Studio.app" ]]
}

step_start "Heavy / interactive installs (Xcode via mas, Android Studio, …)"
step_info "These can total ~15 GB. They run last so the rest of bootstrap finished while you were active."
step_info "Brewfile.heavy:"
sed 's/^/  /' "$HEAVY_FILE"

_need_xcode=0
_need_studio=0
_chris_need_xcode && _need_xcode=1
_chris_need_android_studio && _need_studio=1

if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-0}" == "1" ]]; then
  step_start "brew bundle check (--no-upgrade): Brewfile.heavy"
  if brew bundle check --no-upgrade --file="$HEAVY_FILE" --verbose; then
    step_info "Dry-run: Brewfile.heavy satisfied — nothing to install."
  else
    step_info "Dry-run: would download with live progress:"
    [[ "$_need_xcode" == "1" ]] && step_info "  • Xcode via mas install ${CHRIS_HEAVY_XCODE_MAS_ID} (~7–12+ GB)"
    [[ "$_need_studio" == "1" ]] && step_info "  • Android Studio via brew install --cask android-studio (~1 GB)"
    step_info "  then: brew bundle install --no-upgrade --file=${HEAVY_FILE} for any remaining entries"
  fi
  exit 0
fi

step_start "brew bundle check (--no-upgrade): Brewfile.heavy"
if brew bundle check --no-upgrade --file="$HEAVY_FILE" --verbose; then
  step_ok "Brewfile.heavy satisfied — skipping heavy downloads"
  if chris_xcode_app_installed; then
    step_info "Xcode present — running first-launch components if still needed…"
    bash "${CHRIS_DEVSTRAP_SCRIPTS_DIR}/xcode-components.sh" || true
  fi
  exit 0
fi

hr
step_info "Queued heavy downloads:"
if [[ "$_need_xcode" == "1" ]]; then
  step_info "  • Xcode — App Store via mas (~7–12+ GB); progress bar on this terminal"
else
  step_info "  • Xcode — already present, skip"
fi
if [[ "$_need_studio" == "1" ]]; then
  step_info "  • Android Studio — Homebrew cask (~1 GB); brew download progress on this terminal"
else
  step_info "  • Android Studio — already present, skip"
fi

_chris_heavy_interactive=0
if [[ "${CHRIS_DEVSTRAP_HEAVY_NONINTERACTIVE:-0}" != "1" ]] \
  && [[ "${CHRIS_DEVSTRAP_INTERACTIVE:-0}" == "1" ]] \
  && [[ -r /dev/tty ]]; then
  _chris_heavy_interactive=1
fi

if [[ "$_chris_heavy_interactive" == "1" ]]; then
  hr
  printf '%sPress Enter to start heavy downloads, or type s then Enter to skip.%s\n' "$UI_DIM" "$UI_RESET"
  reply=""
  IFS= read -r reply </dev/tty || {
    step_info "Skipping heavy installs (read interrupted)."
    chris_manual_todo "$(chris_heavy_install_manual_msg "$HEAVY_FILE")"
    exit 0
  }
  reply_lc="$(printf '%s' "$reply" | tr '[:upper:]' '[:lower:]')"
  case "$reply_lc" in
    s | skip | n | no)
      step_info "Skipping heavy installs for this run."
      chris_manual_todo "$(chris_heavy_install_manual_msg "$HEAVY_FILE")"
      exit 0
      ;;
  esac
else
  step_info "Non-interactive run — starting heavy downloads. Set CHRIS_DEVSTRAP_SKIP_HEAVY=1 to skip."
fi

chris_raise_open_files_limit

_failures=0

if [[ "$_need_xcode" == "1" ]]; then
  if ! command -v mas >/dev/null 2>&1; then
    step_warn "mas not on PATH — install mas from Brewfile, then: mas install ${CHRIS_HEAVY_XCODE_MAS_ID}"
    _failures=1
  elif ! _chris_heavy_run "Xcode (mas install ${CHRIS_HEAVY_XCODE_MAS_ID}, often 7–12+ GB)" \
    mas install "$CHRIS_HEAVY_XCODE_MAS_ID"; then
    _failures=1
  fi
else
  step_ok "Xcode already installed — skip download"
fi

if [[ "$_need_studio" == "1" ]]; then
  if ! command -v brew >/dev/null 2>&1; then
    step_warn "brew not on PATH — cannot install android-studio cask."
    _failures=1
  elif ! _chris_heavy_run "Android Studio (brew cask, ~1 GB)" \
    brew install --cask android-studio; then
    _failures=1
  fi
else
  step_ok "Android Studio already installed — skip download"
fi

# Reconcile any other Brewfile.heavy entries (or retries if an individual install failed).
if ! brew bundle check --no-upgrade --file="$HEAVY_FILE" >/dev/null 2>&1; then
  if ! _chris_heavy_run "Remaining Brewfile.heavy entries (brew bundle)" \
    brew bundle install --no-upgrade --file="$HEAVY_FILE"; then
    _failures=1
  fi
fi

if [[ "$_failures" -ne 0 ]]; then
  step_warn "One or more heavy installs failed (see output above)."
  chris_manual_todo "$(chris_heavy_install_manual_msg "$HEAVY_FILE")"
  exit 0
fi

step_ok "Heavy installs finished."

if chris_xcode_app_installed; then
  step_info "Xcode present after heavy install — running first-launch components…"
  bash "${CHRIS_DEVSTRAP_SCRIPTS_DIR}/xcode-components.sh" || true
fi

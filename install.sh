#!/usr/bin/env bash
# Remote bootstrap entrypoint (macOS only).
# Quick start:
#   curl -fsSL https://raw.githubusercontent.com/jstart/chris-devstrap/main/install.sh | bash
# With bootstrap args:
#   curl -fsSL https://raw.githubusercontent.com/jstart/chris-devstrap/main/install.sh | bash -s -- --dry-run
# Wait for CLT GUI install instead of exit-and-re-run (default when stdout is a TTY):
#   CHRIS_DEVSTRAP_WAIT_CLT=1 curl -fsSL ... | bash
set -euo pipefail

REPO_SLUG="${CHRIS_DEVSTRAP_REPO_SLUG:-jstart/chris-devstrap}"
REPO_HTTPS="${CHRIS_DEVSTRAP_REPO_HTTPS:-https://github.com/${REPO_SLUG}.git}"
CLONE_DIR="${CHRIS_DEVSTRAP_CLONE_DIR:-${HOME}/Developer/Personal/chris-devstrap}"
INSTALL_SH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"

_log() { printf '%s\n' "$*" >&2; }

if [[ "$(uname -s)" != "Darwin" ]]; then
  _log "chris-devstrap targets macOS only."
  exit 1
fi

# Default: wait for CLT on interactive one-liner runs; exit-and-re-run when piped/non-TTY.
if [[ -z "${CHRIS_DEVSTRAP_WAIT_CLT:-}" ]]; then
  if [[ -t 1 ]]; then
    CHRIS_DEVSTRAP_WAIT_CLT=1
  else
    CHRIS_DEVSTRAP_WAIT_CLT=0
  fi
fi
export CHRIS_DEVSTRAP_WAIT_CLT
export CHRIS_DEVSTRAP_CLT_CONTEXT=install
export CHRIS_DEVSTRAP_REPO_SLUG="$REPO_SLUG"

# Load scripts/clt.sh into this shell. macOS /bin/bash is 3.2 — `source <(...)`
# process substitution is a known no-op there, so remote loads use a temp file.
_chris_clt_try_source() {
  local path="$1"
  [[ -f "$path" ]] || return 1
  # shellcheck disable=SC1090
  source "$path"
  declare -F chris_clt_require >/dev/null 2>&1
}

_clt_loaded=0
if [[ -n "$INSTALL_SH_DIR" ]] && _chris_clt_try_source "${INSTALL_SH_DIR}/scripts/clt.sh"; then
  _clt_loaded=1
else
  _clt_url="https://raw.githubusercontent.com/${REPO_SLUG}/main/scripts/clt.sh"
  _clt_tmpfile="$(mktemp "${TMPDIR:-/tmp}/chris-devstrap-clt.XXXXXX")"
  if curl -fsSL "$_clt_url" -o "$_clt_tmpfile" 2>/dev/null &&
    [[ -s "$_clt_tmpfile" ]] &&
    _chris_clt_try_source "$_clt_tmpfile"; then
    _clt_loaded=1
  fi
  rm -f "$_clt_tmpfile"
fi

if [[ "$_clt_loaded" != "1" ]]; then
  _log "Could not load scripts/clt.sh — using minimal CLT check."
  if ! xcode-select -p >/dev/null 2>&1; then
    _log "Xcode Command Line Tools missing. Launching the installer..."
    xcode-select --install >/dev/null 2>&1 || true
    _log "Click Install in the dialog, wait for it to finish (~5-10 min), then re-run:"
    _log "  curl -fsSL https://raw.githubusercontent.com/${REPO_SLUG}/main/install.sh | bash"
    exit 1
  fi
else
  chris_clt_require
  chris_clt_require_git
fi

mkdir -p "$(dirname "$CLONE_DIR")"
if [[ -d "${CLONE_DIR}/.git" ]]; then
  _log "Updating existing clone: ${CLONE_DIR}"
  git -C "$CLONE_DIR" fetch origin
  git -C "$CLONE_DIR" checkout main 2>/dev/null || git -C "$CLONE_DIR" checkout master 2>/dev/null || true
  git -C "$CLONE_DIR" pull --ff-only origin main 2>/dev/null || git -C "$CLONE_DIR" pull --ff-only origin master 2>/dev/null || true
else
  _log "Cloning ${REPO_HTTPS} -> ${CLONE_DIR}"
  git clone "$REPO_HTTPS" "$CLONE_DIR"
fi

cd "$CLONE_DIR"
chmod +x bootstrap.sh scripts/*.sh 2>/dev/null || true
exec ./bootstrap.sh "$@"

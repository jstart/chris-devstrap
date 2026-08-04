#!/usr/bin/env bash
# Remote bootstrap entrypoint (macOS only).
# Quick start:
#   curl -fsSL https://raw.githubusercontent.com/jstart/chris-devstrap/main/install.sh | bash
# With bootstrap args:
#   curl -fsSL https://raw.githubusercontent.com/jstart/chris-devstrap/main/install.sh | bash -s -- --dry-run
# Install a non-main ref (feature branch / tag):
#   CHRIS_DEVSTRAP_REF=cursor/fix-clt-source-bash32-af43 \
#     curl -fsSL https://raw.githubusercontent.com/jstart/chris-devstrap/cursor/fix-clt-source-bash32-af43/install.sh | bash
# Wait for CLT GUI install instead of exit-and-re-run (default when stdout is a TTY):
#   CHRIS_DEVSTRAP_WAIT_CLT=1 curl -fsSL ... | bash
set -euo pipefail

REPO_SLUG="${CHRIS_DEVSTRAP_REPO_SLUG:-jstart/chris-devstrap}"
REPO_HTTPS="${CHRIS_DEVSTRAP_REPO_HTTPS:-https://github.com/${REPO_SLUG}.git}"
# Branch or tag to clone/checkout. curl of a branch's install.sh still defaults to
# main unless you set this — otherwise PR fixes never land in ~/…/chris-devstrap.
REPO_REF="${CHRIS_DEVSTRAP_REF:-main}"
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
export CHRIS_DEVSTRAP_REF="$REPO_REF"

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
  _clt_url="https://raw.githubusercontent.com/${REPO_SLUG}/${REPO_REF}/scripts/clt.sh"
  _clt_tmpfile="$(mktemp "${TMPDIR:-/tmp}/chris-devstrap-clt.XXXXXX")"
  if curl -fsSL "$_clt_url" -o "$_clt_tmpfile" 2>/dev/null &&
    [[ -s "$_clt_tmpfile" ]] &&
    _chris_clt_try_source "$_clt_tmpfile"; then
    _clt_loaded=1
  elif [[ "$REPO_REF" != "main" ]]; then
    # Branch tip may lag; fall back to main's clt.sh gate.
    _clt_url="https://raw.githubusercontent.com/${REPO_SLUG}/main/scripts/clt.sh"
    if curl -fsSL "$_clt_url" -o "$_clt_tmpfile" 2>/dev/null &&
      [[ -s "$_clt_tmpfile" ]] &&
      _chris_clt_try_source "$_clt_tmpfile"; then
      _clt_loaded=1
    fi
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
  _log "Updating existing clone: ${CLONE_DIR} (ref ${REPO_REF})"
  git -C "$CLONE_DIR" fetch origin
  if ! git -C "$CLONE_DIR" checkout "$REPO_REF" 2>/dev/null; then
    _log "Could not checkout ${REPO_REF} — trying main/master."
    git -C "$CLONE_DIR" checkout main 2>/dev/null || git -C "$CLONE_DIR" checkout master 2>/dev/null || true
  fi
  git -C "$CLONE_DIR" pull --ff-only origin "$REPO_REF" 2>/dev/null ||
    git -C "$CLONE_DIR" pull --ff-only origin main 2>/dev/null ||
    git -C "$CLONE_DIR" pull --ff-only origin master 2>/dev/null || true
else
  _log "Cloning ${REPO_HTTPS} (ref ${REPO_REF}) -> ${CLONE_DIR}"
  if ! git clone --branch "$REPO_REF" "$REPO_HTTPS" "$CLONE_DIR" 2>/dev/null; then
    _log "Clone of ref ${REPO_REF} failed — cloning default branch."
    git clone "$REPO_HTTPS" "$CLONE_DIR"
  fi
fi

cd "$CLONE_DIR"
_log "Using $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?') @ $(git rev-parse --short HEAD 2>/dev/null || echo '?')"
chmod +x bootstrap.sh scripts/*.sh 2>/dev/null || true
exec ./bootstrap.sh "$@"

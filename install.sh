#!/usr/bin/env bash
# Remote bootstrap entrypoint (macOS only).
# Quick start:
#   curl -fsSL https://raw.githubusercontent.com/jstart/chris-devstrap/main/install.sh | bash
# With bootstrap args:
#   curl -fsSL https://raw.githubusercontent.com/jstart/chris-devstrap/main/install.sh | bash -s -- --dry-run
set -euo pipefail

REPO_SLUG="${CHRIS_DEVSTRAP_REPO_SLUG:-jstart/chris-devstrap}"
REPO_HTTPS="${CHRIS_DEVSTRAP_REPO_HTTPS:-https://github.com/${REPO_SLUG}.git}"
CLONE_DIR="${CHRIS_DEVSTRAP_CLONE_DIR:-${HOME}/Developer/Personal/chris-devstrap}"

_log() { printf '%s\n' "$*" >&2; }

if [[ "$(uname -s)" != "Darwin" ]]; then
  _log "chris-devstrap targets macOS only."
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  _log "git not found. Install Xcode Command Line Tools (xcode-select --install) first."
  exit 1
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

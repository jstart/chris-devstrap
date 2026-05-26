#!/usr/bin/env bash
# Xcode Command Line Tools gate (sourced by install.sh and brew.sh; do not execute directly).
# shellcheck shell=bash

# True when xcode-select reports an active developer directory.
chris_clt_installed() {
  xcode-select -p >/dev/null 2>&1
}

_chris_clt_log() {
  if declare -f step_info &>/dev/null; then
    step_info "$*"
  elif declare -f _log &>/dev/null; then
    _log "$*"
  else
    printf '%s\n' "$*" >&2
  fi
}

_chris_clt_warn() {
  if declare -f step_warn &>/dev/null; then
    step_warn "$*"
  elif declare -f _log &>/dev/null; then
    _log "$*"
  else
    printf '%s\n' "$*" >&2
  fi
}

_chris_clt_ok() {
  if declare -f step_ok &>/dev/null; then
    step_ok "$*"
  elif declare -f _log &>/dev/null; then
    _log "$*"
  else
    printf '%s\n' "$*" >&2
  fi
}

# Require CLT before git clone / Homebrew. Exits 1 when missing and not waiting.
# Env:
#   CHRIS_DEVSTRAP_CLT_CONTEXT=install|bootstrap  (message wording)
#   CHRIS_DEVSTRAP_WAIT_CLT=1                     poll after GUI install (~30s)
#   CHRIS_DEVSTRAP_DRY_RUN=1                      print intent only (bootstrap)
#   CHRIS_DEVSTRAP_REPO_SLUG                        for install re-run one-liner hint
chris_clt_require() {
  local ctx="${CHRIS_DEVSTRAP_CLT_CONTEXT:-bootstrap}"
  local slug="${CHRIS_DEVSTRAP_REPO_SLUG:-jstart/chris-devstrap}"

  if chris_clt_installed; then
    if declare -f step_start &>/dev/null; then
      step_start "Xcode Command Line Tools"
    fi
    _chris_clt_ok "Command Line Tools present"
    return 0
  fi

  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-0}" == "1" ]]; then
    _chris_clt_warn "Would run xcode-select --install (GUI) — install CLT, then re-run bootstrap."
    exit 1
  fi

  if declare -f step_start &>/dev/null; then
    step_start "Xcode Command Line Tools"
  fi
  _chris_clt_log "Command Line Tools missing — launching the installer (GUI dialog may appear)..."
  xcode-select --install >/dev/null 2>&1 || xcode-select --install || true

  if [[ "${CHRIS_DEVSTRAP_WAIT_CLT:-0}" == "1" ]]; then
    _chris_clt_log "Waiting for Command Line Tools to finish (click Install in the dialog if shown)…"
    local waited=0
    while ! chris_clt_installed; do
      sleep 30 || exit 1
      waited=$((waited + 30))
      _chris_clt_log "Still waiting for Command Line Tools… (${waited}s elapsed)"
    done
    _chris_clt_ok "Command Line Tools installed."
    return 0
  fi

  if [[ "$ctx" == "install" ]]; then
    _chris_clt_log "Click Install in the dialog, wait for it to finish (~5–10 min), then re-run:"
    _chris_clt_log "  curl -fsSL https://raw.githubusercontent.com/${slug}/main/install.sh | bash"
    _chris_clt_log "Or set CHRIS_DEVSTRAP_WAIT_CLT=1 on this one-liner to wait automatically."
  else
    _chris_clt_warn "Wait for CLT install to finish, then re-run ./bootstrap.sh"
    _chris_clt_log "Or set CHRIS_DEVSTRAP_WAIT_CLT=1 to wait automatically."
  fi
  exit 1
}

# Secondary guard: CLT selected but git missing from PATH.
chris_clt_require_git() {
  if command -v git >/dev/null 2>&1; then
    return 0
  fi
  _chris_clt_warn "git not found on PATH even though Command Line Tools are selected."
  _chris_clt_log "Try: sudo xcode-select --reset, then re-run."
  exit 1
}

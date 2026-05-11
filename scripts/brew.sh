#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

step_start "Xcode Command Line Tools"
if ! xcode-select -p &>/dev/null; then
  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
    step_warn "Would run xcode-select --install (GUI) — install CLT, then re-run bootstrap."
    exit 1
  fi
  step_info "Installing Command Line Tools (GUI prompt may appear)..."
  xcode-select --install || true
  step_warn "Wait for CLT install to finish, then re-run bootstrap.sh"
  exit 1
fi
step_ok "Command Line Tools present"

step_start "Homebrew"
if ! chris_brew_prefix_path &>/dev/null; then
  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
    step_info "Would install Homebrew (NONINTERACTIVE=1 official install.sh)."
  else
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
fi

ZPROFILE="${HOME}/.zprofile"
MARK_BEGIN="# brew shellenv (chris-devstrap)"
MARK_END="# end brew shellenv (chris-devstrap)"

ensure_shellenv_block() {
  local brew_prefix=""
  if ! brew_prefix="$(chris_brew_prefix_path)"; then
    return 1
  fi
  touch "$ZPROFILE"
  if grep -qF "$MARK_BEGIN" "$ZPROFILE" 2>/dev/null; then
    step_ok "brew shellenv block already present in $ZPROFILE"
    return 0
  fi
  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
    step_info "Would append brew shellenv block to $ZPROFILE (brew_prefix=$brew_prefix)"
    return 0
  fi
  {
    echo ""
    echo "$MARK_BEGIN"
    echo "eval \"\$(${brew_prefix}/bin/brew shellenv zsh)\""
    echo "$MARK_END"
  } >>"$ZPROFILE"
  step_ok "Appended brew shellenv to $ZPROFILE"
}

step_start "brew on PATH (this shell)"
if ! chris_eval_brew_shellenv; then
  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
    step_info "brew not on PATH yet; skipping shellenv block."
    exit 0
  fi
  step_warn "brew binary missing after install script"
  exit 1
fi

step_start "${HOME}/.zprofile shellenv block"
ensure_shellenv_block

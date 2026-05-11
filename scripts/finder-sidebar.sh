#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# No Homebrew formula; official release is a signed .pkg (GitHub).
# Override URL to pin another release: CHRIS_DEVSTRAP_SBEDIT_PKG_URL
# Skip download/install: CHRIS_DEVSTRAP_SKIP_SBEDIT_INSTALL=1
_chris_try_install_sbedit_pkg() {
  local url="${CHRIS_DEVSTRAP_SBEDIT_PKG_URL:-https://github.com/fabienconus/sidebar-editor/releases/download/1.0/sbedit-1.0.pkg}"
  local tmp="${TMPDIR:-/tmp}/chris-devstrap-sbedit-$$.pkg"
  step_start "Install sbedit (sidebar-editor CLI, signed pkg)"
  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
    chris_run curl -fsSL -o "$tmp" "$url"
    chris_run sudo installer -pkg "$tmp" -target /
    return 0
  fi
  if ! curl -fsSL -o "$tmp" "$url"; then
    step_warn "Could not download sbedit pkg — skipping automatic install."
    return 1
  fi
  set +e
  sudo installer -pkg "$tmp" -target / </dev/null
  local st=$?
  set -e
  rm -f "$tmp"
  if [[ "$st" -ne 0 ]]; then
    step_warn "sbedit installer exited $st (needs admin; run bootstrap with sudo primed or install pkg from GitHub releases)."
    return 1
  fi
  step_ok "Installed sbedit from pkg."
  hash -r 2>/dev/null || true
  return 0
}

step_start "Developer layout (~/Developer, ~/Downloads)"
if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
  chris_run mkdir -p "$HOME/Developer/Personal/chris-devstrap"
  chris_run mkdir -p "$HOME/Downloads"
else
  mkdir -p "$HOME/Developer/Personal/chris-devstrap"
  mkdir -p "$HOME/Downloads"
fi
step_ok "Directories ready"

step_start "Finder sidebar favorites"
if ! command -v sbedit &>/dev/null && [[ "${CHRIS_DEVSTRAP_SKIP_SBEDIT_INSTALL:-0}" != "1" ]]; then
  _chris_try_install_sbedit_pkg || true
fi

if command -v sbedit &>/dev/null; then
  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
    chris_run sbedit --add "$HOME/Developer" "$HOME/Downloads"
    chris_run sbedit --reload --force
  else
    sbedit --add "$HOME/Developer" "$HOME/Downloads" 2>/dev/null || true
    sbedit --reload --force 2>/dev/null || sbedit --reload 2>/dev/null || true
  fi
  step_ok "sbedit: added Developer + Downloads (reloaded)."
elif command -v mysides &>/dev/null; then
  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
    chris_run mysides add Developer "file://${HOME}/Developer"
    chris_run mysides add Downloads "file://${HOME}/Downloads"
    chris_run killall Finder
  else
    mysides add Developer "file://${HOME}/Developer" 2>/dev/null || true
    mysides add Downloads "file://${HOME}/Downloads" 2>/dev/null || true
    killall Finder 2>/dev/null || true
  fi
  step_ok "mysides: attempted Developer + Downloads sidebar entries (legacy)."
else
  step_info "No sbedit or mysides on PATH — Finder sidebar pins are optional (directories still created)."
  chris_manual_todo "Finder sidebar: install sbedit from https://github.com/fabienconus/sidebar-editor/releases (or brew install mysides), then re-run bootstrap — or add ~/Developer and ~/Downloads under Finder → Settings → Sidebar."
  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
    chris_run open "$HOME/Developer"
  else
    open "$HOME/Developer" 2>/dev/null || true
  fi
  step_ok "Finder sidebar: skipped automation (no optional CLI tools)."
fi

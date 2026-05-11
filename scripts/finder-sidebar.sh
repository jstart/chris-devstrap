#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

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
  chris_manual_todo "Finder sidebar: install sbedit (https://github.com/fabienconus/sidebar-editor/releases) or add ~/Developer and ~/Downloads under Finder → Settings → Sidebar."
  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
    chris_run open "$HOME/Developer"
  else
    open "$HOME/Developer" 2>/dev/null || true
  fi
  step_ok "Finder sidebar: skipped automation (no optional CLI tools)."
fi

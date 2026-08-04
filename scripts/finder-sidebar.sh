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

# A5: skip sbedit add+reload when Developer + Downloads already pinned.
_chris_sbedit_already_pinned() {
  local listing
  listing="$(sbedit --list 2>/dev/null || true)"
  [[ -z "$listing" ]] && return 1
  grep -qF "$HOME/Developer" <<<"$listing" || return 1
  grep -qF "$HOME/Downloads" <<<"$listing" || return 1
}

# A5 (mysides variant): mysides list returns "Label -> file:///path".
_chris_mysides_already_pinned() {
  local listing
  listing="$(mysides list 2>/dev/null || true)"
  [[ -z "$listing" ]] && return 1
  grep -qF "file://${HOME}/Developer" <<<"$listing" || return 1
  grep -qF "file://${HOME}/Downloads" <<<"$listing" || return 1
}

if command -v sbedit &>/dev/null; then
  if _chris_sbedit_already_pinned; then
    step_ok "sbedit: Developer + Downloads already in sidebar — skipping --reload --force."
  elif [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
    chris_run sbedit --add "$HOME/Developer" "$HOME/Downloads"
    chris_run sbedit --reload --force
  else
    # Capture stderr: TCC / Full Disk Access failures still print "Services reloaded"
    # and we must not claim success when the SFL file was not writable.
    _chris_sbedit_out=""
    _chris_sbedit_out="$(sbedit --add "$HOME/Developer" "$HOME/Downloads" 2>&1 || true)"
    _chris_sbedit_out+=$'\n'"$(sbedit --reload --force 2>&1 || sbedit --reload 2>&1 || true)"
    if printf '%s\n' "$_chris_sbedit_out" | grep -qiE 'permission|Operation not permitted|unable to read the SFL|NSCocoaErrorDomain'; then
      step_warn "sbedit could not update Finder sidebar (needs Full Disk Access for your terminal)."
      printf '%s\n' "$_chris_sbedit_out" | sed '/^$/d; s/^/  /' >&2
      chris_manual_todo_block "Finder sidebar — grant Full Disk Access, then re-run sidebar script:" \
        "  System Settings → Privacy & Security → Full Disk Access → enable Terminal (or iTerm)" \
        "  Then: ./scripts/finder-sidebar.sh" \
        "  Or add ~/Developer + ~/Downloads under Finder → Settings → Sidebar"
    elif _chris_sbedit_already_pinned; then
      step_ok "sbedit: added Developer + Downloads (reloaded)."
    else
      step_warn "sbedit ran but Developer/Downloads not confirmed in sidebar."
      chris_manual_todo "Finder sidebar: grant Full Disk Access to your terminal, run ./scripts/finder-sidebar.sh — or pin ~/Developer + ~/Downloads in Finder → Settings → Sidebar."
    fi
  fi
elif command -v mysides &>/dev/null; then
  if _chris_mysides_already_pinned; then
    step_ok "mysides: Developer + Downloads already in sidebar — skipping add + Finder restart."
  elif [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
    chris_run mysides add Developer "file://${HOME}/Developer"
    chris_run mysides add Downloads "file://${HOME}/Downloads"
    chris_run killall Finder
  else
    mysides add Developer "file://${HOME}/Developer" 2>/dev/null || true
    mysides add Downloads "file://${HOME}/Downloads" 2>/dev/null || true
    killall Finder 2>/dev/null || true
    step_ok "mysides: attempted Developer + Downloads sidebar entries (legacy)."
  fi
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

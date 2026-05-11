#!/usr/bin/env bash
# Machine + repo readiness checks for chris-devstrap (macOS).
# See README: exit codes and ssh -T GitHub behavior.
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

export CHRIS_DEVSTRAP_INTERACTIVE="${CHRIS_DEVSTRAP_INTERACTIVE:-0}"
[[ -t 1 ]] && CHRIS_DEVSTRAP_INTERACTIVE=1

HC_FAILED=0
HC_FATAL=0

_hc_pass() { step_ok "$1"; }
_hc_fail() {
  step_warn "$1"
  HC_FAILED=1
}
_hc_fatal() {
  step_warn "$1"
  HC_FAILED=1
  HC_FATAL=1
}

_banner_ok() {
  if type banner &>/dev/null; then
    banner "healthcheck — $(date '+%Y-%m-%d %H:%M:%S')"
  else
    printf 'healthcheck — %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
  fi
}

_command_path() {
  command -v "$1" >/dev/null 2>&1
}

_run_capture() {
  local out code
  set +e
  out="$("$@" 2>&1)"
  code=$?
  set -e
  printf '%s\n' "$out"
  return "$code"
}

_main() {
  _banner_ok
  step_info "Repo root: $ROOT"
  hr

  step_start "uname"
  if _run_capture uname -a; then
    _hc_pass "uname"
  else
    _hc_fatal "uname failed"
  fi
  [[ "$HC_FATAL" -eq 1 ]] && return 1

  step_start "macOS (sw_vers)"
  if [[ "$(uname -s)" != "Darwin" ]]; then
    _hc_fatal "Not macOS — chris-devstrap targets Darwin only."
    return 1
  fi
  if _run_capture sw_vers; then
    _hc_pass "sw_vers"
  else
    _hc_fail "sw_vers failed"
  fi

  step_start "Xcode Command Line Tools (xcode-select -p)"
  if out="$(xcode-select -p 2>&1)"; then
    printf '%s\n' "$out"
    _hc_pass "CLT path present"
  else
    printf '%s\n' "$out"
    _hc_fatal "xcode-select -p failed — install CLT (xcode-select --install)."
  fi
  [[ "$HC_FATAL" -eq 1 ]] && return 1

  step_start "Homebrew (brew --version)"
  if ! _command_path brew; then
    _hc_fatal "brew not found on PATH"
    return 1
  fi
  if _run_capture brew --version; then
    _hc_pass "brew --version"
  else
    _hc_fatal "brew --version failed"
    return 1
  fi

  step_start "brew doctor (non-fatal — warnings do not fail this script)"
  set +e
  doc="$(_run_capture brew doctor)"
  dcode=$?
  set -e
  doc_tail="$(printf '%s\n' "$doc" | tail -n 25)"
  if [[ "$dcode" -eq 0 ]]; then
    printf '%s\n' "$doc_tail"
    _hc_pass "brew doctor exited 0"
  else
    printf '%s\n' "$doc_tail"
    step_info "brew doctor exited $dcode (see tail above) — fix when convenient; not treated as fatal."
    _hc_pass "brew doctor (soft-fail OK)"
  fi

  step_start "brew bundle check — $ROOT/Brewfile (--no-upgrade)"
  set +e
  bundle_out="$(cd "$ROOT" && brew bundle check --no-upgrade --file="$ROOT/Brewfile" 2>&1)"
  bcode=$?
  set -e
  printf '%s\n' "$bundle_out"
  if [[ "$bcode" -eq 0 ]]; then
    _hc_pass "brew bundle check"
  else
    _hc_fail "brew bundle check failed — run ./bootstrap.sh or ./bootstrap.sh update"
  fi

  if [[ -f "$ROOT/Brewfile.dev" ]] && [[ "${CHRIS_DEVSTRAP_SKIP_DEV_BUNDLE:-0}" != "1" ]]; then
    step_start "brew bundle check — $ROOT/Brewfile.dev (--no-upgrade)"
    set +e
    bundle_dev_out="$(cd "$ROOT" && brew bundle check --no-upgrade --file="$ROOT/Brewfile.dev" 2>&1)"
    bdcode=$?
    set -e
    printf '%s\n' "$bundle_dev_out"
    if [[ "$bdcode" -eq 0 ]]; then
      _hc_pass "brew bundle check (Brewfile.dev)"
    else
      _hc_fail "brew bundle check (Brewfile.dev) failed — run ./bootstrap.sh or ./bootstrap.sh update"
    fi
  fi

  step_start "git --version"
  if ! _command_path git; then
    _hc_fatal "git not found on PATH"
    return 1
  fi
  if _run_capture git --version; then
    _hc_pass "git --version"
  else
    _hc_fatal "git --version failed"
    return 1
  fi

  if [[ -d "$ROOT/.git" ]]; then
    step_start "git remote -v"
    if _run_capture git -C "$ROOT" remote -v; then
      _hc_pass "git remote -v"
    else
      _hc_fail "git remote -v failed"
    fi
  else
    step_start "git remote -v"
    step_info "No $ROOT/.git — skipping git remote -v"
    _hc_pass "skip (not a git checkout)"
  fi

  step_start "GitHub SSH (ssh -T git@github.com)"
  step_info "GitHub often exits 1 while printing a success line — see https://docs.github.com/en/authentication/connecting-to-github-with-ssh/testing-your-ssh-connection"
  set +e
  ssh_out="$(_run_capture ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -T git@github.com)"
  ssh_code=$?
  set -e
  printf '%s\n' "$ssh_out"
  if grep -qi 'Permission denied' <<<"$ssh_out"; then
    _hc_fail "GitHub SSH: Permission denied"
  elif [[ "$ssh_code" -eq 255 ]]; then
    _hc_fail "GitHub SSH: connection/host key problem (exit 255)"
  elif grep -Eq 'successfully authenticated|Welcome to GitHub|^Hi ' <<<"$ssh_out"; then
    _hc_pass "GitHub SSH authenticated"
  elif [[ "$ssh_code" -eq 1 ]] && grep -qi 'github\.com' <<<"$ssh_out" && ! grep -qi 'Permission denied' <<<"$ssh_out"; then
    _hc_pass "GitHub SSH OK (exit 1 with GitHub message — expected)"
  else
    _hc_fail "Could not confirm GitHub SSH (exit ${ssh_code})"
  fi

  step_start "dockutil --version"
  if _command_path dockutil && _run_capture dockutil --version; then
    _hc_pass "dockutil"
  else
    _hc_fail "dockutil missing or failed — install via Brewfile / ./bootstrap.sh update"
  fi

  step_start "mas --version (optional)"
  if _command_path mas && _run_capture mas --version; then
    _hc_pass "mas"
  else
    step_info "mas not on PATH or failed — optional until App Store CLI is needed"
    _hc_pass "mas (optional skip)"
  fi

  hr
  if [[ "$HC_FATAL" -eq 1 ]]; then
    step_warn "healthcheck: fatal errors above"
    return 1
  fi
  if [[ "$HC_FAILED" -eq 1 ]]; then
    step_warn "healthcheck: some checks failed — review above"
    return 1
  fi
  step_ok "healthcheck: all checks passed"
  return 0
}

_main "$@"

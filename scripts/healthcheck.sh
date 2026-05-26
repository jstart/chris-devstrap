#!/usr/bin/env bash
# Machine + repo readiness checks for chris-devstrap (macOS).
# See README: exit codes and ssh -T GitHub behavior.
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=ssh-config.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ssh-config.sh"

chris_export_interactive_if_tty

HC_FAILED=0
HC_FATAL=0
HC_WARNED=0

_hc_pass() { step_ok "$1"; }
_hc_warn() {
  step_warn "$1"
  HC_WARNED=1
}
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

  # C1: alias-aware GitHub SSH check. The bootstrap-time setup at scripts/git-ssh-setup.sh
  # parses ~/.ssh/config for whichever Host alias routes the dedicated key, so a demoted
  # primary (Host github.com-jstart) would otherwise pass/fail the wrong host here.
  local ssh_host="github.com"
  local dedicated_key="${HOME}/.ssh/id_ed25519_chrisdevstrap"
  if [[ -f "$dedicated_key" ]]; then
    local routed_host
    routed_host="$(chris_ssh_config_host_for_identity_file "$dedicated_key" 2>/dev/null || true)"
    [[ -n "$routed_host" ]] && ssh_host="$routed_host"
  fi
  step_start "GitHub SSH (ssh -T git@${ssh_host})"
  step_info "GitHub often exits 1 while printing a success line — see https://docs.github.com/en/authentication/connecting-to-github-with-ssh/testing-your-ssh-connection"
  local hc_rc=0
  chris_github_ssh_verify_batchmode "$ssh_host" || hc_rc=$?
  printf '%s\n' "$CHRIS_SSH_VERIFY_OUTPUT"
  case "$hc_rc" in
    0)
      if [[ "$CHRIS_SSH_VERIFY_CODE" -eq 1 ]]; then
        _hc_pass "GitHub SSH OK (exit 1 with GitHub message — expected)"
      else
        _hc_pass "GitHub SSH authenticated"
      fi
      ;;
    2) _hc_fail "GitHub SSH (${ssh_host}): Permission denied" ;;
    3) _hc_fail "GitHub SSH (${ssh_host}): connection/host key problem (exit 255)" ;;
    *) _hc_fail "Could not confirm GitHub SSH (${ssh_host}; exit ${CHRIS_SSH_VERIFY_CODE})" ;;
  esac

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

  # ============================================================================
  # Tier A — fatal-on-fail config checks (bootstrap promises these)
  # ============================================================================
  hr
  step_start "Tier A: bootstrap-managed config (fatal)"

  local zprofile="${HOME}/.zprofile"
  if [[ -f "$zprofile" ]] && grep -qF '# brew shellenv (chris-devstrap)' "$zprofile"; then
    _hc_pass ".zprofile contains brew shellenv block"
  else
    _hc_fail ".zprofile missing chris-devstrap brew shellenv block — run ./bootstrap.sh"
  fi

  if [[ -d "$ROOT/.git" ]]; then
    local origin_url
    origin_url="$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)"
    if [[ -n "$origin_url" && "$origin_url" =~ ^(git@|ssh://) ]]; then
      _hc_pass "git origin uses SSH (${origin_url})"
    elif [[ -z "$origin_url" ]]; then
      _hc_fail "git origin not set — run ./bootstrap.sh or ./scripts/git-ssh-setup.sh"
    else
      _hc_fail "git origin is HTTPS, expected SSH (${origin_url}) — run ./scripts/git-ssh-setup.sh or set CHRIS_DEVSTRAP_GIT_SSH_URL"
    fi
  fi

  if [[ -d "${HOME}/Developer" ]]; then
    # shellcheck disable=SC2088 # cosmetic ~ in human-facing message
    _hc_pass "~/Developer exists"
  else
    # shellcheck disable=SC2088
    _hc_fail "~/Developer missing — run ./bootstrap.sh (creates layout in scripts/finder-sidebar.sh)"
  fi

  if _command_path git; then
    local default_branch
    default_branch="$(git config --global init.defaultBranch 2>/dev/null || true)"
    if [[ "$default_branch" == "main" ]]; then
      _hc_pass "git config --global init.defaultBranch=main"
    elif [[ -z "$default_branch" ]]; then
      _hc_fail "git config --global init.defaultBranch unset — run ./bootstrap.sh (scripts/git-config.sh)"
    else
      step_info "git config --global init.defaultBranch=${default_branch} (chris-devstrap defaults to main; not failing)"
      _hc_pass "git init.defaultBranch (custom: ${default_branch})"
    fi
  fi

  # ============================================================================
  # Tier B — warn-only drift detection (skip with CHRIS_DEVSTRAP_HEALTHCHECK_SKIP_DRIFT=1)
  # ============================================================================
  if [[ "${CHRIS_DEVSTRAP_HEALTHCHECK_SKIP_DRIFT:-0}" != "1" ]]; then
    hr
    step_start "Tier B: config drift (warn-only — CHRIS_DEVSTRAP_HEALTHCHECK_SKIP_DRIFT=1 to silence)"

    local _hc_finder_new
    _hc_finder_new="$(defaults read com.apple.finder NewWindowTarget 2>/dev/null || echo "")"
    if [[ "$_hc_finder_new" == "PfLo" ]]; then
      _hc_pass "Finder new windows → Downloads (PfLo)"
    else
      _hc_warn "Finder new-window target is '${_hc_finder_new:-unset}', expected PfLo"
    fi

    local _hc_finder_view
    _hc_finder_view="$(defaults read com.apple.finder FXPreferredViewStyle 2>/dev/null || echo "")"
    if [[ "$_hc_finder_view" == "clmv" ]]; then
      _hc_pass "Finder default view = column"
    else
      _hc_warn "Finder default view is '${_hc_finder_view:-unset}', expected clmv (column)"
    fi

    local _hc_dark
    _hc_dark="$(defaults read NSGlobalDomain AppleInterfaceStyle 2>/dev/null || echo "")"
    if [[ "$_hc_dark" == "Dark" ]]; then
      _hc_pass "Dark mode enabled"
    else
      _hc_warn "AppleInterfaceStyle is '${_hc_dark:-Light}', expected Dark"
    fi

    local _hc_tl _hc_bl
    _hc_tl="$(defaults read com.apple.dock wvous-tl-corner 2>/dev/null || echo "")"
    _hc_bl="$(defaults read com.apple.dock wvous-bl-corner 2>/dev/null || echo "")"
    if [[ "$_hc_tl" == "10" && "$_hc_bl" == "1" ]]; then
      _hc_pass "Hot corners: top-left=sleep(10), bottom-left=off(1)"
    else
      _hc_warn "Hot corners drift: tl=${_hc_tl:-unset} bl=${_hc_bl:-unset} (expected 10/1)"
    fi

    local _hc_dock_autohide
    _hc_dock_autohide="$(defaults read com.apple.dock autohide 2>/dev/null || echo "")"
    if [[ "$_hc_dock_autohide" == "1" ]]; then
      _hc_pass "Dock autohide enabled"
    else
      _hc_warn "Dock autohide is '${_hc_dock_autohide:-unset}', expected 1"
    fi

    if _command_path dockutil; then
      local _missing_dock=""
      while IFS=$'\t' read -r label _ || [[ -n "${label:-}" ]]; do
        label="${label//$'\r'/}"
        [[ -z "${label//[[:space:]]/}" ]] && continue
        [[ "$label" =~ ^[[:space:]]*# ]] && continue
        label="${label#"${label%%[![:space:]]*}"}"
        label="${label%"${label##*[![:space:]]}"}"
        [[ -z "$label" ]] && continue
        dockutil --find "$label" &>/dev/null || _missing_dock+="${label} "
      done <"${ROOT}/config/dock-add.tsv"
      if [[ -z "$_missing_dock" ]]; then
        _hc_pass "Dock contains all labels from config/dock-add.tsv"
      else
        _hc_warn "Dock missing pinned apps: ${_missing_dock% }"
      fi
    fi

    local _hc_spotlight_plist="${HOME}/Library/Preferences/com.apple.symbolichotkeys.plist"
    if [[ -f "$_hc_spotlight_plist" ]]; then
      local _hc_hotkey
      _hc_hotkey="$(/usr/libexec/PlistBuddy -c 'Print :AppleSymbolicHotKeys:64:enabled' "$_hc_spotlight_plist" 2>/dev/null || echo "")"
      if [[ "$_hc_hotkey" == "false" ]]; then
        _hc_pass "Spotlight hotkey 64 disabled (⌘Space free for Raycast)"
      else
        _hc_warn "Spotlight hotkey 64 is '${_hc_hotkey:-unset}', expected false"
      fi
    fi

    local _hc_iterm_plist="${HOME}/Library/Preferences/com.googlecode.iterm2.plist"
    if [[ -f "$_hc_iterm_plist" ]] && [[ "${CHRIS_DEVSTRAP_SKIP_ITERM_REUSE_DIRECTORY:-0}" != "1" ]]; then
      local _hc_iterm_ok
      _hc_iterm_ok="$(python3 - "$_hc_iterm_plist" <<'PY' 2>/dev/null || true
import plistlib, pathlib, sys
try:
    with pathlib.Path(sys.argv[1]).open("rb") as f:
        data = plistlib.load(f)
except Exception:
    print("err"); sys.exit(0)
bookmarks = data.get("New Bookmarks", [])
if not isinstance(bookmarks, list) or not bookmarks:
    print("none"); sys.exit(0)
print("ok" if all(isinstance(b, dict) and b.get("Custom Directory") == "Recycle" for b in bookmarks) else "drift")
PY
      )"
      case "$_hc_iterm_ok" in
        ok) _hc_pass "iTerm2: Initial directory = Recycle on all profiles" ;;
        drift) _hc_warn "iTerm2: one or more profiles do not set Custom Directory=Recycle" ;;
        none) step_info "iTerm2 plist has no profiles yet — skipping" ;;
        *) step_info "iTerm2 plist unreadable — skipping" ;;
      esac
    fi
  fi

  # ============================================================================
  # Tier C — informational (never fails or warns; just prints status)
  # ============================================================================
  hr
  step_start "Tier C: optional / deferred (informational only)"

  if [[ -f "$ROOT/Brewfile.heavy" ]]; then
    if brew bundle check --no-upgrade --file="$ROOT/Brewfile.heavy" >/dev/null 2>&1; then
      step_ok "Brewfile.heavy satisfied"
    else
      step_info "Brewfile.heavy unsatisfied (heavy installs deferred — last bootstrap step)"
    fi
  fi

  if chris_xcode_app_installed; then
    step_ok "Xcode.app installed"
    local _hc_dev
    _hc_dev="$(xcode-select -p 2>/dev/null || true)"
    if [[ -n "$_hc_dev" && -x "${_hc_dev}/usr/bin/xcodebuild" ]]; then
      if "${_hc_dev}/usr/bin/xcodebuild" -checkFirstLaunchStatus >/dev/null 2>&1; then
        step_ok "xcodebuild -checkFirstLaunchStatus satisfied"
      else
        step_info "Xcode first-launch components not yet completed (run ./bootstrap.sh or open Xcode once)"
      fi
    fi
    if command -v xcrun >/dev/null 2>&1 && xcrun simctl list runtimes 2>/dev/null | grep -Eq '^iOS [0-9]'; then
      step_ok "iOS Simulator runtime installed"
    else
      step_info "No iOS Simulator runtime installed (xcrun simctl list runtimes)"
    fi
  else
    step_info "Xcode.app not installed (CLT-only or heavy install deferred)"
  fi

  if [[ "${CHRIS_DEVSTRAP_SKIP_HEADSHOT:-0}" != "1" ]] && [[ -f "$ROOT/assets/headshot.png" ]]; then
    if [[ -f "${HOME}/Downloads/headshot.png" ]]; then
      step_ok "Headshot copied to ~/Downloads/headshot.png"
    else
      step_info "assets/headshot.png present but ~/Downloads/headshot.png missing (re-run bootstrap)"
    fi
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
  if [[ "$HC_WARNED" -eq 1 ]]; then
    step_info "healthcheck: passed with config-drift warnings (set CHRIS_DEVSTRAP_HEALTHCHECK_SKIP_DRIFT=1 to silence)"
  fi
  step_ok "healthcheck: all required checks passed"
  return 0
}

_main "$@"

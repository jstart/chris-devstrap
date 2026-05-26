#!/usr/bin/env bash
# Install GitHub CLI extensions used by chris-devstrap.
# Idempotent — `gh extension install` is skipped when the extension is already registered.
#
# Env:
#   CHRIS_DEVSTRAP_SKIP_GH_EXTENSIONS=1   Bypass this whole script.
#   CHRIS_DEVSTRAP_GH_EXTENSIONS=…        Whitespace-separated list overrides the defaults
#                                         (each item is the gh extension spec passed to
#                                         `gh extension install`, e.g. dlvhdr/gh-dash).
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

if [[ "${CHRIS_DEVSTRAP_SKIP_GH_EXTENSIONS:-0}" == "1" ]]; then
  step_info "Skipping gh extensions (CHRIS_DEVSTRAP_SKIP_GH_EXTENSIONS=1)."
  exit 0
fi

if ! command -v gh &>/dev/null; then
  step_warn "gh not on PATH — skipping gh extensions (install via Brewfile, then re-run)."
  exit 0
fi

# Default extension list. dlvhdr/gh-dash → `gh dash` TUI for PRs/issues/notifications.
_default_extensions=(
  "dlvhdr/gh-dash"
)
if [[ -n "${CHRIS_DEVSTRAP_GH_EXTENSIONS:-}" ]]; then
  # shellcheck disable=SC2206 # intentional whitespace split for env-supplied list
  _extensions=(${CHRIS_DEVSTRAP_GH_EXTENSIONS})
else
  _extensions=("${_default_extensions[@]}")
fi

# gh extension list output is tab-separated:
#   gh dash<TAB>dlvhdr/gh-dash<TAB>v4.24.1
# Column 1 contains a space ("gh dash") so default awk whitespace splitting breaks; use -F'\t'.
_gh_extension_installed() {
  local spec="$1"
  gh extension list 2>/dev/null \
    | awk -F'\t' -v s="$spec" '$2 == s { found=1 } END { exit (found ? 0 : 1) }'
}

step_start "GitHub CLI extensions"
for ext in "${_extensions[@]}"; do
  if _gh_extension_installed "$ext"; then
    step_ok "${ext} already installed — skipping"
    continue
  fi
  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
    chris_run gh extension install "$ext"
    continue
  fi
  step_info "Installing gh extension: ${ext}"
  if gh extension install "$ext"; then
    step_ok "Installed ${ext}"
  else
    step_warn "gh extension install ${ext} failed (network / auth?). Skipping; re-run later: gh extension install ${ext}"
  fi
done

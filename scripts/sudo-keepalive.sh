#!/usr/bin/env bash
# Sourced only from bootstrap.sh (after scripts/lib.sh). Prime sudo once, then
# refresh the ticket in the background until bootstrap exits.
# shellcheck shell=bash

chris_devstrap_stop_sudo_keepalive() {
  if [[ -n "${CHRIS_DEVSTRAP_SUDO_KEEPALIVE_PID:-}" ]]; then
    kill "$CHRIS_DEVSTRAP_SUDO_KEEPALIVE_PID" 2>/dev/null || true
    wait "$CHRIS_DEVSTRAP_SUDO_KEEPALIVE_PID" 2>/dev/null || true
    CHRIS_DEVSTRAP_SUDO_KEEPALIVE_PID=""
  fi
}

# Interactive once (sudo -v); then non-interactive sudo -nv in a loop every 50–60s.
chris_devstrap_sudo_prime_and_keepalive() {
  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]] || [[ "${CHRIS_DEVSTRAP_SKIP_SUDO_PRIME:-}" == 1 ]]; then
    return 0
  fi

  # A10: skip the password prompt when sudo is already primed in this shell session.
  # The keepalive still runs so a long brew bundle does not hit an expired credential.
  if sudo -nv 2>/dev/null; then
    step_info "sudo already primed — skipping password prompt, starting keepalive in the background (~55s)."
  else
    step_info "sudo: enter your password once if prompted — bootstrap refreshes the sudo session in the background (~55s) so a long brew bundle or other sudo-using steps do not hit an expired credential mid-run."
    sudo -v
  fi

  (
    while true; do
      sleep "$((50 + RANDOM % 11))" || exit 0
      sudo -nv 2>/dev/null || exit 0
    done
  ) &
  CHRIS_DEVSTRAP_SUDO_KEEPALIVE_PID=$!

  trap 'chris_devstrap_stop_sudo_keepalive' EXIT INT TERM
}

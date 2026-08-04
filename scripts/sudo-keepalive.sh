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

# Ask for the sudo password once. Always use /dev/tty — curl|bash leaves stdin as
# the pipe (EOF), and bootstrap redirects stdout/stderr through tee, so a bare
# `sudo -v` will not present a usable password prompt.
chris_devstrap_sudo_prime() {
  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]] || [[ "${CHRIS_DEVSTRAP_SKIP_SUDO_PRIME:-}" == 1 ]]; then
    return 0
  fi

  # Already have a live ticket in this session.
  if sudo -nv 2>/dev/null; then
    return 0
  fi

  if [[ ! -r /dev/tty || ! -w /dev/tty ]]; then
    step_warn "sudo needs a password but /dev/tty is unavailable (non-interactive). Re-run from Terminal, or set CHRIS_DEVSTRAP_SKIP_SUDO_PRIME=1."
    return 1
  fi

  step_info "sudo: enter your password once if prompted — bootstrap refreshes the sudo session in the background (~55s) so a long brew bundle or other sudo-using steps do not hit an expired credential mid-run."
  # stdin: password; stderr: "Password:" prompt (bypasses bootstrap's tee redirect)
  if ! sudo -v </dev/tty 2>/dev/tty; then
    step_warn "sudo -v failed — Homebrew install and later admin steps may fail."
    return 1
  fi
  return 0
}

# Interactive once (sudo -v via /dev/tty); then non-interactive sudo -nv every 50–60s.
chris_devstrap_sudo_prime_and_keepalive() {
  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]] || [[ "${CHRIS_DEVSTRAP_SKIP_SUDO_PRIME:-}" == 1 ]]; then
    return 0
  fi

  if [[ -n "${CHRIS_DEVSTRAP_SUDO_KEEPALIVE_PID:-}" ]] && kill -0 "$CHRIS_DEVSTRAP_SUDO_KEEPALIVE_PID" 2>/dev/null; then
    step_info "sudo keepalive already running (pid ${CHRIS_DEVSTRAP_SUDO_KEEPALIVE_PID})"
    return 0
  fi

  if sudo -nv 2>/dev/null; then
    step_info "sudo already primed — skipping password prompt, starting keepalive in the background (~55s)."
  else
    chris_devstrap_sudo_prime || return 1
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

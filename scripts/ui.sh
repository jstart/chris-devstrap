#!/usr/bin/env bash
# Terminal UX helpers for chris-devstrap (sourced from lib.sh).
# shellcheck shell=bash

# Colors when stdout is a TTY, or when bootstrap saved interactive before tee, or FORCE_COLOR.
# Set CHRIS_DEVSTRAP_NO_COLOR=1 to disable.
_chris_ui_use_color() {
  [[ -z "${CHRIS_DEVSTRAP_NO_COLOR:-}" ]] || return 1
  [[ -n "${FORCE_COLOR:-}" ]] && return 0
  [[ -t 1 ]] && return 0
  [[ "${CHRIS_DEVSTRAP_INTERACTIVE:-0}" == 1 ]] && return 0
  return 1
}

# shellcheck disable=SC2034
if _chris_ui_use_color; then
  UI_RESET=$'\033[0m'
  UI_BOLD=$'\033[1m'
  UI_DIM=$'\033[2m'
  UI_GREEN=$'\033[32m'
  UI_YELLOW=$'\033[33m'
  UI_BLUE=$'\033[34m'
  UI_CYAN=$'\033[36m'
else
  UI_RESET=""
  UI_BOLD=""
  UI_DIM=""
  UI_GREEN=""
  UI_YELLOW=""
  UI_BLUE=""
  UI_CYAN=""
fi

hr() {
  if _chris_ui_use_color; then
    printf '%s────────────────────────────────────────%s\n' "$UI_DIM" "$UI_RESET"
  else
    printf -- '----------------------------------------\n'
  fi
}

banner() {
  local text="$1"
  if [[ "${CHRIS_DEVSTRAP_FUN:-0}" == "1" ]]; then
    case $((RANDOM % 5)) in
      0) text="$text — Ship it." ;;
      1) text="$text — May your builds be green." ;;
      2) text="$text — Tab complete your destiny." ;;
      3) text="$text — One more defaults write for the road." ;;
      4) text="$text — You look productive today." ;;
    esac
  fi
  hr
  if _chris_ui_use_color; then
    printf '%s%schris-devstrap%s\n' "$UI_BOLD" "$UI_CYAN" "$UI_RESET"
    printf '%s%s%s\n' "$UI_DIM" "$text" "$UI_RESET"
  else
    printf 'chris-devstrap\n%s\n' "$text"
  fi
  hr
}

# Optional: step_progress 2 9 "Label"
step_progress() {
  local cur="$1" total="$2"
  local label="${3:-}"
  if _chris_ui_use_color; then
    printf '%sStep %s%s/%s%s%s' "$UI_DIM" "$UI_BOLD" "$cur" "$total" "$UI_RESET" "$UI_DIM"
  else
    printf '[Step %s/%s]' "$cur" "$total"
  fi
  if [[ -n "$label" ]]; then
    printf '%s\n' " ${label}"
  else
    printf '\n'
  fi
}

step_start() {
  local title="$1"
  if _chris_ui_use_color; then
    printf '%s▸%s %s%s%s\n' "$UI_CYAN" "$UI_RESET" "$UI_BOLD" "$title" "$UI_RESET"
  else
    printf '▸ %s\n' "$title"
  fi
}

step_ok() {
  local msg="${1:-ok}"
  if _chris_ui_use_color; then
    printf '%s✓%s %s\n' "$UI_GREEN" "$UI_RESET" "$msg"
  else
    printf '[ok] %s\n' "$msg"
  fi
}

step_warn() {
  local msg="$1"
  if _chris_ui_use_color; then
    printf '%s✗%s %s\n' "$UI_YELLOW" "$UI_RESET" "$msg"
  else
    printf '[!!] %s\n' "$msg"
  fi
}

step_info() {
  local msg="$1"
  if _chris_ui_use_color; then
    printf '%s·%s %s\n' "$UI_BLUE" "$UI_RESET" "$msg"
  else
    printf '[i] %s\n' "$msg"
  fi
}

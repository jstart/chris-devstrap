#!/usr/bin/env bash
# Install chris-devstrap-managed Raycast Script Commands and remind the user to register the
# directory + assign a hotkey (Raycast hotkeys live in com.raycast.macos.plist with undocumented
# keypaths, so we never write that plist — assignment is one-time, by hand in Raycast Settings).
#
# Env:
#   CHRIS_DEVSTRAP_SKIP_RAYCAST_SCRIPTS=1   Skip the whole installer.
#   CHRIS_DEVSTRAP_RAYCAST_SCRIPTS_DIR=…    Override the install directory (default:
#                                           ~/Library/Application Support/chris-devstrap/raycast-script-commands).
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

if [[ "${CHRIS_DEVSTRAP_SKIP_RAYCAST_SCRIPTS:-0}" == "1" ]]; then
  step_info "Skipping Raycast Script Commands (CHRIS_DEVSTRAP_SKIP_RAYCAST_SCRIPTS=1)."
  exit 0
fi

SRC_DIR="$ROOT/templates/raycast-script-commands"
DEST_DIR="${CHRIS_DEVSTRAP_RAYCAST_SCRIPTS_DIR:-${HOME}/Library/Application Support/chris-devstrap/raycast-script-commands}"

if [[ ! -d "$SRC_DIR" ]]; then
  step_warn "No $SRC_DIR — nothing to install."
  exit 0
fi

step_start "Raycast Script Commands → ${DEST_DIR}"

if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
  chris_run mkdir -p "$DEST_DIR"
  shopt -s nullglob
  for src in "$SRC_DIR"/*.sh; do
    chris_run cp -f "$src" "$DEST_DIR/$(basename "$src")"
    chris_run chmod +x "$DEST_DIR/$(basename "$src")"
  done
  shopt -u nullglob
else
  mkdir -p "$DEST_DIR"
  installed_count=0
  shopt -s nullglob
  for src in "$SRC_DIR"/*.sh; do
    dst="$DEST_DIR/$(basename "$src")"
    # Idempotent — only copy when the source actually differs (cmp is exit-0 on identical).
    if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
      continue
    fi
    cp -f "$src" "$dst"
    chmod +x "$dst"
    installed_count=$((installed_count + 1))
  done
  shopt -u nullglob
  if [[ "$installed_count" -gt 0 ]]; then
    step_ok "Installed/updated ${installed_count} Raycast Script Command(s)."
  else
    step_ok "Raycast Script Commands already up to date — nothing to copy."
  fi
fi

# One guided Raycast step (prefs + Script Commands / ⌘⌃Z). Privacy/Accessibility is prio 40.
chris_manual_todo_block_prio 45 "Raycast setup:" \
  "  General → Hotkey → ⌘Space" \
  "  AI → off (global switch)" \
  "  Extensions → disable rows you do not need" \
  "  Window Management: Left ⌘⌃← / Right ⌘⌃→ / Maximize ⌘⌃Space" \
  "  Clipboard History ⌘⇧C" \
  "  Script Commands: Settings → Extensions → Script Commands → '+' → User Folder → ${DEST_DIR}" \
  "  Extensions → 'Dismiss Mac Notifications' → Hotkey → ⌘⌃Z" \
  "  Accessibility + Screen Recording for Raycast are in the Privacy checklist step" \
  "  UI sounds: silenced by bootstrap unless CHRIS_DEVSTRAP_SILENCE_UI_SOUNDS=0"

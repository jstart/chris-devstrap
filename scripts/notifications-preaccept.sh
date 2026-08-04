#!/usr/bin/env bash
# Pre-accept Notification Center for standard apps + mute Messages/Reminders sounds.
#
# 1) Upserts ~/Library/Preferences/com.apple.ncprefs.plist (allow + banners + badges;
#    sound off for Messages/Reminders).
# 2) Installs templates/notifications-preaccept.mobileconfig when possible (covers apps
#    that have not registered with Notification Center yet).
# 3) Sets Messages PlaySoundsKey=false.
#
# Env:
#   CHRIS_DEVSTRAP_SKIP_NOTIFICATION_PREACCEPT=1  Skip entirely.
#   CHRIS_DEVSTRAP_KEEP_APP_NOTIFICATION_SOUNDS=1 Keep Messages/Reminders sounds on.
#   CHRIS_DEVSTRAP_SKIP_NOTIFICATION_PROFILE=1    Skip .mobileconfig install/open.
#   CHRIS_DEVSTRAP_DRY_RUN=1
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

if [[ "${CHRIS_DEVSTRAP_SKIP_NOTIFICATION_PREACCEPT:-0}" == "1" ]]; then
  step_info "Skipping notification pre-accept (CHRIS_DEVSTRAP_SKIP_NOTIFICATION_PREACCEPT=1)."
  exit 0
fi

step_start "Pre-accept notifications (standard apps)"

_mute_sounds=1
if [[ "${CHRIS_DEVSTRAP_KEEP_APP_NOTIFICATION_SOUNDS:-0}" == "1" ]]; then
  _mute_sounds=0
  step_info "Keeping Messages/Reminders notification sounds (CHRIS_DEVSTRAP_KEEP_APP_NOTIFICATION_SOUNDS=1)."
else
  chris_defaults_write_if_diff com.apple.MobileSMS PlaySoundsKey -bool false
  step_info "Messages PlaySoundsKey=false (quit Messages if it was open)."
fi

# bundle-id|label|sound(0|1) — sound forced off when _mute_sounds=1 for Messages/Reminders.
_chris_notif_apps=(
  "com.apple.Notes|Notes|1"
  "com.apple.stocks|Stocks|1"
  "com.apple.MobileSMS|Messages|0"
  "com.apple.reminders|Reminders|0"
  "com.apple.AppStore|App Store|1"
  "com.googlecode.iterm2|iTerm|1"
  "com.google.Chrome|Google Chrome|1"
  "com.google.Chrome.helper|Chrome Helper|1"
  "com.apple.findmy|Find My|1"
  "com.apple.FaceTime|FaceTime|1"
  "com.apple.Maps|Maps|1"
  "com.apple.news|News|1"
  "com.apple.Passwords|Passwords|1"
  "com.apple.shortcuts|Shortcuts|1"
  "com.apple.weather|Weather|1"
  "us.zoom.xos|Zoom|1"
)

# Seed / update ncprefs so Allow Notifications is on (and sound policy applied).
# Uses python3 + plistlib (ships with macOS). Creates missing app rows when possible.
_chris_ncprefs_upsert() {
  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
    local row bid label sound
    for row in "${_chris_notif_apps[@]}"; do
      IFS='|' read -r bid label sound <<<"$row"
      if [[ "$_mute_sounds" == "1" && ( "$bid" == "com.apple.MobileSMS" || "$bid" == "com.apple.reminders" ) ]]; then
        sound=0
      fi
      chris_run : "ncprefs upsert ${bid} (${label}) allow=1 sound=${sound}"
    done
    return 0
  fi

  local apps_env=""
  local row bid label sound
  for row in "${_chris_notif_apps[@]}"; do
    IFS='|' read -r bid label sound <<<"$row"
    if [[ "$_mute_sounds" == "1" && ( "$bid" == "com.apple.MobileSMS" || "$bid" == "com.apple.reminders" ) ]]; then
      sound=0
    fi
    apps_env+="${bid}|${sound}"$'\n'
  done

  CHRIS_NOTIF_APPS="$apps_env" python3 - <<'PY'
import os, plistlib, subprocess, sys
from pathlib import Path

ncprefs = Path.home() / "Library/Preferences/com.apple.ncprefs.plist"
# Match a common “allowed” System Settings shape: allow + banners + badge (+ optional sound).
# bits 13+23 appear on stock allowed entries on recent macOS.
BASE = (1 << 25) | (1 << 3) | (1 << 1) | (1 << 13) | (1 << 23)  # 41951242
SOUND = 1 << 2

def resolve_path(bundle_id: str) -> str:
    try:
        out = subprocess.check_output(
            ["mdfind", f"kMDItemCFBundleIdentifier == '{bundle_id}'"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        return ""
    for line in out.splitlines():
        p = line.strip()
        if p.endswith(".app") and os.path.isdir(p):
            return p
    return ""

raw = os.environ.get("CHRIS_NOTIF_APPS", "")
wanted = []
for line in raw.splitlines():
    line = line.strip()
    if not line or "|" not in line:
        continue
    bid, sound_s = line.split("|", 1)
    wanted.append((bid, sound_s == "1"))

if ncprefs.exists():
    with ncprefs.open("rb") as f:
        data = plistlib.load(f)
else:
    data = {}

apps = data.get("apps")
if not isinstance(apps, list):
    apps = []
    data["apps"] = apps

index_by_id = {}
for i, app in enumerate(apps):
    if isinstance(app, dict) and app.get("bundle-id"):
        index_by_id[app["bundle-id"]] = i

changed = False
added = updated = ok = 0
for bid, want_sound in wanted:
    target = BASE | (SOUND if want_sound else 0)
    path = resolve_path(bid)
    if bid in index_by_id:
        i = index_by_id[bid]
        app = apps[i]
        try:
            cur = int(app.get("flags") or 0)
        except Exception:
            cur = 0
        new = cur | (1 << 25) | (1 << 3) | (1 << 1) | (1 << 13) | (1 << 23)
        if want_sound:
            new |= SOUND
        else:
            new &= ~SOUND
        did = False
        if new != cur:
            app["flags"] = new
            did = True
        if path and app.get("path") != path:
            app["path"] = path
            did = True
        if did:
            updated += 1
            changed = True
            print(f"updated\t{bid}\t{cur}->{new}")
        else:
            ok += 1
            print(f"ok\t{bid}")
    else:
        entry = {
            "bundle-id": bid,
            "flags": target,
            "grouping": 0,
            "content_visibility": 0,
        }
        if path:
            entry["path"] = path
        apps.append(entry)
        added += 1
        changed = True
        print(f"added\t{bid}\tflags={target}\tpath={path or '-'}")

if changed:
    ncprefs.parent.mkdir(parents=True, exist_ok=True)
    with ncprefs.open("wb") as f:
        plistlib.dump(data, f, fmt=plistlib.FMT_BINARY)
    for proc in ("usernoted", "cfprefsd", "NotificationCenter"):
        subprocess.run(["killall", proc], stderr=subprocess.DEVNULL, check=False)
print(f"summary\tadded={added}\tupdated={updated}\tok={ok}\tchanged={int(changed)}", file=sys.stderr)
PY
}

_chris_ncprefs_upsert

# Configuration profile — pre-authorizes even before an app registers in ncprefs.
if [[ "${CHRIS_DEVSTRAP_SKIP_NOTIFICATION_PROFILE:-0}" == "1" ]]; then
  step_info "Skipping notifications .mobileconfig (CHRIS_DEVSTRAP_SKIP_NOTIFICATION_PROFILE=1)."
else
  _tpl="${CHRIS_DEVSTRAP_ROOT}/templates/notifications-preaccept.mobileconfig"
  _dest_dir="${HOME}/Library/Application Support/chris-devstrap"
  _dest="${_dest_dir}/chris-devstrap-notifications.mobileconfig"
  if [[ ! -f "$_tpl" ]]; then
    step_warn "Missing ${_tpl} — ncprefs upsert only."
  elif [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
    chris_run mkdir -p "$_dest_dir"
    chris_run cp "$_tpl" "$_dest"
    chris_run : "install or open notifications profile ${_dest}"
  else
    mkdir -p "$_dest_dir"
    cp "$_tpl" "$_dest"
    _installed=0
    # Best-effort CLI install (often still needs UI approval on modern macOS).
    if command -v profiles >/dev/null 2>&1; then
      if profiles install -type configuration "$_dest" >/dev/null 2>&1 ||
        profiles -I -F "$_dest" >/dev/null 2>&1; then
        _installed=1
        step_ok "Installed notifications configuration profile via profiles CLI."
      fi
    fi
    if [[ "$_installed" != "1" ]]; then
      open "$_dest" 2>/dev/null || true
      step_info "Opened notifications profile — confirm Install in System Settings if prompted."
      chris_manual_todo_block "Install chris-devstrap Notifications profile (pre-accepts standard apps):" \
        "  System Settings → Privacy & Security → Profiles → chris-devstrap — Pre-accept Notifications → Install" \
        "  Profile file: ${_dest}"
    fi
  fi
fi

step_ok "Notification pre-accept finished (Notes, Stocks, Messages, Reminders, App Store, iTerm, Chrome (+ helper), Find My, FaceTime, Maps, News, Passwords, Shortcuts, Weather, Zoom)."

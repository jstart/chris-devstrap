#!/usr/bin/env bash
# Add a GitHub SSH identity (primary or aliased) and wire it into ~/.ssh/config.
# Interactive — reads from /dev/tty. Re-run for additional aliased accounts.
#
# Primary  → key ~/.ssh/id_ed25519,        Host github.com           (default identity)
# Aliased  → key ~/.ssh/id_ed25519_<label>, Host github.com-<label>  (use git@github.com-<label>:owner/repo.git)
#
# When you mark a new account as primary AND an existing managed Host github.com
# block already exists for a different key, this script demotes the old block to
# Host github.com-jstart (override the alias when prompted) and rewrites this
# repo's `origin` so chris-devstrap keeps authenticating.
#
# Env (skip the matching prompt):
#   GH_LABEL=personal
#   GH_USERNAME=octocat
#   GH_EMAIL=octocat@example.com
#   GH_IS_PRIMARY=1|0
#   GH_DEMOTE_ALIAS=github.com-jstart   only used when promoting a new primary
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=ssh-config.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ssh-config.sh"

if [[ "$(uname -s)" != "Darwin" ]]; then
  step_warn "github-account-add.sh: macOS-only (uses pbcopy + open). Other platforms can adapt the SSH config block manually."
fi

_CHRIS_GH_DEMOTE_ALIAS_DEFAULT='github.com-jstart'

# Read a value from /dev/tty (or honor the env var if already set). Supports a default in [].
_chris_prompt() {
  local var="$1" prompt="$2" default="${3:-}"
  if [[ -n "${!var:-}" ]]; then
    return 0
  fi
  if [[ ! -r /dev/tty ]]; then
    if [[ -n "$default" ]]; then
      printf -v "$var" '%s' "$default"
      return 0
    fi
    step_warn "No TTY and no value supplied for $var — set the env var or run from an interactive terminal."
    exit 1
  fi
  local value
  if [[ -n "$default" ]]; then
    printf '%s [%s]: ' "$prompt" "$default" >/dev/tty
  else
    printf '%s: ' "$prompt" >/dev/tty
  fi
  IFS= read -r value </dev/tty || true
  [[ -z "$value" ]] && value="$default"
  printf -v "$var" '%s' "$value"
}

# Yes/no prompt → sets var to 1 or 0.
_chris_prompt_yn() {
  local var="$1" prompt="$2" default="${3:-n}"
  if [[ -n "${!var:-}" ]]; then
    case "${!var}" in
      1 | y | Y | yes | YES | true) printf -v "$var" '%s' 1 ;;
      *) printf -v "$var" '%s' 0 ;;
    esac
    return 0
  fi
  local hint
  case "$default" in y | Y | 1 | yes) hint='Y/n' ;; *) hint='y/N' ;; esac
  if [[ ! -r /dev/tty ]]; then
    case "$default" in y | Y | 1 | yes) printf -v "$var" '%s' 1 ;; *) printf -v "$var" '%s' 0 ;; esac
    return 0
  fi
  local value
  printf '%s [%s]: ' "$prompt" "$hint" >/dev/tty
  IFS= read -r value </dev/tty || true
  case "$value" in
    y | Y | yes | YES | 1) printf -v "$var" '%s' 1 ;;
    n | N | no | NO | 0) printf -v "$var" '%s' 0 ;;
    '') case "$default" in y | Y | 1 | yes) printf -v "$var" '%s' 1 ;; *) printf -v "$var" '%s' 0 ;; esac ;;
    *) printf -v "$var" '%s' 0 ;;
  esac
}

# If we are about to claim Host github.com but an existing block points at a different key,
# rename that block to Host github.com-jstart (or the alias the user chooses) so both keys coexist.
_chris_demote_existing_primary_if_needed() {
  local new_primary_key="$1" cfg="${HOME}/.ssh/config"
  [[ -f "$cfg" ]] || return 0

  local existing_id
  existing_id="$(chris_ssh_config_identity_for_host github.com)"
  [[ -z "$existing_id" ]] && return 0

  local expanded="${existing_id/#\~/$HOME}"
  if [[ "$expanded" == "$new_primary_key" ]]; then
    step_info "Host github.com already points at ${new_primary_key} — no demotion needed."
    return 0
  fi

  step_info "Host github.com currently points at ${existing_id}; demoting before claiming the primary slot."

  _chris_prompt GH_DEMOTE_ALIAS "Alias for the old primary key" "$_CHRIS_GH_DEMOTE_ALIAS_DEFAULT"
  if [[ -z "${GH_DEMOTE_ALIAS:-}" ]]; then
    GH_DEMOTE_ALIAS="$_CHRIS_GH_DEMOTE_ALIAS_DEFAULT"
  fi

  if chris_ssh_config_has_host "$GH_DEMOTE_ALIAS"; then
    # shellcheck disable=SC2088 # tilde is cosmetic in this user-facing message
    step_warn "~/.ssh/config already has a 'Host ${GH_DEMOTE_ALIAS}' block; not renaming. Resolve manually before re-running."
    exit 1
  fi

  chris_ssh_config_rename_host github.com "$GH_DEMOTE_ALIAS"
  step_ok "Renamed existing 'Host github.com' → 'Host ${GH_DEMOTE_ALIAS}' (still uses ${existing_id})."

  # Best-effort: update the marker comment that sits immediately above the renamed block.
  local cfg="${HOME}/.ssh/config" tmp
  tmp="$(mktemp)"
  awk -v alias="$GH_DEMOTE_ALIAS" '
    {
      if (prev ~ /^# chris-devstrap: github\.com \(managed block — safe to delete\)$/ && $0 ~ /^Host[[:space:]]+/ && $0 ~ alias) {
        prev = "# chris-devstrap: github.com → " alias " (managed block — safe to delete)"
      }
      if (NR > 1) print prev
      prev = $0
    }
    END { print prev }
  ' "$cfg" >"$tmp"
  mv "$tmp" "$cfg"
  chmod 600 "$cfg" 2>/dev/null || true

  # If THIS repo's origin used plain github.com, redirect it to the alias so chris-devstrap keeps working.
  if [[ -d "$ROOT/.git" ]]; then
    local cur new_url
    cur="$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)"
    if [[ "$cur" == git@github.com:* ]]; then
      new_url="${cur/git@github.com:/git@${GH_DEMOTE_ALIAS}:}"
      git -C "$ROOT" remote set-url origin "$new_url"
      step_ok "Updated chris-devstrap origin: ${cur} → ${new_url}"
    fi
  fi
}

main() {
  hr
  banner "Add GitHub SSH identity"

  _chris_prompt GH_LABEL "Short label (e.g. personal, work) — used for key filename + Host alias"
  _chris_prompt GH_USERNAME "GitHub username"
  _chris_prompt GH_EMAIL "Email for this account (used as the SSH key comment)"
  _chris_prompt_yn GH_IS_PRIMARY "Set this account as primary (Host github.com)?" "n"

  if [[ -z "${GH_USERNAME:-}" || -z "${GH_EMAIL:-}" ]]; then
    step_warn "GitHub username and email are required."
    exit 1
  fi

  local key host_alias
  if [[ "$GH_IS_PRIMARY" == "1" ]]; then
    key="${HOME}/.ssh/id_ed25519"
    host_alias="github.com"
  else
    if [[ -z "${GH_LABEL:-}" ]]; then
      step_warn "Non-primary accounts require a label."
      exit 1
    fi
    key="${HOME}/.ssh/id_ed25519_${GH_LABEL}"
    host_alias="github.com-${GH_LABEL}"
  fi

  mkdir -p "${HOME}/.ssh"
  chmod 700 "${HOME}/.ssh" 2>/dev/null || true

  if [[ "$GH_IS_PRIMARY" == "1" ]]; then
    _chris_demote_existing_primary_if_needed "$key"
  fi

  if [[ -f "$key" ]]; then
    step_info "Reusing existing SSH key: $key"
  else
    step_start "Generating ed25519 key ($key)"
    ssh-keygen -t ed25519 -C "$GH_EMAIL" -f "$key" -N ""
    step_ok "Created $key"
  fi

  if [[ ! -f "${key}.pub" ]]; then
    step_warn "Missing public key: ${key}.pub"
    exit 1
  fi

  chris_ssh_config_append_github_block "$host_alias" "$key"

  if command -v ssh-add >/dev/null 2>&1; then
    step_start "ssh-add (Apple keychain when available)"
    ssh-add --apple-use-keychain "$key" >/dev/null 2>&1 \
      || ssh-add "$key" \
      || step_warn "ssh-add failed — you can re-run: ssh-add --apple-use-keychain $key"
  fi

  if command -v pbcopy >/dev/null 2>&1; then
    pbcopy <"${key}.pub"
    step_ok "Public key copied to clipboard (pbcopy)."
  else
    step_info "pbcopy not available — copy the public key shown below manually."
  fi

  hr
  cat "${key}.pub"
  hr

  step_info "Opening https://github.com/settings/keys — sign in as ${GH_USERNAME} first if you have multiple GitHub sessions."
  if command -v open >/dev/null 2>&1; then
    open "https://github.com/settings/keys" >/dev/null 2>&1 || true
  fi

  if [[ -r /dev/tty ]]; then
    printf 'Press Enter after you have added this key to GitHub for %s… ' "$GH_USERNAME" >/dev/tty
    IFS= read -r _ </dev/tty || true
  fi

  step_start "Verifying ssh -T git@${host_alias}"
  local rc=0
  chris_github_ssh_verify_batchmode "$host_alias" || rc=$?
  printf '%s\n' "$CHRIS_SSH_VERIFY_OUTPUT"

  case "$rc" in
    0)
      if grep -Eq "^Hi ${GH_USERNAME}" <<<"$CHRIS_SSH_VERIFY_OUTPUT"; then
        step_ok "Authenticated as ${GH_USERNAME} via ${host_alias}."
      else
        step_ok "GitHub SSH OK via ${host_alias}."
        step_info "If the 'Hi <user>' line above doesn't match ${GH_USERNAME}, double-check the key was added to the right account."
      fi
      ;;
    2)
      step_warn "GitHub rejected the key — verify it was added to ${GH_USERNAME}'s account at https://github.com/settings/keys."
      exit 1
      ;;
    3)
      step_warn "ssh exited 255 — connection or host key problem."
      exit 1
      ;;
    *)
      step_warn "Could not confirm GitHub SSH authentication (exit ${CHRIS_SSH_VERIFY_CODE}). See the output above."
      exit 1
      ;;
  esac

  hr
  step_ok "Configured: ${GH_USERNAME} → Host ${host_alias} → ${key}"
  if [[ "$GH_IS_PRIMARY" == "1" ]]; then
    step_info "Default git@github.com: now uses this account."
    if [[ -n "${GH_DEMOTE_ALIAS:-}" ]]; then
      step_info "Previous primary key is reachable via git@${GH_DEMOTE_ALIAS}:owner/repo.git (this repo's origin was updated automatically)."
    fi
  else
    step_info "Use 'git@${host_alias}:owner/repo.git' as the remote URL for repos under this account."
  fi
}

main "$@"

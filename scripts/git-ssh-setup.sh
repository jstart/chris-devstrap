#!/usr/bin/env bash
# GitHub SSH + git origin for this repo (see README: CHRIS_DEVSTRAP_GIT_SSH_URL, SKIP_SSH, FORCE_SSH_SETUP).
set -euo pipefail

DEDICATED_KEY="${HOME}/.ssh/id_ed25519_chrisdevstrap"
PUB_KEY="${DEDICATED_KEY}.pub"

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
# shellcheck source=ssh-config.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/ssh-config.sh"

GIT_SSH_URL="$(chris_ssh_compute_git_ssh_url "$DEDICATED_KEY")"

# Full TTY, or stdin TTY + bootstrap saved interactive (stdout may be piped to tee from bootstrap).
_interactive_context_ok() {
  if [[ -t 0 && -t 1 ]]; then
    return 0
  fi
  if [[ -t 0 && "${CHRIS_DEVSTRAP_INTERACTIVE:-0}" == "1" ]]; then
    return 0
  fi
  return 1
}

_git_origin_url_ok() {
  local cur="$1" want="$2"
  [[ -n "$cur" && "$cur" == "$want" ]]
}

_die_no_tty() {
  step_warn "GitHub SSH setup requires an interactive terminal (stdin/stdout must be a TTY, or run from ./bootstrap.sh in a normal Terminal session)."
  step_info "This check avoids unattended runs hanging on prompts or failing silently."
  step_info "For CI or automation, set CHRIS_DEVSTRAP_SKIP_SSH=1 to skip this step (documented escape hatch)."
  exit 1
}

_ensure_github_ssh_config() {
  local cfg="${HOME}/.ssh/config"
  mkdir -p "${HOME}/.ssh"
  chmod 700 "${HOME}/.ssh" 2>/dev/null || true

  # If the chris-devstrap key is already configured under ANY host alias (default github.com
  # or a demoted alias like github.com-jstart from scripts/github-account-add.sh), don't add a
  # duplicate block that would fight the new primary.
  local existing_host
  existing_host="$(chris_ssh_config_host_for_identity_file "$DEDICATED_KEY" 2>/dev/null || true)"
  if [[ -n "$existing_host" ]]; then
    step_info "SSH config already routes ${DEDICATED_KEY} via 'Host ${existing_host}' (~/.ssh/config)."
    return 0
  fi

  if [[ -f "$cfg" ]] && grep -qF "chris-devstrap: github.com" "$cfg" 2>/dev/null; then
    step_info "SSH config already contains a chris-devstrap managed block (~/.ssh/config)."
    return 0
  fi

  {
    echo ""
    echo "# chris-devstrap: github.com (managed block — safe to delete)"
    echo "Host github.com"
    echo "  HostName github.com"
    echo "  User git"
    echo "  IdentityFile ~/.ssh/id_ed25519_chrisdevstrap"
    echo "  IdentitiesOnly yes"
  } >>"$cfg"
  chmod 600 "$cfg" 2>/dev/null || true
  step_ok "Appended github.com stanza to ~/.ssh/config (IdentitiesOnly + dedicated key)"
}

_verify_github_ssh() {
  # Talk to the Host alias the chris-devstrap key is actually routed under, so a demoted alias
  # like github.com-jstart is exercised (and gets host-key accepted) instead of the new primary.
  local target_host="github.com"
  local dedicated_host
  dedicated_host="$(chris_ssh_config_host_for_identity_file "$DEDICATED_KEY" 2>/dev/null || true)"
  if [[ -n "$dedicated_host" ]]; then
    target_host="$dedicated_host"
  fi
  step_start "Testing GitHub SSH (ssh -T git@${target_host})"
  set +e
  # accept-new: add github.com host key without interactive prompt; BatchMode: no password prompts.
  ssh_report="$(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -T "git@${target_host}" 2>&1)"
  ssh_code=$?
  set -e

  printf '%s\n' "$ssh_report"

  if grep -qi 'Permission denied' <<<"$ssh_report"; then
    step_warn "GitHub rejected the SSH key (Permission denied)."
    return 1
  fi
  if [[ "$ssh_code" -eq 255 ]]; then
    step_warn "ssh exited 255 — connection or host key problem."
    return 1
  fi
  if grep -Eq 'successfully authenticated|Welcome to GitHub|^Hi ' <<<"$ssh_report"; then
    step_ok "GitHub authenticated over SSH."
    return 0
  fi
  # GitHub often exits 1 while printing success text.
  if [[ "$ssh_code" -eq 1 ]] && grep -qi 'github\.com' <<<"$ssh_report" && ! grep -qi 'Permission denied' <<<"$ssh_report"; then
    step_ok "GitHub SSH test returned exit ${ssh_code} (common when GitHub prints your username)."
    return 0
  fi

  step_warn "Could not confirm GitHub SSH authentication (exit ${ssh_code})."
  return 1
}

_config_remote() {
  cd "$ROOT"
  hr
  step_start "Git remote (${GIT_SSH_URL})"

  if [[ ! -d "$ROOT/.git" ]]; then
    step_start "git init"
    git init
    git remote add origin "$GIT_SSH_URL"
    step_ok "Initialized repo and added origin"
  elif git remote get-url origin >/dev/null 2>&1; then
    cur="$(git remote get-url origin 2>/dev/null || true)"
    if _git_origin_url_ok "$cur" "$GIT_SSH_URL"; then
      step_ok "origin already set to SSH URL (${GIT_SSH_URL})"
    else
      git remote set-url origin "$GIT_SSH_URL"
      step_ok "Updated origin URL to SSH"
    fi
  else
    git remote add origin "$GIT_SSH_URL"
    step_ok "Added origin (SSH)"
  fi

  _optional_fetch
}

_optional_fetch() {
  step_start "git fetch origin (best-effort)"
  set +e
  git fetch origin 2>/dev/null || true
  set -e
  step_ok "fetch finished or skipped"
}

main() {
  if [[ "${CHRIS_DEVSTRAP_SKIP_SSH:-0}" == "1" ]]; then
    step_info "CHRIS_DEVSTRAP_SKIP_SSH=1 — skipping GitHub SSH setup (automation escape hatch)."
    exit 0
  fi

  # Fast path: desired SSH origin already set and GitHub auth works — no TTY needed.
  if [[ "${CHRIS_DEVSTRAP_FORCE_SSH_SETUP:-0}" != "1" ]] && [[ -d "$ROOT/.git" ]] && git -C "$ROOT" remote get-url origin >/dev/null 2>&1; then
    local cur
    cur="$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)"
    _ensure_github_ssh_config
    if _git_origin_url_ok "$cur" "$GIT_SSH_URL" && _verify_github_ssh; then
      hr
      step_ok "GitHub SSH and origin already configured — skipping prompts."
      exit 0
    fi
  fi

  if ! _interactive_context_ok; then
    _die_no_tty
  fi

  hr
  banner "GitHub SSH + origin"

  cat <<EOF
Bootstrap finishes by linking this folder to GitHub over SSH.

Default origin: ${GIT_SSH_URL}
Override with CHRIS_DEVSTRAP_GIT_SSH_URL.

This script uses a dedicated key at:
  ${DEDICATED_KEY}
If that file already exists, it is not overwritten. Private keys are never stored in the repo.

GitHub SSH test: \`ssh -T git@github.com\` often exits with status 1 on success
(when it prints your username). Exit 255 or "Permission denied" usually means auth failed.
EOF
  hr

  mkdir -p "${HOME}/.ssh"
  chmod 700 "${HOME}/.ssh" 2>/dev/null || true

  if [[ -f "$DEDICATED_KEY" ]]; then
    step_info "Using existing SSH key: ${DEDICATED_KEY}"
  else
    step_start "Creating ed25519 key (chris-devstrap)"
    ssh-keygen -t ed25519 -C "chris-devstrap" -f "$DEDICATED_KEY" -N ""
    step_ok "Created ${DEDICATED_KEY}"
  fi

  if [[ ! -f "$PUB_KEY" ]]; then
    step_warn "Missing public key: ${PUB_KEY}"
    exit 1
  fi

  _ensure_github_ssh_config

  if command -v ssh-add >/dev/null 2>&1; then
    if ssh-add -l >/dev/null 2>&1; then
      if ! ssh-add -l | grep -qF "$(basename "$DEDICATED_KEY")"; then
        step_start "ssh-add (session key)"
        ssh-add --apple-use-keychain "$DEDICATED_KEY" >/dev/null 2>&1 || ssh-add "$DEDICATED_KEY" || step_warn "Could not ssh-add; ensure your key works with GitHub SSH."
      fi
    else
      step_start "ssh-add (starting agent)"
      ssh-add --apple-use-keychain "$DEDICATED_KEY" >/dev/null 2>&1 || ssh-add "$DEDICATED_KEY" || step_warn "Could not ssh-add; ensure SSH can see your GitHub key."
    fi
  fi

  step_start "Public key + GitHub SSH settings"
  step_info "Public key file: ${PUB_KEY}"
  hr
  cat "$PUB_KEY"
  hr

  if command -v pbcopy >/dev/null 2>&1; then
    pbcopy <"$PUB_KEY"
    step_ok "Public key copied to clipboard (pbcopy)."
  else
    step_info "pbcopy not available — copy the public key above manually."
  fi

  step_info "Opening https://github.com/settings/keys"
  if command -v open >/dev/null 2>&1; then
    open "https://github.com/settings/keys"
  fi

  hr
  read -r -p "Press Enter after you have added this key to your GitHub account… " _

  if ! _verify_github_ssh; then
    step_warn "Fix SSH keys or ssh-agent, then re-run: ./scripts/git-ssh-setup.sh"
    exit 1
  fi

  _config_remote

  hr
  step_ok "GitHub SSH setup complete"
}

main "$@"

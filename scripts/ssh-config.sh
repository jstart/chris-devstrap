#!/usr/bin/env bash
# Shared ~/.ssh/config helpers for chris-devstrap (sourced; do not execute directly).
# shellcheck shell=bash

CHRIS_SSH_MANAGED_MARKER='# chris-devstrap: managed github identity'

chris_ssh_config_has_host() {
  local host="$1" cfg="${HOME}/.ssh/config"
  [[ -f "$cfg" ]] || return 1
  awk -v h="$host" '
    /^[[:space:]]*Host[[:space:]]/ {
      sub(/^[[:space:]]*Host[[:space:]]+/, "")
      for (i = 1; i <= NF; i++) if ($i == h) { found = 1; exit }
    }
    END { exit (found ? 0 : 1) }
  ' "$cfg"
}

chris_ssh_config_identity_for_host() {
  local host="$1" cfg="${HOME}/.ssh/config"
  [[ -f "$cfg" ]] || return 0
  awk -v h="$host" '
    BEGIN { in_block = 0 }
    /^[[:space:]]*Host[[:space:]]/ {
      in_block = 0
      sub(/^[[:space:]]*Host[[:space:]]+/, "")
      for (i = 1; i <= NF; i++) if ($i == h) { in_block = 1; next }
    }
    in_block && /^[[:space:]]*IdentityFile[[:space:]]+/ {
      sub(/^[[:space:]]*IdentityFile[[:space:]]+/, "")
      gsub(/[[:space:]]+$/, "")
      print
      exit
    }
  ' "$cfg"
}

# Print the Host alias whose IdentityFile matches key_path (expand ~).
chris_ssh_config_host_for_identity_file() {
  local key_path="$1" cfg="${HOME}/.ssh/config"
  [[ -f "$cfg" ]] || return 0
  awk -v key="$key_path" -v home="$HOME" '
    function expand(p) { sub(/^~\//, home "/", p); return p }
    /^[[:space:]]*Host[[:space:]]/ {
      cur_line = $0
      sub(/^[[:space:]]*Host[[:space:]]+/, "", cur_line)
      cur_count = split(cur_line, cur_hosts, /[[:space:]]+/)
    }
    /^[[:space:]]*IdentityFile[[:space:]]+/ {
      val = $0
      sub(/^[[:space:]]*IdentityFile[[:space:]]+/, "", val)
      gsub(/[[:space:]]+$/, "", val)
      if (expand(val) == key) {
        for (i = 1; i <= cur_count; i++) if (cur_hosts[i] != "") { print cur_hosts[i]; exit }
      }
    }
  ' "$cfg"
}

chris_ssh_config_rename_host() {
  local old="$1" new="$2" cfg="${HOME}/.ssh/config"
  [[ -f "$cfg" ]] || return 1
  local tmp
  tmp="$(mktemp)"
  awk -v old="$old" -v new="$new" '
    /^[[:space:]]*Host[[:space:]]/ {
      indent = ""
      match($0, /^[[:space:]]*/)
      indent = substr($0, RSTART, RLENGTH)
      line = $0
      sub(/^[[:space:]]*Host[[:space:]]+/, "", line)
      n = split(line, parts, /[[:space:]]+/)
      changed = 0
      for (i = 1; i <= n; i++) if (parts[i] == old) { parts[i] = new; changed = 1 }
      if (changed) {
        printf "%sHost", indent
        for (i = 1; i <= n; i++) if (parts[i] != "") printf " %s", parts[i]
        printf "\n"
        next
      }
    }
    { print }
  ' "$cfg" >"$tmp"
  mv "$tmp" "$cfg"
  chmod 600 "$cfg" 2>/dev/null || true
}

chris_ssh_config_append_github_block() {
  local host="$1"
  local key="$2"
  local marker="${3:-}"
  local cfg="${HOME}/.ssh/config"
  if [[ -z "$marker" ]]; then
    marker="${CHRIS_SSH_MANAGED_MARKER} (Host ${host} → $(basename "$key"))"
  fi
  mkdir -p "${HOME}/.ssh"
  chmod 700 "${HOME}/.ssh" 2>/dev/null || true
  touch "$cfg"
  if chris_ssh_config_has_host "$host"; then
    if declare -f step_info &>/dev/null; then
      # shellcheck disable=SC2088
      step_info "~/.ssh/config already has a 'Host ${host}' block — leaving it alone."
    fi
    return 0
  fi
  {
    echo ""
    echo "$marker"
    echo "Host ${host}"
    echo "  HostName github.com"
    echo "  User git"
    echo "  IdentityFile ${key}"
    echo "  IdentitiesOnly yes"
  } >>"$cfg"
  chmod 600 "$cfg" 2>/dev/null || true
  if declare -f step_ok &>/dev/null; then
    step_ok "Appended 'Host ${host}' block (IdentityFile ${key}) to ~/.ssh/config"
  fi
}

# git@<host>:owner/repo.git — host from dedicated key config or github.com.
chris_ssh_compute_git_ssh_url() {
  local dedicated_key="$1" default_repo="${2:-jstart/chris-devstrap.git}"
  if [[ -n "${CHRIS_DEVSTRAP_GIT_SSH_URL:-}" ]]; then
    printf '%s\n' "$CHRIS_DEVSTRAP_GIT_SSH_URL"
    return 0
  fi
  local host
  host="$(chris_ssh_config_host_for_identity_file "$dedicated_key" 2>/dev/null || true)"
  if [[ -z "$host" ]]; then
    host="github.com"
  fi
  printf 'git@%s:%s\n' "$host" "$default_repo"
}

#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

SNIPPET="$ROOT/templates/zshrc.snippet"
ALIASES_SNIPPET="$ROOT/templates/zsh-aliases.snippet"
MARKER="# chris-devstrap marker"

install_oh_my_zsh() {
  if [[ -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]]; then
    step_ok "Oh My Zsh already installed at ~/.oh-my-zsh"
    return 0
  fi
  step_start "Oh My Zsh (official installer)"
  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
    step_info "Would run Oh My Zsh install.sh with RUNZSH=no CHSH=no --unattended"
    return 0
  fi
  # Official install.sh exits if ~/.oh-my-zsh exists but is incomplete, or if ZSH is
  # exported (e.g. bootstrap run from a zsh that sets ZSH). Clear both.
  if [[ -d "$HOME/.oh-my-zsh" ]] && [[ ! -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]]; then
    step_warn "Removing incomplete ~/.oh-my-zsh (missing oh-my-zsh.sh) so the installer can run"
    rm -rf "${HOME:?}/.oh-my-zsh"
  fi
  (
    unset ZSH 2>/dev/null || true
    export RUNZSH=no CHSH=no
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
  )
  step_ok "Oh My Zsh installed"
}

merge_zshrc() {
  step_start "Merge ~/.zshrc (template + marker)"
  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
    step_info "Would merge Oh My Zsh settings into ~/.zshrc (see templates/zshrc.snippet)."
    return 0
  fi

  touch "$HOME/.zshrc"
  if grep -qF "$MARKER" "$HOME/.zshrc" 2>/dev/null; then
    step_ok "${HOME}/.zshrc already contains $MARKER — skipping merge"
    return 0
  fi

  if ! grep -qE 'oh-my-zsh\.sh' "$HOME/.zshrc" 2>/dev/null; then
    step_info "Writing minimal ~/.zshrc from chris-devstrap template"
    cp "$SNIPPET" "$HOME/.zshrc"
    printf '\n%s\n' "$MARKER" >>"$HOME/.zshrc"
    return 0
  fi

  step_info "Merging chris-devstrap defaults into existing ~/.zshrc"
  python3 - <<'PY'
import pathlib, re, sys

def replace_plugins_block(text: str) -> str:
    """Replace the first Oh My Zsh plugins=(...) block, including multiline, with bundled OMZ plugins."""
    lines = text.splitlines(keepends=True)
    out: list[str] = []
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        if re.match(r"^\s*plugins=\s*\(", line):
            depth = line.count("(") - line.count(")")
            i += 1
            while i < n and depth > 0:
                depth += lines[i].count("(") - lines[i].count(")")
                i += 1
            out.append("plugins=(git history-substring-search)\n")
            continue
        out.append(line)
        i += 1
    return "".join(out)


p = pathlib.Path.home() / ".zshrc"
text = p.read_text(encoding="utf-8", errors="replace")
if "chris-devstrap marker" in text:
    sys.exit(0)
if re.search(r"^ZSH_THEME=", text, flags=re.M):
    text = re.sub(r"^ZSH_THEME=.*$", 'ZSH_THEME="robbyrussell"', text, flags=re.M, count=1)
else:
    m = re.search(r"^\s*source\s+.*oh-my-zsh\.sh\s*$", text, flags=re.M)
    if m:
        i = m.start()
        text = text[:i] + 'ZSH_THEME="robbyrussell"\n' + text[i:]
    else:
        m2 = re.search(r"^export\s+ZSH=.*$", text, flags=re.M)
        if m2:
            i = m2.end()
            text = text[:i] + '\nZSH_THEME="robbyrussell"' + text[i:]
        else:
            text = 'ZSH_THEME="robbyrussell"\n' + text
if re.search(r"^\s*plugins=\s*\(", text, flags=re.M):
    text = replace_plugins_block(text)
p.write_text(text.rstrip() + "\n\n# chris-devstrap marker\n", encoding="utf-8")
PY
}

sanitize_zshrc_artifacts() {
  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
    return 0
  fi
  [[ -f "$HOME/.zshrc" ]] || return 0
  python3 - <<'PY'
import pathlib, re

def is_complete_plugins_line(s: str) -> bool:
    s = s.strip()
    if not s.startswith("plugins=(") or not s.endswith(")"):
        return False
    return s.count("(") == s.count(")")


p = pathlib.Path.home() / ".zshrc"
raw = p.read_text(encoding="utf-8", errors="replace")
lines = raw.splitlines(keepends=True)
lines = [ln for ln in lines if not re.match(r"^\s*history-substring-search\s*$", ln)]
out: list[str] = []
i = 0
n = len(lines)
while i < n:
    ln = lines[i]
    if is_complete_plugins_line(ln):
        out.append(ln)
        i += 1
        # Leftovers from a broken multiline merge: bare plugin tokens then a lone ')'
        while i < n:
            nxt = lines[i]
            if re.match(r"^\s*\)\s*$", nxt):
                i += 1
                break
            if re.match(r"^\s*[a-z][a-z0-9_-]*\s*$", nxt, re.I):
                i += 1
                continue
            break
        continue
    if re.match(r"^\s*\)\s*$", ln) and out and is_complete_plugins_line(out[-1]):
        i += 1
        continue
    out.append(ln)
    i += 1
new = "".join(out)
if new != raw:
    p.write_text(new, encoding="utf-8")
PY
}

append_shell_extras() {
  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
    return 0
  fi
  if grep -qE 'fzf/shell/key-bindings\.zsh|chris-devstrap: fzf \+ zsh-autosuggestions' "$HOME/.zshrc" 2>/dev/null; then
    return 0
  fi
  step_start "Append fzf + zsh-autosuggestions to ~/.zshrc"
  cat >>"$HOME/.zshrc" <<'EOF'

# --- chris-devstrap: fzf + zsh-autosuggestions (begin) ---
if [[ -r /opt/homebrew/opt/fzf/shell/completion.zsh ]]; then
  source /opt/homebrew/opt/fzf/shell/completion.zsh
  source /opt/homebrew/opt/fzf/shell/key-bindings.zsh
elif [[ -r /usr/local/opt/fzf/shell/completion.zsh ]]; then
  source /usr/local/opt/fzf/shell/completion.zsh
  source /usr/local/opt/fzf/shell/key-bindings.zsh
fi
for _chris_as in /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh /usr/local/share/zsh-autosuggestions/zsh-autosuggestions.zsh; do
  [[ -r "$_chris_as" ]] && source "$_chris_as" && break
done
unset _chris_as
# --- chris-devstrap: fzf + zsh-autosuggestions (end) ---
EOF
  step_ok "Shell extras block appended"
}

append_shell_aliases() {
  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
    step_info "Would append shell aliases to ~/.zshrc (see templates/zsh-aliases.snippet)."
    return 0
  fi
  if [[ ! -f "$ALIASES_SNIPPET" ]]; then
    step_warn "Missing $ALIASES_SNIPPET — skipping shell aliases append."
    return 0
  fi
  if grep -qF 'chris-devstrap: shell aliases (begin)' "$HOME/.zshrc" 2>/dev/null; then
    return 0
  fi
  step_start "Append shell aliases to ~/.zshrc"
  cat "$ALIASES_SNIPPET" >>"$HOME/.zshrc"
  printf '\n' >>"$HOME/.zshrc"
  step_ok "Shell aliases appended"
}

install_dismiss_mac_notifications() {
  local src="$ROOT/templates/dismiss-mac-notifications"
  local dest="${HOME}/bin/DismissMacNotifications"
  step_start "Dismiss Notification Center scripts (${dest})"
  if [[ ! -f "$src/dismiss-notifications.sh" ]] || [[ ! -f "$src/dismiss-notifications.jxa" ]]; then
    step_warn "Missing $src/dismiss-notifications.{sh,jxa} — skipping"
    return 0
  fi
  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
    step_info "Would mkdir -p $dest and copy dismiss-notifications.{sh,jxa}; chmod +x shell wrapper"
    return 0
  fi
  mkdir -p "$dest"
  cp -f "$src/dismiss-notifications.sh" "$src/dismiss-notifications.jxa" "$dest/"
  chmod +x "$dest/dismiss-notifications.sh"
  step_ok "Scripts installed (JXA UI automation; Accessibility required for the calling app)"
  if [[ -f "$src/KEYBOARD_SHORTCUT_SETUP.txt" ]]; then
    cp -f "$src/KEYBOARD_SHORTCUT_SETUP.txt" "$dest/"
  fi
}

append_dismiss_notifications_shell() {
  if [[ "${CHRIS_DEVSTRAP_DRY_RUN:-}" == 1 ]]; then
    step_info "Would append dismissnotifications helper to ~/.zshrc if missing"
    return 0
  fi
  [[ -f "$HOME/.zshrc" ]] || touch "$HOME/.zshrc"
  if grep -qF 'chris-devstrap: dismiss mac notifications (begin)' "$HOME/.zshrc" 2>/dev/null; then
    return 0
  fi
  step_start "Append dismissnotifications to ~/.zshrc"
  cat >>"$HOME/.zshrc" <<'EOF'

# --- chris-devstrap: dismiss mac notifications (begin) ---
# Installed to ~/bin/DismissMacNotifications (see KEYBOARD_SHORTCUT_SETUP.txt there for Shortcuts).
# First run: grant Accessibility for Terminal / iTerm / Shortcuts when macOS prompts.
dismissnotifications() {
  command "${HOME}/bin/DismissMacNotifications/dismiss-notifications.sh" "$@"
}
# --- chris-devstrap: dismiss mac notifications (end) ---
EOF
  step_ok "dismissnotifications block appended"
}

install_oh_my_zsh
merge_zshrc
sanitize_zshrc_artifacts
append_shell_extras
append_shell_aliases
install_dismiss_mac_notifications
append_dismiss_notifications_shell

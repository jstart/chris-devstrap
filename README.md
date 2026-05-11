# chris-devstrap

One-shot macOS bootstrap: Homebrew bundle, Zsh/Oh My Zsh, global Git hints, Finder defaults, Dock (`defaults` + `dockutil`), Raycast prep, optional Xcode components, then GitHub SSH + `origin` when still needed. Logs append to `~/Library/Logs/chris-devstrap.log` on full `./bootstrap.sh` runs.

**Mac App Store:** Apple does not support unattended `mas signin` on modern macOS — sign into the App Store (or Apple Account) in the UI first; then `mas install` works for your purchases. See [mas-cli/mas#164](https://github.com/mas-cli/mas/issues/164).

## Run

**One-liner (clone + bootstrap)** — default clone path is `~/Developer/Personal/chris-devstrap` (override with `CHRIS_DEVSTRAP_CLONE_DIR`):

```bash
curl -fsSL https://raw.githubusercontent.com/jstart/chris-devstrap/main/install.sh | bash
```

Pass flags through to `bootstrap.sh` (e.g. dry-run):

```bash
curl -fsSL https://raw.githubusercontent.com/jstart/chris-devstrap/main/install.sh | bash -s -- --dry-run
```

**From a clone:**

```bash
cd ~/Developer/Personal/chris-devstrap   # or your clone path
chmod +x bootstrap.sh scripts/*.sh
./bootstrap.sh
```

### First-time publish to GitHub (maintainer)

The **`curl`** URL above only works after this repo exists on GitHub with **`main`** containing `install.sh`. From this directory, with [GitHub CLI](https://cli.github.com/) authenticated:

```bash
gh auth login
gh repo create jstart/chris-devstrap --public \
  --description "One-shot macOS bootstrap: Homebrew, Zsh, defaults, Dock, Raycast prep, SSH" \
  --source=. --remote=origin --push
```

If **`origin`** already exists (empty repo on GitHub), use **`git push -u origin main`** instead. Then confirm Actions: **https://github.com/jstart/chris-devstrap/actions**.

**Do not run the whole repo as root.** `defaults`, Dock, `~/.zprofile`, `~/.ssh`, and `git config --global` are per-user. After `brew.sh` puts Homebrew on `PATH`, bootstrap runs `sudo -v` once and keeps the ticket alive in the background so a long `brew bundle` (or other steps that need `sudo`) does not hit an expired credential mid-run. Set `CHRIS_DEVSTRAP_SKIP_SUDO_PRIME=1` to skip that.

## Commands


| Command | What it does |
|--------|----------------|
| `./bootstrap.sh` | Full bootstrap: **9** ordered steps (brew → bundle → zsh + git-config → macOS defaults → Xcode components (if full Xcode) → Finder sidebar → Dock → Raycast hotkey prep → SSH/origin when needed). Idempotent for most steps. Prints **wall time** at the end. |
| `./bootstrap.sh rerun` | Same as no subcommand. |
| `./bootstrap.sh --dry-run` | Prints planned `defaults` / `dockutil` / etc. via `chris_run`; skips `brew bundle install` and SSH setup. Exits `0` early if brew is still missing (preview only). |
| `./bootstrap.sh --verbose` | Same as full bootstrap with `set -x` (shell trace) after helpers load. Combine with other flags as needed. |
| `./bootstrap.sh doctor` | Runs `brew doctor` (non-fatal, if brew is on PATH), then the same checks as **healthcheck**. |
| `./bootstrap.sh healthcheck` | Runs `scripts/healthcheck.sh` (macOS-only checks; see exit policy below). |
| `./bootstrap.sh update` | Runs `scripts/update.sh`: `brew update`, `brew upgrade`, then `brew bundle install --no-upgrade` for `Brewfile` (and for `Brewfile.dev` when that file exists, unless `CHRIS_DEVSTRAP_SKIP_DEV_BUNDLE=1`). Optional `brew cleanup` when `CHRIS_DEVSTRAP_CLEANUP=1`. |


**Environment (common):**


| Variable | Role |
|----------|------|
| `CHRIS_DEVSTRAP_DRY_RUN=1` | Dry-run mode (`--dry-run` sets this). |
| `CHRIS_DEVSTRAP_VERBOSE=1` | Trace bootstrap with `set -x` (or pass `--verbose`). |
| `CHRIS_DEVSTRAP_FUN=1` | Append a random one-liner to bootstrap banners (off by default). |
| `CHRIS_DEVSTRAP_INTERACTIVE` | Set by bootstrap/update when stdout is a TTY (colors + `git-ssh-setup` TTY rules with `tee`). |
| `CHRIS_DEVSTRAP_SKIP_DEV_BUNDLE=1` | Skip `Brewfile.dev` for this run (otherwise installed when that file exists). |
| `CHRIS_DEVSTRAP_CLEANUP=1` | With `./bootstrap.sh update`, run `brew cleanup` after bundle. |
| `CHRIS_DEVSTRAP_SKIP_SUDO_PRIME=1` | Skip sudo prime/keepalive before bundle/defaults. |
| `CHRIS_DEVSTRAP_SILENCE_UI_SOUNDS=1` | During `macos-defaults.sh`, disable **all** macOS UI sound effects (`com.apple.systemsound` + `-g` / NSGlobalDomain `com.apple.sound.uiaudio.enabled` — same scope as **System Settings → Sound → Sound Effects**; includes the screenshot “camera” sound; Apple has no screenshot-only toggle). |
| `CHRIS_DEVSTRAP_SKIP_DEFAULT_BROWSER=1` | Skip the default-browser step in `macos-defaults.sh`. |
| `CHRIS_DEVSTRAP_SKIP_HEADSHOT=1` | Skip `scripts/headshot.sh` (no `Downloads` copy / no `dscl` user picture). |
| `CHRIS_DEVSTRAP_DEFAULT_BROWSER` | First argument to `defaultbrowser` when Chrome is installed (default `chrome`). |
| `CHRIS_DEVSTRAP_GIT_SSH_URL` | Desired SSH `origin` (default `git@github.com:jstart/chris-devstrap.git`). |
| `CHRIS_DEVSTRAP_SKIP_SSH=1` | Skip `git-ssh-setup.sh` (automation). |
| `CHRIS_DEVSTRAP_FORCE_SSH_SETUP=1` | Always run SSH wizard from bootstrap (disables fast path in `git-ssh-setup.sh`). |
| `HOMEBREW_BUNDLE_NO_UPGRADE=1` | Same “no upgrade on bundle” behavior as `brew bundle install --no-upgrade` (see `brew bundle install --help`). |
| `HOMEBREW_BUNDLE_BREW_SKIP` / `_CASK_SKIP` / `_MAS_SKIP` / `_TAP_SKIP` | Space-separated tokens to skip for this run (also honored by update). |


**`brew bundle`:** This repo uses `brew bundle install --no-upgrade --file=…` (not deprecated `--no-lock`; Homebrew 5 removed `--no-lock`). `brew bundle check --no-upgrade` means “present,” not “latest” — use `./bootstrap.sh update` or `brew upgrade` when you want versions to move. The Brewfile includes **`gh`** (GitHub CLI) and **`jira-cli`** (Jira CLI; command **`jira`** — do not install **`go-jira`** alongside it).

**Healthcheck / exit codes:** `./bootstrap.sh healthcheck` exits `1` on non-macOS, missing `brew`/`git`, bad CLT, failed `brew bundle check --no-upgrade` for `Brewfile` (and for `Brewfile.dev` when that file exists and `CHRIS_DEVSTRAP_SKIP_DEV_BUNDLE` is not set), failed GitHub SSH or `dockutil` checks, or any failed check reported above. `brew doctor` is never fatal inside `healthcheck.sh`. `./scripts/git-ssh-setup.sh` exits `0` when skipped (`CHRIS_DEVSTRAP_SKIP_SSH`), on fast path (matching `origin` + working `ssh -T`), or after interactive success; `1` when a TTY is required but missing, SSH verification fails, or keys are missing.

**SSH note:** `ssh -T git@github.com` often exits `1` with a success message ([docs](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/testing-your-ssh-connection)); exit `255` or “Permission denied” is a real failure.

**CI:** [`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs `bash -n` and **ShellCheck** (pinned release) on `bootstrap.sh` and `scripts/*.sh` (Ubuntu; no macOS integration). Repo root [`.shellcheckrc`](.shellcheckrc) disables `SC1091` for dynamic `source` paths.

## What runs where

| Area | Script / files |
|------|----------------|
| Homebrew + CLT + `~/.zprofile` shellenv | `scripts/brew.sh` |
| Bundle | `Brewfile` (+ `Brewfile.dev` when present unless `CHRIS_DEVSTRAP_SKIP_DEV_BUNDLE=1`); for **`mas install`**, sign into the Mac App Store in the UI first (see **Mac App Store** above). |
| Zsh / Oh My Zsh + snippet | `scripts/zsh.sh`, `templates/zshrc.snippet`, `templates/zsh-aliases.snippet` (git/shell shortcuts appended if missing) |
| Global Git defaults (no user.name) | `scripts/git-config.sh` |
| Finder (new window **Downloads**, column view, **date-modified** sort defaults + PlistBuddy best effort); Desktop & Dock window prefs; trackpad (**tap to click** + firm press / Force Click off); screenshots; default browser (`defaultbrowser` when installed); hot corners; hide desktop widgets; global **`NSNavLastRootDirectory`** hint for some open/save sheets | `scripts/macos-defaults.sh` |
| Headshot → **`~/Downloads/headshot.png`** + macOS **local user** login picture (`dscl`, needs **`assets/headshot.png`** in the repo) | `scripts/headshot.sh` (see [`assets/README.md`](assets/README.md); Apple ID / Chrome / Messages avatars stay manual) |
| Xcode first launch + iOS Simulator download | `scripts/xcode-components.sh` (skipped without full Xcode / on dry-run; errors are warnings) |
| `~/Developer` layout + sidebar | `scripts/finder-sidebar.sh` |
| Dock | `scripts/dock.sh` — `defaults` for autohide + **tilesize / largesize 128**; `dockutil --remove all`, `config/dock-remove.txt`, `config/dock-add.tsv`; **`~/Downloads`** fan (**others**, date modified); `killall Dock` |
| Raycast / Spotlight | `scripts/raycast-hotkey.sh` |
| GitHub SSH + `origin` | `scripts/git-ssh-setup.sh` (end of bootstrap when criteria match) |
| Raycast / Cursor / iTerm + iTerm hints | `scripts/iterm.sh` opens those apps when present (iTerm with repo path); respects dry-run |


## Manual steps

### Google Chrome — profile for **[cleetruman@gmail.com](mailto:cleetruman@gmail.com)**

Open Chrome → profile menu → Add / Sign in → complete sign-in for that account; optional profile name/avatar.

### Apple ID / iCloud — Calendar + Contacts (example)

**System Settings → Apple ID → iCloud:** enable what you want (e.g. Calendars, Contacts); turn off Mail/Notes/iCloud Drive if you do not want them. Mirror on iPhone if needed.

### Other apps

- **Cursor** — Sign in with Google.
- **iTerm2** — **Settings (⌘,)** → **Profiles** → your profile → **Keys** → **Key Bindings** → **Presets…** → **Natural Text Editing** (repeat per profile if you use more than one).
- **Raycast** — Root hotkey **⌘Space** (after bootstrap frees Spotlight where possible). **Disable AI:** **Settings → AI** (global switch). **Extensions:** **Settings → Extensions** → **Enabled** column per row (Raycast has no stable CLI for this). **Screenshot sound** is macOS UI sound (see **`CHRIS_DEVSTRAP_SILENCE_UI_SOUNDS`** or **System Settings → Sound → Sound Effects**). Window Management / Clipboard / checklist lines come from `scripts/raycast-hotkey.sh`.
- **Xcode** — Install from App Store or `mas`; `sudo xcodebuild -license accept` when prompted. Simulator runtimes and predictive completion: use **Xcode → Settings → Components / Text Editing** (Apple has no stable headless flow for all optional downloads).

### Microphone, camera, screen recording

macOS TCC cannot be granted from this repo. Use each app once, then **System Settings → Privacy & Security** to enable Chrome/Safari/Zoom as needed; quit and reopen after toggling Screen Recording.

## Troubleshooting

- **Appearance still light** — `defaults write … AppleInterfaceStyle` can lag until **System Settings → Appearance → Dark** is toggled once, a **full logout/login**, or **Apple Intelligence / accent** quirks on newer macOS; bootstrap also restarts Finder afterward.
- **Desktop & Dock → Windows** — Bootstrap sets `AppleWindowTabbingMode`, `NSCloseAlwaysConfirmsChanges`, and `NSQuitAlwaysKeepsWindows` on `NSGlobalDomain`, plus `StandardHideWidgets` on `com.apple.WindowManager` (hide desktop widgets). **System Settings** may show stale labels until that pane is reopened; per-app behavior can require **quitting the app** (some cache). Logout is rarely needed; bootstrap already `killall`s Finder, SystemUIServer, and Dock.
- **Trackpad → tap to click** — `macos-defaults.sh` sets built-in + Bluetooth `Clicking` and `com.apple.mouse.tapBehavior` (`1` = tap to click). If **System Settings → Trackpad** still shows it off, close that pane and reopen, or log out/in (same pattern as other `defaults` UI lag).
- **File dialogs / column sort** — Bootstrap sets **Finder** new windows to **`~/Downloads`**, prefers **column view**, and writes **date-modified** sort/arrange defaults plus best-effort **PlistBuddy** patches. **Every app’s** open/save sheet still remembers its own last folder unless the app respects **`NSNavLastRootDirectory`**; there is no Apple-documented global “always Downloads” for all apps. Stale **`.DS_Store`** files can keep old sort—remove them or **Finder → View → Show View Options → Use as Defaults** on a representative folder.
- **Headshot / user picture** — Add your photo as **`assets/headshot.png`** in the repo, then re-run bootstrap. **`dscl`** may require **sudo** and can fail on some builds; use **System Settings → Users & Groups** and drag **`~/Downloads/headshot.png`** onto your avatar. **Apple ID, Chrome, Messages,** etc. do not share one API—use **`assets/README.md`** and the end-of-bootstrap **Manual follow-ups** lines for those.
- **`brew` not in new terminals** — Ensure `~/.zprofile` contains the brew shellenv block from `scripts/brew.sh`.
- **`~/.zshrc`: `command not found: history-substring-search` / parse error near `)`** — Usually a broken multiline `plugins=(` … `)` block. A common leftover is `plugins=(git)` followed by bare `git` and `)` (running `git` with no args prints the usage banner). **`scripts/zsh.sh`** merges multiline `plugins` and **sanitizes** orphan lines. Re-run **`bash scripts/zsh.sh`** or fix by hand: one valid `plugins=(…)` line and no stray plugin lines.
- **Opening a terminal prints `git` usage** — Follow-on from a broken **`~/.zshrc`**; fix **`plugins=`** then `exec zsh`.
- **`oh-my-zsh.sh`: no such file or directory** — Run **`bash scripts/zsh.sh`** to install Oh My Zsh. **`templates/zshrc.snippet`** only sources OMZ when **`oh-my-zsh.sh`** exists.
- **Oh My Zsh installer: “The `$ZSH` folder already exists”** — Incomplete **`~/.oh-my-zsh`** or exported **`ZSH`**; **`scripts/zsh.sh`** removes incomplete trees and runs the installer with **`ZSH` unset** in a subshell.
- **`gitclean` / parse error near `()`** — Do not define both **`alias gitclean=...`** and **`gitclean()`**; the snippet runs **`unalias gitclean`** before the function.
- **`sbedit` / `mysides` on PATH** — Optional for Finder sidebar automation; install manually if you want scripted sidebar edits. Bootstrap does not require them.
- **`mas install` fails** — Complete App Store sign-in in the UI first (see **Mac App Store** at the top); mas 7+ has no `mas account`.
- **Dockutil “Remove failed”** — Harmless for items that were never in the Dock.
- **Dock icons still look small** — Many Dock tiles cause macOS to shrink them to fit the strip.

## License

Use and modify freely for your own machines.

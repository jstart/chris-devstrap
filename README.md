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

**Do not run the whole repo as root.** `defaults`, Dock, `~/.zprofile`, `~/.ssh`, and `git config --global` are per-user. Before Homebrew install, bootstrap runs `sudo -v` once (via `/dev/tty`, so `curl | bash` still gets a password prompt) and keeps the ticket alive in the background — the official Homebrew installer is `NONINTERACTIVE` (`sudo -n`) and will not ask for a password itself. Set `CHRIS_DEVSTRAP_SKIP_SUDO_PRIME=1` to skip that.

## Commands


| Command | What it does |
|--------|----------------|
| `./bootstrap.sh` | Full bootstrap: **10** ordered steps (brew → bundle → zsh + git-config + gh extensions → macOS defaults → Xcode components (if full Xcode) → Finder sidebar → Dock → Raycast hotkey prep → SSH/origin when needed → **heavy installs (Xcode via mas + Android Studio; deferred so the long downloads run last and never block earlier setup)**). Idempotent for most steps. Prints **wall time** at the end. |
| `./bootstrap.sh rerun` | Same as no subcommand. |
| `./bootstrap.sh --dry-run` | Prints planned `defaults` / `dockutil` / etc. via `chris_run`; skips `brew bundle install` and SSH setup. Exits `0` early if brew is still missing (preview only). |
| `./bootstrap.sh --verbose` | Same as full bootstrap with `set -x` (shell trace) after helpers load. Combine with other flags as needed. |
| `./bootstrap.sh doctor` | Runs `brew doctor` (non-fatal, if brew is on PATH), then the same checks as **healthcheck**. |
| `./bootstrap.sh healthcheck` | Runs `scripts/healthcheck.sh` (macOS-only checks; see exit policy below). |
| `./bootstrap.sh update` | Runs `scripts/update.sh`: `brew update`, `brew upgrade`, then `brew bundle install --no-upgrade` for `Brewfile` (and for `Brewfile.dev` when that file exists, unless `CHRIS_DEVSTRAP_SKIP_DEV_BUNDLE=1`). Optional `brew cleanup` when `CHRIS_DEVSTRAP_CLEANUP=1`. Does **not** install `Brewfile.heavy` unless `CHRIS_DEVSTRAP_INCLUDE_HEAVY=1`. |


**Environment (common):**


| Variable | Role |
|----------|------|
| `CHRIS_DEVSTRAP_DRY_RUN=1` | Dry-run mode (`--dry-run` sets this). |
| `CHRIS_DEVSTRAP_VERBOSE=1` | Trace bootstrap with `set -x` (or pass `--verbose`). |
| `CHRIS_DEVSTRAP_FUN=1` | Append a random one-liner to bootstrap banners (off by default). |
| `CHRIS_DEVSTRAP_REF` | Git branch/tag for `install.sh` to clone/checkout (default **`main`**). Required when curling a PR branch’s `install.sh` — otherwise the clone stays on `main` and branch fixes never run. |
| `CHRIS_DEVSTRAP_INTERACTIVE` | Set by bootstrap/update when a usable terminal is detected (stdout/stdin TTY, or `/dev/tty` — so `curl | bash` still gets guided manual steps + SSH prompts). |
| `CHRIS_DEVSTRAP_SKIP_DEV_BUNDLE=1` | Skip `Brewfile.dev` for this run (otherwise installed when that file exists). |
| `CHRIS_DEVSTRAP_CLEANUP=1` | With `./bootstrap.sh update`, run `brew cleanup` after bundle. |
| `CHRIS_DEVSTRAP_SKIP_SUDO_PRIME=1` | Skip sudo prime/keepalive before Homebrew / bundle / defaults. |
| `CHRIS_DEVSTRAP_OPEN_FILES_LIMIT` | Soft `ulimit -n` target before brew bundle/upgrade (default **10240**). Raises macOS’s low default so large bundles avoid `Too many open files`. |
| `CHRIS_DEVSTRAP_SILENCE_UI_SOUNDS` | **Default on:** unset or non-`0` disables **all** macOS UI sound effects during `macos-defaults.sh` (same scope as **System Settings → Sound → Sound Effects**; includes screenshot shutter). Set to **`0`** to leave UI sounds enabled. Apple has no screenshot-only toggle. |
| `CHRIS_DEVSTRAP_KEEP_APP_NOTIFICATION_SOUNDS=1` | Keep Messages / Reminders notification sounds. Default: mute those two while pre-accepting notifications for standard apps. |
| `CHRIS_DEVSTRAP_GIT_USER_NAME` | Global `git user.name` (default **Christopher Truman**). Always written by `git-config.sh`. |
| `CHRIS_DEVSTRAP_FORCE_GIT_EMAIL=1` | Re-queue the guided `user.email` iTerm step even when email is already set. |
| `CHRIS_DEVSTRAP_SKIP_NOTIFICATION_PROFILE=1` | Skip installing/opening the `.mobileconfig`; still upserts `ncprefs`. |
| `CHRIS_DEVSTRAP_SKIP_SBEDIT_INSTALL=1` | Skip downloading/installing the **sbedit** `.pkg` in `finder-sidebar.sh` (sidebar CLI has no Homebrew formula). |
| `CHRIS_DEVSTRAP_SBEDIT_PKG_URL` | Override URL for the **sbedit** installer pkg (default: sidebar-editor **1.0** release asset on GitHub). |
| `CHRIS_DEVSTRAP_SKIP_ITERM_REUSE_DIRECTORY=1` | Skip patching iTerm2's plist for **Initial directory → Reuse previous session** (`scripts/iterm.sh`). |
| `CHRIS_DEVSTRAP_SKIP_DEFAULT_BROWSER=1` | Skip the default-browser step in `macos-defaults.sh`. |
| `CHRIS_DEVSTRAP_SKIP_HEADSHOT=1` | Skip `scripts/headshot.sh` (no `Downloads` copy / no `dscl` user picture). |
| `CHRIS_DEVSTRAP_FORCE_HEADSHOT=1` | Overwrite the local user picture in `scripts/headshot.sh` even when one is already set. Without it, headshot copies to `~/Downloads/headshot.png` but skips the `sudo dscl` mutation when an avatar is already configured. |
| `CHRIS_DEVSTRAP_WAIT_CLT=1` | After `xcode-select --install`, poll until CLT finishes instead of exit-and-re-run. **Default on** for interactive `install.sh` one-liner (TTY); **default off** for `./bootstrap.sh` / piped runs. |
| `CHRIS_DEVSTRAP_INCLUDE_HEAVY=1` | With `./bootstrap.sh update`, also run `brew bundle install --no-upgrade --file=Brewfile.heavy`. |
| `CHRIS_DEVSTRAP_SKIP_HEAVY=1` | Skip the **heavy installs** step (`scripts/heavy-installs.sh`, last bootstrap step). Queues a manual_todo with the exact `brew bundle install --no-upgrade --file=Brewfile.heavy` command. |
| `CHRIS_DEVSTRAP_HEAVY_NONINTERACTIVE=1` | Skip the Enter prompt before heavy downloads (assumes Apple ID + Mac App Store sign-in was completed during the guided checklist). |
| `CHRIS_DEVSTRAP_DEFAULT_BROWSER` | First argument to `defaultbrowser` when Chrome is installed (default `chrome`). |
| `CHRIS_DEVSTRAP_GIT_SSH_URL` | Desired SSH `origin`. When unset, `git-ssh-setup.sh` parses `~/.ssh/config` for whichever Host alias routes `~/.ssh/id_ed25519_chrisdevstrap` and defaults to `git@<that-alias>:jstart/chris-devstrap.git`; falls back to `git@github.com:jstart/chris-devstrap.git`. |
| `CHRIS_DEVSTRAP_SKIP_SSH=1` | Skip `git-ssh-setup.sh` (automation). |
| `CHRIS_DEVSTRAP_FORCE_SSH_SETUP=1` | Always run SSH wizard from bootstrap (disables fast path in `git-ssh-setup.sh`). |
| `GH_LABEL`, `GH_USERNAME`, `GH_EMAIL`, `GH_IS_PRIMARY`, `GH_DEMOTE_ALIAS` | Inputs for `scripts/github-account-add.sh` (see "Multiple GitHub accounts"). When set, the matching prompt is skipped. |
| `HOMEBREW_BUNDLE_NO_UPGRADE=1` | Same “no upgrade on bundle” behavior as `brew bundle install --no-upgrade` (see `brew bundle install --help`). |
| `HOMEBREW_BUNDLE_BREW_SKIP` / `_CASK_SKIP` / `_MAS_SKIP` / `_TAP_SKIP` | Space-separated tokens to skip for this run (also honored by update). |


**`brew bundle`:** This repo uses `brew bundle check --no-upgrade` before `brew bundle install --no-upgrade --file=…` (via `chris_brew_bundle_if_needed` in `scripts/lib.sh`). On a **fresh Mac** the check fails and everything installs; on **re-runs** satisfied bundles are skipped. `check --no-upgrade` means “present,” not “latest” — use `./bootstrap.sh update` or `brew upgrade` when you want versions to move. The Brewfile includes **`gh`** (GitHub CLI) and **`jira-cli`** (Jira CLI; command **`jira`** — do not install **`go-jira`** alongside it).

**Healthcheck / exit codes:** `./bootstrap.sh healthcheck` exits `1` on non-macOS, missing `brew`/`git`, bad CLT, failed `brew bundle check --no-upgrade` for `Brewfile` (and for `Brewfile.dev` when that file exists and `CHRIS_DEVSTRAP_SKIP_DEV_BUNDLE` is not set), failed GitHub SSH or `dockutil` checks, missing Tier A config (`.zprofile` brew block, SSH `origin`, `~/Developer`, `git init.defaultBranch`), or any failed check reported above. `brew doctor` is never fatal inside `healthcheck.sh`. Tier B (config drift: dark mode, hot corners, Dock layout, Spotlight hotkey, iTerm `Custom Directory`, Finder view/window) is **warn-only** (set `CHRIS_DEVSTRAP_HEALTHCHECK_SKIP_DRIFT=1` to silence) and Tier C (Brewfile.heavy, Xcode first-launch, iOS runtime, headshot) is informational. `./scripts/git-ssh-setup.sh` exits `0` when skipped (`CHRIS_DEVSTRAP_SKIP_SSH`), on fast path (matching `origin` + working `ssh -T`), or after interactive success; `1` when a TTY is required but missing, SSH verification fails, or keys are missing.

**Exit-code policy (3 tiers):**
1. **Fatal** — `brew`/`git`/CLT missing, bash syntax errors, `update.sh` failures, healthcheck Tier A → `exit 1`.
2. **Reported** — healthcheck Tier B drift warnings, individual `step_warn` messages → bootstrap still exits `0`; `healthcheck` prints a summary.
3. **Best-effort** — `heavy-installs.sh`, `headshot.sh`, `xcode-components.sh`, `macos-defaults.sh` per-key failures all **continue** and `exit 0` even when partially failed; the manual checklist queues follow-ups.

**SSH note:** `ssh -T git@github.com` often exits `1` with a success message ([docs](https://docs.github.com/en/authentication/connecting-to-github-with-ssh/testing-your-ssh-connection)); exit `255` or “Permission denied” is a real failure.

**CI:** [`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs `bash -n` and **ShellCheck** (pinned release) on `bootstrap.sh` and `scripts/*.sh` (Ubuntu; no macOS integration). Repo root [`.shellcheckrc`](.shellcheckrc) disables `SC1091` for dynamic `source` paths.

## What runs where

| Area | Script / files |
|------|----------------|
| Homebrew + CLT + `~/.zprofile` shellenv | [`install.sh`](install.sh) gates clone on CLT via [`scripts/clt.sh`](scripts/clt.sh); [`scripts/brew.sh`](scripts/brew.sh) runs CLT then Homebrew |
| Bundle | `Brewfile` (+ `Brewfile.dev` when present unless `CHRIS_DEVSTRAP_SKIP_DEV_BUNDLE=1`); for **`mas install`**, sign into the Mac App Store in the UI first (see **Mac App Store** above). |
| Zsh / Oh My Zsh + snippet | `scripts/zsh.sh`, `templates/zshrc.snippet`, `templates/zsh-aliases.snippet` (git/shell shortcuts appended if missing) |
| Global Git defaults | `scripts/git-config.sh` — always sets **`user.name`** to **Christopher Truman** (override: `CHRIS_DEVSTRAP_GIT_USER_NAME`); `init.defaultBranch=main`, `fetch.prune`, `pull.rebase=false`, `rerere.enabled`, `merge.conflictStyle=zdiff3`. When `delta` is on `PATH`, also sets `core.pager=delta`, `interactive.diffFilter='delta --color-only'`, `delta.navigate/side-by-side/line-numbers=true` (via `_git_set_if_missing`). Guided checklist opens an iTerm tab with `git config --global user.email ` ready to type. |
| GitHub CLI extensions (`gh dash`) | `scripts/gh-extensions.sh` — installs `dlvhdr/gh-dash` (TUI for PRs/issues/notifications). Override the set with `CHRIS_DEVSTRAP_GH_EXTENSIONS='owner/repo other/ext'` or skip entirely with `CHRIS_DEVSTRAP_SKIP_GH_EXTENSIONS=1`. |
| Finder (new window **Downloads**, column view, **date-modified** sort defaults + PlistBuddy best effort); Desktop & Dock window prefs; trackpad (**tap to click** + firm press / Force Click off); screenshots; **Control Center → Sound → Always Show** in menu bar (`ByHost` plist `Sound` = `18`); default browser (`defaultbrowser` when installed); hot corners; hide desktop widgets; global **`NSNavLastRootDirectory`** hint for some open/save sheets; **pre-accept notifications** for Notes, Stocks, Messages, Reminders, App Store, iTerm, Chrome (+ Helper), Find My, FaceTime, Maps, News, Passwords, Shortcuts, Weather, Zoom (Messages/Reminders sounds off) | `scripts/macos-defaults.sh` + `scripts/notifications-preaccept.sh` (UI sounds **off** unless `CHRIS_DEVSTRAP_SILENCE_UI_SOUNDS=0`) |
| Headshot → **`~/Downloads/headshot.png`** + macOS **local user** login picture (`dscl`, needs **`assets/headshot.png`** in the repo) | `scripts/headshot.sh` (see [`assets/README.md`](assets/README.md)) |
| Xcode first launch + iOS Simulator download | `scripts/xcode-components.sh` when Xcode was present at bootstrap start, or chained after successful `heavy-installs.sh` |
| `~/Developer` layout + sidebar | `scripts/finder-sidebar.sh` — downloads official **sbedit** `.pkg` when missing (`sudo installer`), then pins **Developer** + **Downloads** |
| Dock | `scripts/dock.sh` — `defaults` for autohide + **tilesize / largesize 128**; `dockutil --remove all`, `config/dock-remove.txt`, `config/dock-add.tsv`; **`~/Downloads`** fan (**others**, date modified); `killall Dock` |
| Raycast / Spotlight | `scripts/raycast-hotkey.sh` (disables `AppleSymbolicHotKeys:64` so ⌘Space is free for Raycast) |
| Raycast Script Commands | `scripts/raycast-script-commands.sh` — installs `templates/raycast-script-commands/*.sh` (currently **Dismiss Mac Notifications**) into `~/Library/Application Support/chris-devstrap/raycast-script-commands/`. One-time setup: Raycast → Settings → Extensions → Script Commands → "+" → User Folder → that path, then assign **⌘⌃Z**. Override with `CHRIS_DEVSTRAP_RAYCAST_SCRIPTS_DIR=…` or skip with `CHRIS_DEVSTRAP_SKIP_RAYCAST_SCRIPTS=1`. |
| Dismiss-Notifications shortcut (`⌘⌃Z`) | `scripts/zsh.sh` installs `~/bin/DismissMacNotifications/dismiss-notifications.{sh,jxa}` and surfaces a manual TODO at the end of bootstrap with both Raycast (path A, automated) and Shortcuts.app (path B, manual) recipes — see [`templates/dismiss-mac-notifications/KEYBOARD_SHORTCUT_SETUP.txt`](templates/dismiss-mac-notifications/KEYBOARD_SHORTCUT_SETUP.txt) |
| GitHub SSH + `origin` | `scripts/git-ssh-setup.sh` (always invoked at end of bootstrap except `--dry-run`; fast-path skips when `origin` + `ssh -T` already pass) — alias-aware via `~/.ssh/config` parsing; coexists with `scripts/github-account-add.sh` demoted blocks. |
| Add a GitHub SSH identity (primary or alias) | `scripts/github-account-add.sh` (interactive `/dev/tty`; not auto-invoked by `./bootstrap.sh` — run on demand). See **Multiple GitHub accounts** below. |
| Raycast / Cursor / iTerm + iTerm prefs | `scripts/iterm.sh` — sets iTerm2 **Custom Directory** = **Recycle**; opens apps when present; queues **Natural Text Editing** as guided checklist **step 1** |
| Heavy installs (Xcode via `mas`, Android Studio) | `scripts/heavy-installs.sh` — last step; checks `Brewfile.heavy` first (skips downloads when satisfied). Apple ID + App Store sign-in is in the guided checklist (queued after brew bundle). Enter to start downloads or `s` to skip; chains `xcode-components.sh` when Xcode installs or is already present. |


## Manual steps

Most setup is covered by the **guided checklist** at the end of `./bootstrap.sh` (iTerm, Raycast, Git identity, Apple ID + App Store, Xcode after install). Personal-only items live in [`templates/manual-overrides.example.md`](templates/manual-overrides.example.md).

- **Cursor** — Sign in with Google (when the app opens at end of bootstrap).
- **Primary GitHub account** — If you need a personal default `git@github.com` identity, run `./scripts/github-account-add.sh` (see **Multiple GitHub accounts** below). Bootstrap still configures the dedicated chris-devstrap repo key via `git-ssh-setup.sh`.

### Multiple GitHub accounts (primary + aliases)

`scripts/github-account-add.sh` (interactive — reads from `/dev/tty`) wires a new GitHub SSH identity into `~/.ssh/config`:

| Mode | Key path | `~/.ssh/config` host | Remote URL form |
| ---- | -------- | -------------------- | --------------- |
| Primary | `~/.ssh/id_ed25519` | `Host github.com` | `git@github.com:owner/repo.git` |
| Aliased | `~/.ssh/id_ed25519_<label>` | `Host github.com-<label>` | `git@github.com-<label>:owner/repo.git` |

When you promote a **new** account to primary and an existing managed `Host github.com` block already points at a different key, the script:

1. Renames the existing block to `Host github.com-jstart` (override with `GH_DEMOTE_ALIAS`).
2. Rewrites this repo's `origin` from `git@github.com:jstart/chris-devstrap.git` to `git@github.com-jstart:jstart/chris-devstrap.git`, so chris-devstrap keeps authenticating under its dedicated key.
3. Adds a new managed `Host github.com` block for the new primary key.

The bootstrap-time SSH step (`scripts/git-ssh-setup.sh`) is alias-aware: it parses `~/.ssh/config` for whichever `Host` line points at `~/.ssh/id_ed25519_chrisdevstrap`, defaults `CHRIS_DEVSTRAP_GIT_SSH_URL` to `git@<that-host>:jstart/chris-devstrap.git`, and skips adding a duplicate `Host github.com` block. Re-running `./bootstrap.sh` after demotion is safe.

```bash
# Primary account (new, default github.com identity):
./scripts/github-account-add.sh    # then answer Y at "Set this account as primary"

# Or non-interactive (CI / scripted):
GH_LABEL=personal GH_USERNAME=alice GH_EMAIL=alice@example.com GH_IS_PRIMARY=1 \
  ./scripts/github-account-add.sh

# Additional aliased account, e.g. work:
GH_LABEL=work GH_USERNAME=alice-corp GH_EMAIL=alice@corp.example GH_IS_PRIMARY=0 \
  ./scripts/github-account-add.sh
# → Use git@github.com-work:org/repo.git as the remote URL for those repos.
```

The script ssh-adds via `--apple-use-keychain` when available, copies the public key to the clipboard, opens `https://github.com/settings/keys`, waits for Enter, then runs `ssh -T git@<host-alias>` and looks for `Hi <username>` to confirm the right account picked it up.

### Microphone, camera, screen recording

macOS TCC cannot be granted from this repo. The guided checklist includes a **Privacy** step (after Git identity) that opens System Settings panes for:

- **Screen & System Audio Recording** — Google Chrome, zoom.us, Raycast
- **Microphone** / **Camera** — Google Chrome, zoom.us

Quit and reopen each app after toggling Screen Recording.

## Troubleshooting

- **Appearance still light** — Bootstrap now flips dark mode via **osascript** (System Events) first, then writes `defaults` as a fallback. The first run may prompt for **Automation** permission (System Settings → Privacy & Security → Automation → your terminal → System Events) — grant it once and future runs flip dark mode silently. If you cancel that prompt, the `defaults` write still applies but you may need to toggle **System Settings → Appearance → Dark** once (or log out/in).
- **`install.sh` one-liner — `xcode-select: No developer tools were found`** — Fresh Macs ship `/usr/bin/git` as an Apple stub that triggers the CLT installer when run. `install.sh` now checks `xcode-select -p` **before** cloning, fires `xcode-select --install` (GUI), and exits cleanly with the exact re-run command — wait for the CLT dialog to finish (~5–10 min), then re-run the curl one-liner.
- **`curl | bash` — no guided manual steps / “GitHub SSH requires an interactive terminal”** — Older builds treated stdin-as-pipe as non-interactive and `git-ssh-setup.sh` exited `1`, which aborted bootstrap before the checklist and heavy installs. Current builds detect `/dev/tty`, read SSH prompts from it, and soft-fail SSH so the rest of bootstrap continues. **Also:** `install.sh` checks out **`main`** unless you set `CHRIS_DEVSTRAP_REF=<branch>` — curling a PR branch’s `install.sh` without that still runs `main`. Finish SSH with `./scripts/git-ssh-setup.sh` if needed, then re-run `./bootstrap.sh` for heavy installs / the guided checklist.
- **`sbedit` / sidebar “Operation not permitted”** — macOS TCC blocked write to `FavoriteItems.sfl4`. Grant **Full Disk Access** to your terminal (System Settings → Privacy & Security), then `./scripts/finder-sidebar.sh` — or pin folders manually in Finder → Settings → Sidebar.
- **Desktop & Dock → Windows** — Bootstrap sets `AppleWindowTabbingMode`, `NSCloseAlwaysConfirmsChanges`, and `NSQuitAlwaysKeepsWindows` on `NSGlobalDomain`, plus `StandardHideWidgets` on `com.apple.WindowManager` (hide desktop widgets). **System Settings** may show stale labels until that pane is reopened; per-app behavior can require **quitting the app** (some cache). Logout is rarely needed; bootstrap already `killall`s Finder, SystemUIServer, and Dock.
- **Trackpad → tap to click** — `macos-defaults.sh` sets built-in + Bluetooth `Clicking` and `com.apple.mouse.tapBehavior` (`1` = tap to click). If **System Settings → Trackpad** still shows it off, close that pane and reopen, or log out/in (same pattern as other `defaults` UI lag).
- **File dialogs / column sort** — Bootstrap sets **Finder** new windows to **`~/Downloads`**, prefers **column view**, and writes **date-modified** sort/arrange defaults plus best-effort **PlistBuddy** patches. For **open/save sheets**: writes `NSGlobalDomain NSNavLastRootDirectory=~/Downloads` **and** scrubs per-app `NSNavLastRootDirectory` overrides via `defaults find` so apps fall back to the global hint on next launch. Opt out of the scrub with **`CHRIS_DEVSTRAP_KEEP_APP_NAV_DIRS=1`** (e.g. Photoshop pinned to `~/Pictures`). Apps will still write their own value the next time the user picks a different folder — re-run `./scripts/macos-defaults.sh` (or `update --refresh`) to reset. Stale **`.DS_Store`** files can keep old sort—remove them or **Finder → View → Show View Options → Use as Defaults** on a representative folder.
- **Headshot / user picture** — Add your photo as **`assets/headshot.png`** in the repo, then re-run bootstrap. Bootstrap **skips the `sudo dscl` Picture update when the local user already has an avatar set** (checks `dscl . -read Picture` / `JPEGPhoto`); set **`CHRIS_DEVSTRAP_FORCE_HEADSHOT=1`** to overwrite. **`dscl`** may require **sudo** and can fail on some builds; use **System Settings → Users & Groups** and drag **`~/Downloads/headshot.png`** onto your avatar. **Apple ID, Chrome, Messages,** etc. do not share one API—use **`assets/README.md`** and the end-of-bootstrap **Manual follow-ups** lines for those.
- **Heavy installs (Xcode / Android Studio) did not run** — Sign in via the checklist item queued after brew bundle, then press Enter at step 10 (or type `s` to skip). Re-run: `brew bundle install --no-upgrade --file=Brewfile.heavy`. Xcode first-launch runs automatically after a successful heavy install when Xcode appears.
- **`brew` not in new terminals** — Ensure `~/.zprofile` contains the brew shellenv block from `scripts/brew.sh`.
- **`brew bundle`: `Too many open files`** — Fresh macOS shells often start with `ulimit -n` at **256**. Bootstrap raises the soft limit to **10240** (override with `CHRIS_DEVSTRAP_OPEN_FILES_LIMIT`) before brew bundle/upgrade. Re-run the installer, or in the current shell: `ulimit -n 10240` then `brew bundle install --no-upgrade --file=Brewfile`.
- **`~/.zshrc`: `command not found: history-substring-search` / parse error near `)`** — Usually a broken multiline `plugins=(` … `)` block. A common leftover is `plugins=(git)` followed by bare `git` and `)` (running `git` with no args prints the usage banner). **`scripts/zsh.sh`** merges multiline `plugins` and **sanitizes** orphan lines. Re-run **`bash scripts/zsh.sh`** or fix by hand: one valid `plugins=(…)` line and no stray plugin lines.
- **Opening a terminal prints `git` usage** — Follow-on from a broken **`~/.zshrc`**; fix **`plugins=`** then `exec zsh`.
- **`oh-my-zsh.sh`: no such file or directory** — Run **`bash scripts/zsh.sh`** to install Oh My Zsh. **`templates/zshrc.snippet`** only sources OMZ when **`oh-my-zsh.sh`** exists.
- **Oh My Zsh installer: “The `$ZSH` folder already exists”** — Incomplete **`~/.oh-my-zsh`** or exported **`ZSH`**; **`scripts/zsh.sh`** removes incomplete trees and runs the installer with **`ZSH` unset** in a subshell.
- **`gitclean` / parse error near `()`** — Do not define both **`alias gitclean=...`** and **`gitclean()`**; the snippet runs **`unalias gitclean`** before the function.
- **`sbedit` / `mysides` on PATH** — `scripts/finder-sidebar.sh` **auto-downloads and installs the signed sbedit `.pkg`** via `sudo installer` when `sbedit` is missing from `PATH`; set `CHRIS_DEVSTRAP_SKIP_SBEDIT_INSTALL=1` to opt out (the script then falls back to `mysides` when present, or prints a manual checklist item). Override the pkg URL with `CHRIS_DEVSTRAP_SBEDIT_PKG_URL`. Sidebar mutations are skipped when `~/Developer` and `~/Downloads` are already pinned (parsed from `sbedit --list` / `mysides list`).
- **`mas install` fails** — Complete App Store sign-in in the UI first (see **Mac App Store** at the top); mas 7+ has no `mas account`.
- **Dockutil “Remove failed”** — Harmless for items that were never in the Dock.
- **Dock icons still look small** — Many Dock tiles cause macOS to shrink them to fit the strip.

## License

Use and modify freely for your own machines.

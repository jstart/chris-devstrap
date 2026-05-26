# chris-devstrap — Homebrew Bundle (brew bundle is built into Homebrew; no tap required)
# Docs: https://docs.brew.sh/Manpage#bundle-subcommand

brew "bat"                 # syntax-highlighted cat; fzf/delta preview backend
brew "btop"                # modern top with mouse + themes
brew "defaultbrowser"
brew "dockutil"
brew "eza"                 # modern ls with icons + git status
brew "fastlane"            # iOS/Android release automation
brew "fd"                  # modern find; pairs with fzf
brew "fzf"
brew "gh"
brew "git-delta"           # syntax-aware pager for git diff (wired in scripts/git-config.sh)
brew "jira-cli"
brew "jq"                  # JSON wrangling
brew "mas"
brew "ncdu"                # interactive disk-usage explorer
brew "periphery"           # find unused Swift code
brew "ripgrep"             # rg — fast grep, used by Cursor/agents
brew "swiftformat"
brew "swiftlint"
brew "watch"               # repeat a command (not shipped on macOS)
brew "xcbeautify"          # pretty xcodebuild output
brew "xcodes"              # manage multiple Xcode versions
brew "yq"                  # YAML wrangling
brew "zoxide"              # smart cd (frecency)
brew "zsh-autosuggestions"

cask "cursor"
# Skip Homebrew cask when the app is already present (App Store/manual install).
# brew bundle check ignores these lines when the path exists, so healthcheck matches reality.
cask "google-chrome" unless File.exist?("/Applications/Google Chrome.app")
cask "hiddenbar"           # collapse menu bar icons
cask "iterm2"
cask "monitorcontrol"
cask "proxyman"            # HTTP/HTTPS debugging for iOS simulator + device
cask "raycast"
cask "slack" unless File.exist?("/Applications/Slack.app")
# Tuist ships as a signed cask (the tuist/tuist formula tap conflicts with the cask binary).
cask "tuist"

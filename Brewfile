# chris-devstrap — Homebrew Bundle (brew bundle is built into Homebrew; no tap required)
# Docs: https://docs.brew.sh/Manpage#bundle-subcommand

brew "defaultbrowser"
brew "dockutil"
brew "fzf"
brew "gh"
brew "jira-cli"
brew "mas"
brew "zsh-autosuggestions"

cask "cursor"
# Skip Homebrew cask when the app is already present (App Store/manual install).
# brew bundle check ignores these lines when the path exists, so healthcheck matches reality.
cask "google-chrome" unless File.exist?("/Applications/Google Chrome.app")
cask "iterm2"
cask "monitorcontrol"
cask "raycast"
cask "slack" unless File.exist?("/Applications/Slack.app")

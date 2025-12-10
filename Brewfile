# Brewfile - Homebrew Bundle
# Install: brew bundle install
# Dump current: brew bundle dump --force
# Cleanup unlisted: brew bundle cleanup --force
# Check status: brew bundle check

# ============================================================================
# Taps
# ============================================================================

tap "goreleaser/tap"
tap "khanakia/vercelgate"
tap "khanhas/tap"
tap "lotyp/formulae"
tap "homebrew/cask-fonts"
tap "artginzburg/tap"

# ============================================================================
# CLI Utilities
# ============================================================================

# Search tools
brew "ack"                          # Code search tool
brew "ag"                           # The Silver Searcher
brew "fd"                           # Fast find alternative
brew "fzf"                          # Fuzzy finder
brew "ripgrep"                      # Fast grep alternative
brew "the_silver_searcher"          # ag

# File utilities
brew "bat"                          # Cat with syntax highlighting
brew "eza"                          # Modern ls replacement
brew "tree"                         # Directory tree view
brew "unar"                         # Universal archive extractor
brew "croc"                         # Secure file transfer

# Text processing
brew "gnu-sed"                      # GNU sed
brew "gawk"                         # GNU awk
brew "grep"                         # GNU grep
brew "jq"                           # JSON processor
brew "yq"                           # YAML processor

# System utilities
brew "coreutils"                    # GNU core utilities
brew "findutils"                    # GNU find, xargs, etc.
brew "readline"                     # GNU readline
brew "stow"                         # Symlink farm manager
brew "mackup"                       # App settings backup
brew "mas"                          # Mac App Store CLI
brew "topgrade"                     # System upgrade tool
brew "thefuck"                      # Command correction
brew "zoxide"                       # Smarter cd command
brew "starship"                     # Cross-shell prompt
brew "psgrep"                       # Process grep

# Network utilities
brew "wget"                         # HTTP client
brew "httpie"                       # Modern HTTP client
brew "ssh-copy-id"                  # SSH key installer

# Development tools
brew "git-delta"                    # Better git diff
brew "gh"                           # GitHub CLI
brew "shfmt"                        # Shell formatter
brew "shellcheck"                   # Shell script linter
brew "bats-core"                    # Bash testing framework

# Programming languages
brew "python"                       # Python 3
brew "go"                           # Go language
brew "cmake"                        # Build system

# Media tools
brew "ffmpeg"                       # Media converter
brew "imagemagick"                  # Image manipulation
brew "optipng"                      # PNG optimizer
brew "webp"                         # WebP tools
brew "yt-dlp"                       # Video downloader
brew "svgo"                         # SVG optimizer (via npm usually)

# Misc utilities
brew "dos2unix"                     # Line ending converter
brew "uni"                          # Unicode tool
brew "grip"                         # GitHub markdown preview
brew "tldr"                         # Simplified man pages

# Tap-specific
brew "lotyp/formulae/dockutil"      # Dock management
brew "artginzburg/tap/sudo-touchid" # TouchID for sudo

# ============================================================================
# Desktop Applications (Casks)
# ============================================================================

# Browsers
cask "brave-browser"
cask "firefox"
cask "google-chrome"

# Development
cask "visual-studio-code"
cask "gitkraken"
cask "sourcetree"
cask "arduino"
cask "arduino-ide"
cask "ngrok"
cask "goreleaser"
cask "kaleidoscope"

# Design
cask "adobe-creative-cloud"
cask "figma"
cask "autodesk-fusion"
cask "prusaslicer"
cask "superslicer"

# Communication
cask "discord"
cask "slack"
cask "telegram"
cask "zoom"
cask "notion"

# Utilities
cask "raycast"                      # Spotlight replacement
cask "karabiner-elements"           # Keyboard customization
cask "keka"                         # Archive utility
cask "keycastr"                     # Keystroke visualizer
cask "shottr"                       # Screenshot tool
cask "topnotch"                     # Notch hider
cask "flux-app"                     # Blue light filter
cask "setapp"                       # App subscription

# Media
cask "spotify"
cask "vlc"
cask "iina"                         # Modern video player

# Remote & VPN
cask "anydesk"
cask "teamviewer"
cask "protonvpn"
cask "tunnelblick"
cask "tailscale"

# Cloud & Sync
cask "google-drive"
cask "transmission"

# iOS
cask "altserver"

# QuickLook plugins
cask "qlmarkdown"
cask "qlstephen"
cask "qlvideo"
cask "quicklook-json"
cask "quicklookase"
cask "syntax-highlight"
cask "suspicious-package"
cask "apparency"

# Terminal
cask "warp"

# Fonts
cask "font-awesome-terminal-fonts"
cask "font-fira-code"
cask "font-fira-mono"
cask "font-fira-code-nerd-font"
cask "font-fira-mono-nerd-font"
cask "font-fontawesome"
cask "font-geist-mono-nerd-font"
cask "font-hack"
cask "font-hack-nerd-font"
cask "font-inter"
cask "font-menlo-for-powerline"
cask "font-meslo-for-powerline"
cask "font-meslo-lg"
cask "font-meslo-lg-nerd-font"
cask "font-roboto-mono-nerd-font"

# ============================================================================
# Mac App Store
# ============================================================================

mas "Emby", id: 992180193
mas "LastPass", id: 926036361
mas "LocalSend", id: 1661733229
mas "Magnet", id: 441258766
mas "Messenger", id: 1480068668
mas "SponsorBlock", id: 1573461917
mas "Tailscale", id: 1475387142
mas "Windows App", id: 1295203466

# ============================================================================
# VS Code Extensions (managed separately via code.list)
# ============================================================================
# Note: VS Code extensions are managed via packages/code.list
# Install with: cat packages/code.list | xargs -L 1 code --install-extension

# ============================================================================
# NPM Global Packages (managed separately via npm.list)
# ============================================================================
# Note: NPM packages are managed via packages/npm.list
# Install with: cat packages/npm.list | xargs npm install -g
#
# These cannot be in Brewfile because they require Node.js/npm to be installed
# and configured via fnm first.

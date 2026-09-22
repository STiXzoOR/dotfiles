# Brewfile - Homebrew Bundle
# Install: brew bundle install
# Dump current: brew bundle dump --describe --force
# Cleanup unlisted: brew bundle cleanup --force
# Check status: brew bundle check
#
# Apple silicon only: HOMEBREW_PREFIX is /opt/homebrew.
#
# Homebrew 7 refuses to load a cask from an untrusted tap, which hard-fails
# the whole `brew bundle install` run. `dotfiles install --packages` now runs
# `brew trust --tap` over every tap declared below before bundling, so a
# third-party cask must be written fully qualified and its tap declared here.
# Anything installed from a tap NOT declared below is installed by hand on
# purpose, so that bootstrapping this repo never grants trust to a tap the
# manifest does not name.

# ============================================================================
# Taps
# ============================================================================

tap "datadog-labs/pack"             # pup (Datadog CLI)
tap "goreleaser/tap"                # goreleaser
tap "lotyp/formulae"                # dockutil
tap "timescam/tap"                  # pay-respects
tap "artginzburg/tap"               # sudo-touchid

# ============================================================================
# CLI Utilities
# ============================================================================

# Search tools
brew "fd"                           # Fast find alternative
brew "fzf"                          # Fuzzy finder
brew "ripgrep"                      # Fast grep alternative

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
brew "gettext"                      # GNU i18n tools (envsubst)
brew "jq"                           # JSON processor
brew "yq"                           # YAML processor

# System utilities
brew "coreutils"                    # GNU core utilities
brew "findutils"                    # GNU find, xargs, etc.
brew "stow"                         # Symlink farm manager
brew "mas"                          # Mac App Store CLI
brew "topgrade"                     # System upgrade tool
brew "zoxide"                       # Smarter cd command
brew "atuin"                        # Searchable shell history
brew "starship"                     # Shell prompt (rich terminals; Warp draws its own)
brew "psgrep"                       # Process grep
brew "rtk"                          # Token-optimising command proxy
brew "timescam/tap/pay-respects"    # Command correction (replaces thefuck)

# Network utilities
brew "wget"                         # HTTP client
brew "httpie"                       # Modern HTTP client
brew "mosh"                         # Roaming-tolerant SSH
brew "tailscale"                    # Tailnet CLI (GUI app installed separately)

# Security
brew "age"                          # Modern file encryption
brew "gitleaks"                     # Secret scanner for git history

# Development tools
brew "git-delta"                    # Better git diff
brew "difftastic"                   # Structural (syntax-aware) diff
brew "lazygit"                      # Terminal UI for git
brew "gh"                           # GitHub CLI
brew "shfmt"                        # Shell formatter
brew "shellcheck"                   # Shell script linter
brew "bats-core"                    # Bash testing framework
brew "ast-grep"                     # Structural code search
brew "circleci"                     # CircleCI CLI
brew "awscli"                       # AWS CLI
brew "datadog-labs/pack/pup"        # Datadog CLI
brew "tmux"                         # Terminal multiplexer
brew "neovim"                       # Editor (config in config/nvim)

# Apple platform tools
brew "swiftlint"                    # Swift linter
brew "xcodegen"                     # Xcode project generator
brew "asc"                          # App Store Connect CLI

# Programming languages and runtimes
brew "mise"                         # Runtime/tool version manager
brew "bun"                          # JS runtime/package manager (not the npm shim)
brew "python"                       # Python 3
brew "go"                           # Go language
brew "cmake"                        # Build system
brew "ruby"                         # Ruby
brew "pipx"                         # Isolated Python app installs
brew "postgresql@17"                # Postgres server

# Media tools
brew "ffmpeg"                       # Media converter
brew "imagemagick"                  # Image manipulation
brew "optipng"                      # PNG optimizer
brew "webp"                         # WebP tools
brew "yt-dlp"                       # Video downloader
brew "pngquant"                     # PNG compressor
brew "ghostscript"                  # PostScript/PDF interpreter
brew "librsvg"                      # SVG rendering
brew "poppler"                      # PDF utilities
brew "qpdf"                         # PDF transformation

# Misc utilities
brew "dos2unix"                     # Line ending converter
brew "uni"                          # Unicode tool
brew "grip"                         # GitHub markdown preview
brew "pandoc"                       # Document converter
brew "cliclick"                     # CLI mouse/keyboard control
brew "libimobiledevice"             # iOS device communication
brew "lotyp/formulae/dockutil"      # Dock management
brew "artginzburg/tap/sudo-touchid" # TouchID for sudo (writes /etc/pam.d/sudo_local once)

# ============================================================================
# Desktop Applications (Casks)
# ============================================================================

# Browsers
cask "brave-browser"
cask "firefox"
cask "google-chrome"

# Development
cask "visual-studio-code"
cask "webstorm"
cask "gitkraken"
cask "sourcetree"
cask "arduino-ide"
cask "ngrok"
cask "kaleidoscope"
cask "goreleaser/tap/goreleaser"     # fully qualified: needs its tap trusted
cask "codexbar"                     # Codex menubar client

# Design
cask "adobe-creative-cloud"
cask "figma"
cask "autodesk-fusion"
cask "prusaslicer"

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
cask "obsidian"                     # Knowledge base / vault
cask "setapp"                       # App subscription
cask "balenaetcher"                 # Flash OS images to SD/USB
cask "basictex"                     # Minimal TeX distribution

# Media
cask "spotify"
cask "vlc"
cask "iina"                         # Modern video player

# Remote & VPN
cask "anydesk"
cask "protonvpn"
cask "tunnelblick"

# Cloud & Sync
cask "google-drive"
cask "transmission"

# iOS
cask "altserver"

# QuickLook plugins
cask "qlmarkdown"
cask "quicklook-video"
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
cask "font-ibm-plex-mono"
cask "font-inter"
cask "font-menlo-for-powerline"
cask "font-meslo-for-powerline"
cask "font-meslo-lg"
cask "font-meslo-lg-nerd-font"
cask "font-roboto-mono-nerd-font"

# ============================================================================
# Mac App Store
# ============================================================================
#
# `mas` cannot sign in to the App Store on modern macOS and `mas install`
# only works for apps already in the purchase history: sign in by hand first.

mas "Emby", id: 992180193
mas "LastPass", id: 926036361
mas "LocalSend", id: 1661733229
mas "Magnet", id: 441258766
mas "Messenger", id: 1480068668
mas "SponsorBlock", id: 1573461917
mas "Windows App", id: 1295203466

# ============================================================================
# VS Code Extensions (managed separately via code.list)
# ============================================================================
# Note: VS Code extensions are managed via packages/code.list
# Install with: ./bin/dotfiles install --packages
# By hand -- the list carries a comment header and xargs does not strip it:
#   grep -v '^#' packages/code.list | xargs -L 1 code --install-extension

# ============================================================================
# Node CLIs (managed by mise, not Homebrew)
# ============================================================================
# Declared in config/mise/config.toml under [tools] as "npm:<package>", pinned
# in config/mise/mise.lock. Install with: ./bin/dotfiles install --node
#
# These cannot be in the Brewfile because they require a Node.js toolchain
# first. They are not installed with `npm i -g` either: mise's npm backend
# runs with --ignore-scripts, so a package's lifecycle scripts do not execute
# as you unless it declares allow_builds for itself.

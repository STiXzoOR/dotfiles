# Sourced by husky's git hooks, which run with a minimal non-interactive
# PATH. Re-establish the Homebrew environment and the Node toolchain.
#
# POSIX sh: husky runs its hooks with sh, not bash.

if ! command -v brew >/dev/null 2>&1; then
  PATH="${HOMEBREW_PREFIX:-/opt/homebrew}/bin:$PATH"
  export PATH
fi
command -v brew >/dev/null 2>&1 && eval "$(brew shellenv)"

# Node: the mise shims are a fixed path that needs no eval and no subprocess,
# and each shim resolves the version this repository asks for at exec time.
# `mise activate --shims` is the fallback for a machine where mise is
# installed but `mise install` has not built the shims yet.
if [ -d "$HOME/.local/share/mise/shims" ]; then
  PATH="$HOME/.local/share/mise/shims:$PATH"
  export PATH
elif command -v mise >/dev/null 2>&1; then
  eval "$(mise activate bash --shims)"
fi

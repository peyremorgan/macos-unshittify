#!/bin/zsh
#
# Ensure git is installed, installing it with Homebrew if it is missing.
#
# Idempotent: if a working git is already present, this does nothing.
#
# On macOS, /usr/bin/git always exists, but until the Xcode Command Line Tools
# (or Xcode) are installed it is only a shim that pops up a GUI install prompt.
# So `command -v git` is not enough, and the shim must never be invoked to find
# out: instead, check that the active developer directory has a real git.
#
# Requires Homebrew (see 001_homebrew.sh) when git has to be installed.

set -euo pipefail

source "${0:A:h}/../lib/io.sh"

# brew may not be on PATH yet (fresh install, non-login shell), so also check
# the default prefixes for Apple Silicon and Intel.
find_brew() {
  local candidate
  for candidate in "$(command -v brew || true)" /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

# Print the path of a working git, without ever running the /usr/bin/git shim.
find_git() {
  local candidate dev_dir
  # Every executable named git on PATH ((N*) = executables only, no error if
  # none match), then the Homebrew prefixes in case they are not on PATH.
  for candidate in $^path/git(N*) /opt/homebrew/bin/git /usr/local/bin/git; do
    [[ -x "$candidate" ]] || continue
    if [[ "$candidate" == /usr/bin/git ]]; then
      # `xcode-select -p` only reads the configured path; it never prompts.
      dev_dir="$(xcode-select -p 2>/dev/null || true)"
      [[ -n "$dev_dir" && -x "$dev_dir/usr/bin/git" ]] || continue
    fi
    echo "$candidate"
    return 0
  done
  return 1
}

main() {
  local git brew

  if git="$(find_git)"; then
    log "git found at ${git} ($("$git" --version))"
    return 0
  fi

  brew="$(find_brew)" || die "git is missing and Homebrew is not installed. Run 001_homebrew.sh first."
  log "git not found, installing it with Homebrew"
  "$brew" install --quiet git

  git="$(find_git)" || die "Homebrew finished but git was not found."
  log "Installed $("$git" --version) at ${git}"
}

main "$@"

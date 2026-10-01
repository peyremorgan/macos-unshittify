#!/bin/zsh
#
# Ensure Homebrew is installed and up to date.
#
# Idempotent: if brew is already present, this only runs `brew update`, which
# is a no-op when Homebrew is already current.
#
# The official installer is never piped straight from curl into a shell.
# Instead, it is pinned to a single commit of github.com/Homebrew/install,
# downloaded from two independent CDNs (GitHub and jsDelivr), and only run if
# both copies are byte-identical.
#
# Set NONINTERACTIVE=1 to skip the installer's prompts (sudo must then already
# be usable without a password).

set -euo pipefail

source "${0:A:h}/../lib/io.sh"

readonly INSTALL_REPO="Homebrew/install"
readonly SHELLENV_FILE="${HOME}/.zprofile"

workdir=""
cleanup() { if [[ -n "$workdir" ]]; then rm -rf "$workdir"; fi; }
trap cleanup EXIT

fetch() {
  curl --fail --silent --show-error --location \
       --proto '=https' --tlsv1.2 --retry 3 \
       "$@"
}

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

install_homebrew() {
  [[ $EUID -ne 0 ]] || die "Do not run as root: Homebrew refuses to install as root."

  workdir="$(mktemp -d)"
  local primary="$workdir/install.github.sh"
  local mirror="$workdir/install.jsdelivr.sh"
  local sha

  # Pin both downloads to the same commit so CDN caching can't cause a
  # spurious mismatch.
  log "Resolving latest commit of ${INSTALL_REPO}"
  sha="$(fetch -H 'Accept: application/vnd.github.sha' \
    "https://api.github.com/repos/${INSTALL_REPO}/commits/HEAD")"
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || die "Unexpected commit SHA from GitHub API: ${sha}"

  log "Downloading installer at ${sha} from GitHub"
  fetch -o "$primary" "https://raw.githubusercontent.com/${INSTALL_REPO}/${sha}/install.sh"
  log "Downloading installer at ${sha} from jsDelivr"
  fetch -o "$mirror" "https://cdn.jsdelivr.net/gh/${INSTALL_REPO}@${sha}/install.sh"

  [[ -s "$primary" ]] || die "Installer downloaded from GitHub is empty."
  if ! cmp -s "$primary" "$mirror"; then
    diff -u "$primary" "$mirror" >&2 || true
    die "Installer from GitHub and jsDelivr differ. Refusing to run it."
  fi
  [[ "$(head -n 1 "$primary")" == "#!/bin/bash" ]] || die "Installer does not look like a bash script."

  log "Both copies match (sha256 $(shasum -a 256 "$primary" | cut -d ' ' -f 1))"
  log "Running Homebrew installer"
  # The installer itself is a bash script and refuses to run under any other
  # shell; /bin/bash ships with macOS.
  /bin/bash "$primary"
}

# Add `brew shellenv` to the login shell profile, once.
ensure_shellenv() {
  local brew="$1"
  local line="eval \"\$(${brew} shellenv)\""

  if ! grep -qsF "$line" "$SHELLENV_FILE"; then
    log "Adding Homebrew to PATH in ${SHELLENV_FILE}"
    printf '\n%s\n' "$line" >> "$SHELLENV_FILE"
  fi
  eval "$("$brew" shellenv)"
}

main() {
  local brew

  if brew="$(find_brew)"; then
    log "Homebrew found at ${brew}, updating"
    "$brew" update --quiet
  else
    install_homebrew
    brew="$(find_brew)" || die "Homebrew installer finished but brew was not found."
  fi

  ensure_shellenv "$brew"
}

main "$@"

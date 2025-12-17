#!/usr/bin/env zsh
# Interactive, BSD-clean, NO-SUDO installer for SkyWater Sky130 PDK
#
# Firewall HTTPS-only fix:
# - Patches any .gitmodules under the repo to replace git+ssh/ssh/git@/git:// with HTTPS
# - Runs submodule sync/update twice (to catch nested submodules)

set -eu

say() { print -r -- "$*"; }
err() { print -r -- "ERROR: $*" >&2; }
die() { err "$@"; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

ask() {
  local prompt="$1" def="${2:-}" ans=""
  if [[ -n "$def" ]]; then
    printf "%s [%s]: " "$prompt" "$def" > /dev/tty
  else
    printf "%s: " "$prompt" > /dev/tty
  fi
  IFS= read -r ans < /dev/tty || true
  [[ -z "$ans" ]] && ans="$def"
  print -r -- "$ans"
}

ask_yn() {
  local prompt="$1" def="${2:-y}" ans=""
  while true; do
    [[ "$def" == "y" ]] && printf "%s [Y/n]: " "$prompt" > /dev/tty || printf "%s [y/N]: " "$prompt" > /dev/tty
    IFS= read -r ans < /dev/tty || true
    ans="${ans:l}"
    [[ -z "$ans" ]] && ans="$def"
    case "$ans" in
      y|yes) return 0 ;;
      n|no)  return 1 ;;
      *) say "Please answer y or n." ;;
    esac
  done
}

detect_os() {
  case "$(uname -s 2>/dev/null || true)" in
    Darwin) print "macos" ;;
    Linux)  print "linux" ;;
    *)      print "other" ;;
  esac
}

detect_pkg_mgr() {
  if have port; then print "macports"
  elif have brew; then print "homebrew"
  elif have apt-get; then print "apt"
  elif have dnf; then print "dnf"
  elif have yum; then print "yum"
  else print "none"
  fi
}

check_deps() {
  local missing=()
  for t in git make python3 tcsh find sed; do
    have "$t" || missing+=("$t")
  done
  if (( ${#missing[@]} > 0 )); then
    say "Missing tools:"
    for m in "${missing[@]}"; do say "  - $m"; done
    return 1
  fi
  return 0
}

print_dep_instructions() {
  local pm="$1"
  say ""
  say "Required tools (user-level): git make python3 tcsh"
  say "No sudo will be used."
  say ""
  case "$pm" in
    macports) say "MacPorts:  port install git python311 tcsh" ;;
    homebrew) say "Homebrew:  brew install git python tcsh" ;;
    *)        say "Ensure tools are available in PATH." ;;
  esac
  say ""
}

# Patch ONE .gitmodules file, robust to whitespace around '='
patch_gitmodules_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0

  # Only do work if it contains any blocked schemes
  if ! /usr/bin/grep -qE 'git\+ssh://|ssh://git@github\.com/|git@github\.com:|git://' "$f"; then
    return 0
  fi

  say "Patching $f (forcing HTTPS URLs)..."

  # BSD sed: -i ''
  # We replace *only the URL value* portion in common forms, tolerant of whitespace.
  /usr/bin/sed -i '' \
    -e 's#[Uu][Rr][Ll][[:space:]]*=[[:space:]]*git\+ssh://github\.com/#[Uu][Rr][Ll] = https://github.com/#g' \
    -e 's#[Uu][Rr][Ll][[:space:]]*=[[:space:]]*git\+ssh://git@github\.com/#[Uu][Rr][Ll] = https://github.com/#g' \
    -e 's#[Uu][Rr][Ll][[:space:]]*=[[:space:]]*ssh://git@github\.com/#[Uu][Rr][Ll] = https://github.com/#g' \
    -e 's#[Uu][Rr][Ll][[:space:]]*=[[:space:]]*git@github\.com:#[Uu][Rr][Ll] = https://github.com/#g' \
    -e 's#[Uu][Rr][Ll][[:space:]]*=[[:space:]]*git://#[Uu][Rr][Ll] = https://#g' \
    "$f"
}

# Patch all .gitmodules under repo
patch_all_gitmodules() {
  local repo="$1"
  local f
  say "Scanning for .gitmodules under $repo ..."
  # Use find (BSD) and patch each file found
  while IFS= read -r f; do
    patch_gitmodules_file "$f"
  done < <(/usr/bin/find "$repo" -name .gitmodules -type f 2>/dev/null)
}

prepare_https_submodules() {
  local repo="$1"

  # Global rewrites help for clones, but we also patch .gitmodules explicitly.
  git config --global url."https://github.com/".insteadOf "git+ssh://github.com/"
  git config --global url."https://github.com/".insteadOf "git+ssh://git@github.com/"
  git config --global url."https://github.com/".insteadOf "git@github.com:"
  git config --global url."https://github.com/".insteadOf "ssh://git@github.com/"
  git config --global url."https://".insteadOf "git://"

  (
    cd "$repo"
    git config --local url."https://github.com/".insteadOf "git+ssh://github.com/"
    git config --local url."https://github.com/".insteadOf "git+ssh://git@github.com/"
    git config --local url."https://github.com/".insteadOf "git@github.com:"
    git config --local url."https://github.com/".insteadOf "ssh://git@github.com/"
    git config --local url."https://".insteadOf "git://"
  )

  patch_all_gitmodules "$repo"

  ( cd "$repo" && git submodule sync --recursive || true )
}

# ---------------- main ----------------
say "SkyWater Open PDK installer (Sky130)"
say "Root-free / sudo-free interactive mode"
say ""

OS="$(detect_os)"
PM="$(detect_pkg_mgr)"
say "Detected OS : $OS"
say "Detected PM : $PM"
say ""

if ! check_deps; then
  print_dep_instructions "$PM"
  die "Dependencies missing."
fi

say "All required tools found."
say ""
say "Current working directory:"
say "  $(/bin/pwd)"
say ""

PDK_ROOT_DEFAULT="${HOME}/pdks"
PDK_ROOT="$(ask "Where should PDK_ROOT be installed?" "$PDK_ROOT_DEFAULT")"
PDK_ROOT="${PDK_ROOT/#\~/${HOME}}"
[[ -z "$PDK_ROOT" ]] && die "PDK_ROOT cannot be empty."
export PDK_ROOT

if [[ ! -d "$PDK_ROOT" ]]; then
  ask_yn "Create directory $PDK_ROOT?" "y" || die "Cannot proceed."
  mkdir -p "$PDK_ROOT"
fi

REPO_URL="$(ask "SkyWater PDK git URL" "https://github.com/google/skywater-pdk.git")"

WORKDIR_DEFAULT="${PDK_ROOT}/src/skywater-pdk"
WORKDIR="$(ask "Where should the repo be cloned/built?" "$WORKDIR_DEFAULT")"
WORKDIR="${WORKDIR/#\~/${HOME}}"

TARGET="$(ask "Build target" "sky130")"

say ""
if [[ -d "$WORKDIR/.git" ]]; then
  say "Repository already exists:"
  say "  $WORKDIR"
  ask_yn "Update it (git pull)?" "y" && ( cd "$WORKDIR" && git pull --rebase )
else
  say "Cloning repository..."
  mkdir -p "$(dirname "$WORKDIR")"
  git clone "$REPO_URL" "$WORKDIR"
fi

export SKYWATER_PDK_REPO="$WORKDIR"

# Pass 0: patch any existing .gitmodules before touching submodules
prepare_https_submodules "$WORKDIR"

say "Updating submodules (pass 1)..."
( cd "$WORKDIR" && git submodule update --init --recursive )

# Pass 2: now nested .gitmodules exist—patch again and update again
prepare_https_submodules "$WORKDIR"

say "Updating submodules (pass 2)..."
( cd "$WORKDIR" && git submodule update --init --recursive )

say ""
say "Build summary:"
say "  PDK_ROOT          = $PDK_ROOT"
say "  SKYWATER_PDK_REPO = $SKYWATER_PDK_REPO"
say "  TARGET            = $TARGET"
say ""

ask_yn "Proceed with build?" "y" || die "Aborted."

say ""
say "Building SkyWater PDK ..."
( cd "$WORKDIR" && make "$TARGET" PDK_ROOT="$PDK_ROOT" )

say ""
say "Installation complete."
say ""
say "PDK installed at:"
say "  $PDK_ROOT"
say ""
say "ngspice models:"
say "  $PDK_ROOT/sky130A/libs.tech/ngspice/"
say ""
say "This session exports:"
say "  PDK_ROOT=\"$PDK_ROOT\""
say "  SKYWATER_PDK_REPO=\"$SKYWATER_PDK_REPO\""
say ""
say "To make PDK_ROOT permanent, add to ~/.zshrc:"
say "  export PDK_ROOT=\"$PDK_ROOT\""
say "Optional:"
say "  export SKYWATER_PDK_REPO=\"$SKYWATER_PDK_REPO\""
say ""
say "Then:"
say "  source ~/.zshrc"

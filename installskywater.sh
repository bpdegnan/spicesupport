#!/usr/bin/env zsh
# Interactive, BSD-clean, NO-SUDO installer for SkyWater Sky130 PDK
#
# Fixes HTTPS-only firewall environments by:
# - Rewriting git+ssh:// / ssh:// / git@github.com: / git:// URLs to https://
# - Patching BOTH known .gitmodules locations:
#     1) top-level .gitmodules
#     2) libraries/sky130_fd_io/latest/.gitmodules
# - Syncing and updating submodules before make

set -eu

# ---------------- helpers ----------------
say() { print -r -- "$*"; }
err() { print -r -- "ERROR: $*" >&2; }
die() { err "$@"; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

ask() {
  local prompt="$1"
  local def="${2:-}"
  local ans=""
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
  local prompt="$1"
  local def="${2:-y}"
  local ans=""
  while true; do
    if [[ "$def" == "y" ]]; then
      printf "%s [Y/n]: " "$prompt" > /dev/tty
    else
      printf "%s [y/N]: " "$prompt" > /dev/tty
    fi
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
  if have port; then
    print "macports"
  elif have brew; then
    print "homebrew"
  elif have apt-get; then
    print "apt"
  elif have dnf; then
    print "dnf"
  elif have yum; then
    print "yum"
  else
    print "none"
  fi
}

check_deps() {
  local missing=()
  for t in git make python3 tcsh sed; do
    have "$t" || missing+=("$t")
  done
  if (( ${#missing[@]} > 0 )); then
    say "Missing tools:"
    for m in "${missing[@]}"; do
      say "  - $m"
    done
    return 1
  fi
  return 0
}

print_dep_instructions() {
  local pm="$1"
  say ""
  say "Required tools (user-level): git make python3 tcsh sed"
  say "No sudo will be used."
  say ""
  case "$pm" in
    macports)
      say "MacPorts (user prefix):"
      say "  port install git python311 tcsh"
      ;;
    homebrew)
      say "Homebrew:"
      say "  brew install git python tcsh"
      ;;
    *)
      say "Ensure the tools are available in PATH."
      ;;
  esac
  say ""
}

# Rewrite schemes in a .gitmodules file (BSD sed: -i '')
patch_gitmodules_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0

  # Only patch if it actually contains a blocked scheme (avoid needless file churn)
  if ! /usr/bin/grep -qE 'git\+ssh://|ssh://git@github\.com/|git@github\.com:|git://' "$f"; then
    return 0
  fi

  say "Patching $f (forcing HTTPS URLs)..."
  /usr/bin/sed -i '' \
    -e 's#url = git\+ssh://github.com/#url = https://github.com/#g' \
    -e 's#url = git\+ssh://git@github.com/#url = https://github.com/#g' \
    -e 's#url = ssh://git@github.com/#url = https://github.com/#g' \
    -e 's#url = git@github.com:#url = https://github.com/#g' \
    -e 's#url = git://#url = https://#g' \
    "$f"
}

# Apply rewrite rules + patch known .gitmodules locations, then sync
prepare_https_submodules() {
  local repo="$1"

  say "Configuring git URL rewrites (global + local) ..."
  # global (user-level): helps for nested submodules
  git config --global url."https://github.com/".insteadOf "git+ssh://github.com/"
  git config --global url."https://github.com/".insteadOf "git+ssh://git@github.com/"
  git config --global url."https://github.com/".insteadOf "git@github.com:"
  git config --global url."https://github.com/".insteadOf "ssh://git@github.com/"
  git config --global url."https://".insteadOf "git://"

  (
    cd "$repo"

    # local (repo-level): belt-and-suspenders
    git config --local url."https://github.com/".insteadOf "git+ssh://github.com/"
    git config --local url."https://github.com/".insteadOf "git+ssh://git@github.com/"
    git config --local url."https://github.com/".insteadOf "git@github.com:"
    git config --local url."https://github.com/".insteadOf "ssh://git@github.com/"
    git config --local url."https://".insteadOf "git://"

    # Patch top-level .gitmodules if present
    patch_gitmodules_file ".gitmodules"

    # Patch the specific nested .gitmodules you observed (if/when it exists)
    patch_gitmodules_file "libraries/sky130_fd_io/latest/.gitmodules"

    # Sync .gitmodules → .git/config (critical after patch)
    git submodule sync --recursive || true
  )
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

# 1) Pre-flight HTTPS conversion BEFORE submodules init
prepare_https_submodules "$WORKDIR"

say "Updating submodules (pass 1)..."
( cd "$WORKDIR" && git submodule update --init --recursive )

# 2) Now that submodules exist, patch nested .gitmodules (if it appeared) and resync
prepare_https_submodules "$WORKDIR"

say "Updating submodules (pass 2, to catch nested git+ssh)..."
( cd "$WORKDIR" && git submodule update --init --recursive )

say ""
say "Build summary:"
say "  PDK_ROOT          = $PDK_ROOT"
say "  SKYWATER_PDK_REPO = $SKYWATER_PDK_REPO"
say "  TARGET            = $TARGET"
say ""

ask_yn "Proceed with build?" "y" || die "Aborted."

say ""
say "Building SkyWater PDK (this can take a while)..."
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
say "To make PDK_ROOT permanent, add ONE of the following to ~/.zshrc:"
say ""
say "Simple export (recommended):"
say "  export PDK_ROOT=\"$PDK_ROOT\""
say ""
say "Guarded export (won't override an existing value):"
say "  if [[ -z \"\${PDK_ROOT:-}\" ]]; then"
say "    export PDK_ROOT=\"$PDK_ROOT\""
say "  fi"
say ""
say "Optional (also persist the repo checkout path):"
say "  export SKYWATER_PDK_REPO=\"$SKYWATER_PDK_REPO\""
say ""
say "After editing ~/.zshrc:"
say "  source ~/.zshrc"

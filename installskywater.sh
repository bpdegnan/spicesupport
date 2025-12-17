#!/usr/bin/env zsh
# Interactive, BSD-clean, NO-SUDO installer for SkyWater Sky130 PDK
#
# Key features:
# - Prompts read from /dev/tty (robust; avoids “funny” prompting)
# - Prints current directory before asking for PDK_ROOT
# - Exports PDK_ROOT and SKYWATER_PDK_REPO for this run
# - Forces HTTPS for git URLs (including git+ssh://) BEFORE submodules and BEFORE make
# - Prints a zshrc snippet to persist PDK_ROOT (and optionally SKYWATER_PDK_REPO)

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
  for t in git make python3 tcsh; do
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
  say "Required tools (user-level): git make python3 tcsh"
  say "No sudo will be used."
  say ""
  case "$pm" in
    macports)
      say "MacPorts (user prefix):"
      say "  port install git python311 tcsh"
      say "  # ensure MacPorts bin dir is in PATH"
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

force_https_git() {
  # Enforce HTTPS for SSH-ish and git:// URLs, including git+ssh:// used by some submodules.
  local repo="$1"
  say "Forcing HTTPS for git URLs (including git+ssh://) ..."

  # GLOBAL rewrite rules (user-level, no sudo). Most reliable for deeply nested submodules.
  git config --global url."https://github.com/".insteadOf "git+ssh://github.com/"
  git config --global url."https://github.com/".insteadOf "git+ssh://git@github.com/"
  git config --global url."https://github.com/".insteadOf "git@github.com:"
  git config --global url."https://github.com/".insteadOf "ssh://git@github.com/"
  git config --global url."https://".insteadOf "git://"

  # LOCAL rewrite rules too (belt and suspenders).
  (
    cd "$repo"
    git config --local url."https://github.com/".insteadOf "git+ssh://github.com/"
    git config --local url."https://github.com/".insteadOf "git+ssh://git@github.com/"
    git config --local url."https://github.com/".insteadOf "git@github.com:"
    git config --local url."https://github.com/".insteadOf "ssh://git@github.com/"
    git config --local url."https://".insteadOf "git://"

    # Sync submodule URLs into .git/config so the rewrites take effect for submodule operations
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

# Critical: apply HTTPS rewrite BEFORE any submodule operations
force_https_git "$WORKDIR"

say "Updating submodules (over HTTPS)..."
( cd "$WORKDIR" && git submodule update --init --recursive )

# Helpful: re-apply after submodules initialize (nested submodules inherit the rewrites globally anyway)
force_https_git "$WORKDIR"

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

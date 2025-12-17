#!/usr/bin/env zsh
# installskywater.zsh
# Interactive, BSD-clean, NO-SUDO installer for SkyWater Sky130 PDK
# - Prompts read from /dev/tty (robust in terminals)
# - Exports PDK_ROOT for this run
# - Prints zshrc snippet for persistence
# - Optionally sets SKYWATER_PDK_REPO to the repo checkout path

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
      say "  # Ensure your MacPorts bin dir is in PATH"
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

# Export for this script and any child processes (make, etc.)
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

# Export repo path too (useful for other helper scripts)
export SKYWATER_PDK_REPO="$WORKDIR"

say "Updating submodules..."
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

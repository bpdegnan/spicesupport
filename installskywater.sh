#!/bin/zsh
# Interactive, BSD-clean, NO-SUDO installer for SkyWater Sky130 PDK

set -eu

# ---------------- helpers ----------------
say() { print -r -- "$*"; }
err() { print -r -- "ERROR: $*" >&2; }
die() { err "$@"; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# Read explicitly from the controlling terminal to avoid buffering issues
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

# ---------------- main ----------------
say "SkyWater Open PDK installer (Sky130)"
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

# ---- Print current directory explicitly ----
say "Current working directory:"
say "  $(pwd)"
say ""

PDK_ROOT_DEFAULT="${HOME}/pdks"
PDK_ROOT="$(ask "Where should PDK_ROOT be installed?" "$PDK_ROOT_DEFAULT")"
PDK_ROOT="${PDK_ROOT/#\~/${HOME}}"
[[ -z "$PDK_ROOT" ]] && die "PDK_ROOT cannot be empty."

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

say "Updating submodules..."
( cd "$WORKDIR" && git submodule update --init --recursive )

say ""
say "Build summary:"
say "  PDK_ROOT = $PDK_ROOT"
say "  WORKDIR  = $WORKDIR"
say "  TARGET   = $TARGET"
say ""

ask_yn "Proceed with build?" "y" || die "Aborted."

say ""
say "Building SkyWater PDK (this can take a while)..."
( cd "$WORKDIR" && make "$TARGET" PDK_ROOT="$PDK_ROOT" )

say ""
say "Installation complete."
say ""
say "ngspice models:"
say "  $PDK_ROOT/sky130A/libs.tech/ngspice/"
say ""
say "Optional:"
say "  echo 'export PDK_ROOT=\"$PDK_ROOT\"' >> ~/.zshrc"

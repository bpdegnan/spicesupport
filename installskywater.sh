#!/usr/bin/env zsh
# installskywater.sh — interactive installer for SkyWater Sky130 open PDK
#!/bin/zsh
# install_skywater_pdks_nosudo.zsh
# Interactive, BSD-clean, NO-SUDO installer for SkyWater Sky130 PDK

set -eu

# ---------------- helpers ----------------
say() { print -- "$*"; }
err() { print -- "ERROR: $*" >&2; }
die() { err "$@"; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

ask() {
  local prompt="$1"
  local def="${2:-}"
  local ans=""
  if [[ -n "$def" ]]; then
    print -n -- "${prompt} [${def}]: "
  else
    print -n -- "${prompt}: "
  fi
  IFS= read -r ans || true
  [[ -z "$ans" ]] && ans="$def"
  print -- "$ans"
}

ask_yn() {
  local prompt="$1"
  local def="${2:-y}"
  local ans=""
  while true; do
    if [[ "$def" == "y" ]]; then
      print -n -- "${prompt} [Y/n]: "
    else
      print -n -- "${prompt} [y/N]: "
    fi
    IFS= read -r ans || true
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

print_dep_instructions() {
  local pm="$1"

  say ""
  say "== Missing dependencies =="
  say "Required: git, make, python3, tcsh"
  say ""
  say "You do NOT have root. Install these in user space."
  say ""

  case "$pm" in
    macports)
      say "MacPorts (user prefix):"
      say "  port install git python311 tcsh"
      say "  # ensure your MacPorts bin dir is in PATH"
      ;;
    homebrew)
      say "Homebrew (no sudo):"
      say "  brew install git python tcsh"
      ;;
    apt)
      say "apt detected, but requires root."
      say "Use a user-local environment (conda, nix, or preinstalled tools)."
      ;;
    dnf|yum)
      say "dnf/yum detected, but requires root."
      say "Use a user-local environment."
      ;;
    *)
      say "No package manager detected."
      say "Ensure git, make, python3, and tcsh are available in PATH."
      ;;
  esac

  say ""
  say "After installing, re-run this script."
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

# ---------------- main ----------------
say "SkyWater Open PDK installer (Sky130)"
say "Root-free / sudo-free interactive mode"
say ""

OS="$(detect_os)"
PM="$(detect_pkg_mgr)"

say "Detected OS:  ${OS}"
say "Detected PM:  ${PM}"
say ""

if ! check_deps; then
  print_dep_instructions "$PM"
  die "Dependencies missing."
fi

say "All required tools found."
say ""

PDK_ROOT_DEFAULT="${HOME}/pdks"
PDK_ROOT="$(ask "Where should PDK_ROOT be?" "$PDK_ROOT_DEFAULT")"
PDK_ROOT="${PDK_ROOT/#\~/${HOME}}"
[[ -z "$PDK_ROOT" ]] && die "PDK_ROOT cannot be empty."

if [[ ! -d "$PDK_ROOT" ]]; then
  ask_yn "Create $PDK_ROOT?" "y" || die "Cannot proceed."
  mkdir -p "$PDK_ROOT"
fi

REPO_URL="$(ask "SkyWater PDK git URL" "https://github.com/google/skywater-pdk.git")"

WORKDIR_DEFAULT="${PDK_ROOT}/src/skywater-pdk"
WORKDIR="$(ask "Where to clone/build the repo?" "$WORKDIR_DEFAULT")"
WORKDIR="${WORKDIR/#\~/${HOME}}"

TARGET="$(ask "Build target" "sky130")"

say ""
if [[ -d "$WORKDIR/.git" ]]; then
  say "Repo exists at $WORKDIR"
  ask_yn "Update repo (git pull)?" "y" && ( cd "$WORKDIR" && git pull --rebase )
else
  say "Cloning repo..."
  mkdir -p "$(dirname "$WORKDIR")"
  git clone "$REPO_URL" "$WORKDIR"
fi

say "Updating submodules..."
( cd "$WORKDIR" && git submodule update --init --recursive )

say ""
say "Configuration summary:"
say "  PDK_ROOT = $PDK_ROOT"
say "  WORKDIR  = $WORKDIR"
say "  TARGET   = $TARGET"
say ""

ask_yn "Proceed with build?" "y" || die "Aborted."

say ""
say "Building (this may take a while)..."
( cd "$WORKDIR" && make "$TARGET" PDK_ROOT="$PDK_ROOT" )

say ""
say "Installation complete."
say ""
say "ngspice models:"
say "  $PDK_ROOT/sky130A/libs.tech/ngspice/"
say ""
say "Add to ~/.zshrc if desired:"
say "  export PDK_ROOT=\"$PDK_ROOT\""


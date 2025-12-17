#!/usr/bin/env zsh
# installskywater.sh — interactive installer for SkyWater Sky130 open PDK


set -eu

# ---------- helpers ----------
say()  { print -- "$*"; }
err()  { print -- "ERROR: $*" >&2; }
die()  { err "$@"; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

ask() {
  # ask "Prompt" "default"
  local prompt="$1"
  local def="${2:-}"
  local ans=""
  if [[ -n "$def" ]]; then
    print -n -- "${prompt} [${def}]: "
  else
    print -n -- "${prompt}: "
  fi
  IFS= read -r ans || true
  if [[ -z "$ans" ]]; then
    ans="$def"
  fi
  print -- "$ans"
}

ask_yn() {
  # ask_yn "Prompt" "y|n"
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
    if [[ -z "$ans" ]]; then
      ans="$def"
    fi
    case "$ans" in
      y|yes) return 0 ;;
      n|no)  return 1 ;;
      *) say "Please answer y or n." ;;
    esac
  done
}

detect_os() {
  local u="$(uname -s 2>/dev/null || true)"
  case "$u" in
    Darwin) print "macos" ;;
    Linux)  print "linux" ;;
    *)      print "other" ;;
  esac
}

detect_pkg_mgr() {
  # best-effort
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
  local os="$1"
  local pm="$2"

  say ""
  say "== Dependency install suggestions =="
  say "Required tools: git, make, python3, tcsh"
  say ""

  case "$pm" in
    macports)
      say "MacPorts:"
      say "  sudo port selfupdate"
      say "  sudo port install git python311 tcsh"
      say "  # (make is provided by Xcode command line tools; install with: xcode-select --install)"
      ;;
    homebrew)
      say "Homebrew:"
      say "  brew update"
      say "  brew install git python tcsh"
      say "  # (make is provided by Xcode command line tools; install with: xcode-select --install)"
      ;;
    apt)
      say "Debian/Ubuntu (apt):"
      say "  sudo apt-get update"
      say "  sudo apt-get install -y git make python3 tcsh"
      ;;
    dnf)
      say "Fedora/RHEL (dnf):"
      say "  sudo dnf install -y git make python3 tcsh"
      ;;
    yum)
      say "RHEL/CentOS (yum):"
      say "  sudo yum install -y git make python3 tcsh"
      ;;
    none|*)
      say "No supported package manager detected."
      say "Please install: git, make, python3, tcsh using your system tools."
      ;;
  esac
  say ""
}

check_deps() {
  local missing=0
  for t in git make python3 tcsh; do
    if ! have "$t"; then
      say "Missing: $t"
      missing=1
    fi
  done
  return "$missing"
}

# ---------- main ----------
say "SkyWater Open PDK installer (Sky130) — interactive"
say "This will clone and build the PDK. You choose where it is installed."
say ""

OS="$(detect_os)"
PM="$(detect_pkg_mgr)"
say "Detected OS: ${OS}"
say "Detected package manager: ${PM}"
say ""

if check_deps; then
  : # all good
else
  print_dep_instructions "$OS" "$PM"
  if ask_yn "Do you want me to attempt to install missing dependencies now?" "n"; then
    case "$PM" in
      macports)
        say "Running: sudo port selfupdate && sudo port install git python311 tcsh"
        sudo port selfupdate
        sudo port install git python311 tcsh
        ;;
      homebrew)
        say "Running: brew update && brew install git python tcsh"
        brew update
        brew install git python tcsh
        ;;
      apt)
        say "Running: sudo apt-get update && sudo apt-get install -y git make python3 tcsh"
        sudo apt-get update
        sudo apt-get install -y git make python3 tcsh
        ;;
      dnf)
        say "Running: sudo dnf install -y git make python3 tcsh"
        sudo dnf install -y git make python3 tcsh
        ;;
      yum)
        say "Running: sudo yum install -y git make python3 tcsh"
        sudo yum install -y git make python3 tcsh
        ;;
      *)
        die "Cannot auto-install dependencies (no supported package manager detected)."
        ;;
    esac
  else
    die "Dependencies missing. Install them, then re-run this script."
  fi
fi

# Re-check after possible install
if ! check_deps; then
  die "Some dependencies are still missing. Please install them and re-run."
fi

say ""
PDK_ROOT_DEFAULT="${HOME}/pdks"
PDK_ROOT="$(ask "Where should PDK_ROOT be (install destination)?" "$PDK_ROOT_DEFAULT")"
[[ -z "$PDK_ROOT" ]] && die "PDK_ROOT cannot be empty."

# Expand ~ manually
PDK_ROOT="${PDK_ROOT/#\~/${HOME}}"

if [[ ! -d "$PDK_ROOT" ]]; then
  if ask_yn "Create directory ${PDK_ROOT}?" "y"; then
    mkdir -p "$PDK_ROOT"
  else
    die "Cannot proceed without PDK_ROOT directory."
  fi
fi

say ""
REPO_URL_DEFAULT="https://github.com/google/skywater-pdk.git"
REPO_URL="$(ask "SkyWater PDK git URL" "$REPO_URL_DEFAULT")"
[[ -z "$REPO_URL" ]] && die "Repo URL cannot be empty."

CLONE_DIR_DEFAULT="${PDK_ROOT}/src/skywater-pdk"
CLONE_DIR="$(ask "Where to clone/build the repo (working directory)?" "$CLONE_DIR_DEFAULT")"
CLONE_DIR="${CLONE_DIR/#\~/${HOME}}"

say ""
BUILD_TARGET="$(ask "Which build target? (recommended: sky130)" "sky130")"
if [[ "$BUILD_TARGET" != "sky130" ]]; then
  say "Note: this script is primarily designed for sky130. Proceeding anyway."
fi

say ""
if [[ -d "${CLONE_DIR}/.git" ]]; then
  say "Repo already exists at: ${CLONE_DIR}"
  if ask_yn "Update it (git pull)?" "y"; then
    ( cd "$CLONE_DIR" && git pull --rebase )
  else
    say "Keeping existing repo as-is."
  fi
else
  say "Cloning into: ${CLONE_DIR}"
  mkdir -p "$(dirname "$CLONE_DIR")"
  git clone "$REPO_URL" "$CLONE_DIR"
fi

say ""
say "Initializing/updating submodules..."
( cd "$CLONE_DIR" && git submodule update --init --recursive )

say ""
say "Build configuration:"
say "  PDK_ROOT  = $PDK_ROOT"
say "  REPO_DIR  = $CLONE_DIR"
say "  TARGET    = $BUILD_TARGET"
say ""

if ! ask_yn "Proceed with build now?" "y"; then
  die "Aborted by user."
fi

say ""
say "Building... (this can take a while depending on your machine)"
( cd "$CLONE_DIR" && make "$BUILD_TARGET" PDK_ROOT="$PDK_ROOT" )

say ""
say "== Done =="
say "Installed PDK(s) under:"
say "  $PDK_ROOT"
say ""
say "Common sky130A paths:"
say "  $PDK_ROOT/sky130A/libs.tech/ngspice/"
say "  $PDK_ROOT/sky130A/libs.ref/sky130_fd_pr/"
say ""
say "ngspice include example:"
say "  .include \"$PDK_ROOT/sky130A/libs.tech/ngspice/sky130.lib.spice\""
say "  .lib sky130.lib.spice tt"
say ""
say "To persist PDK_ROOT in your shell:"
say "  echo 'export PDK_ROOT=\"$PDK_ROOT\"' >> ~/.zshrc"
say "  source ~/.zshrc"

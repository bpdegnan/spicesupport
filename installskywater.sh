#!/usr/bin/env zsh
#
# Interactive, NO-SUDO SkyWater Sky130 installer with HTTPS-only firewall support.
# OS-aware sed in-place edits (macOS BSD sed vs Linux GNU sed). 

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

check_deps() {
  local missing=()
  for t in git make python3 tcsh find grep sed; do
    have "$t" || missing+=("$t")
  done
  if (( ${#missing[@]} > 0 )); then
    say "Missing tools:"
    for m in "${missing[@]}"; do say "  - $m"; done
    return 1
  fi
  return 0
}

# --- OS-aware sed -i wrapper ---
# usage: sedi <script> <file>
sedi() {
  local script="$1"
  local file="$2"
  local os="${OS:-$(detect_os)}"

  if [[ "$os" == "macos" ]]; then
    # BSD sed requires a backup extension argument (empty means in-place with no backup)
    sed -i '' -e "$script" "$file"
  else
    # GNU sed
    sed -i -e "$script" "$file"
  fi
}

# Patch ONE .gitmodules file, tolerant of whitespace around '='
patch_gitmodules_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0

  # only patch if blocked schemes appear
  if ! grep -qE 'git\+ssh://|ssh://git@github\.com/|git@github\.com:|git://' "$f"; then
    return 0
  fi

  say "Patching $f (forcing HTTPS URLs)..."

  # We preserve indentation and "url" token, only rewrite the URL prefix.
  # Match: (url <spaces>=<spaces>) + scheme/prefix
  sedi 's#\([[:space:]]*url[[:space:]]*=[[:space:]]*\)git+ssh://github\.com/#\1https://github.com/#g' "$f"
  sedi 's#\([[:space:]]*url[[:space:]]*=[[:space:]]*\)git+ssh://git@github\.com/#\1https://github.com/#g' "$f"
  sedi 's#\([[:space:]]*url[[:space:]]*=[[:space:]]*\)ssh://git@github\.com/#\1https://github.com/#g' "$f"
  sedi 's#\([[:space:]]*url[[:space:]]*=[[:space:]]*\)git@github\.com:#\1https://github.com/#g' "$f"
  sedi 's#\([[:space:]]*url[[:space:]]*=[[:space:]]*\)git://#\1https://#g' "$f"

  # verify blocked schemes are gone
  if grep -qE 'git\+ssh://|ssh://git@github\.com/|git@github\.com:|git://' "$f"; then
    die "Patch incomplete: blocked URL scheme still present in $f"
  fi
}

patch_all_gitmodules() {
  local repo="$1"
  say "Scanning for .gitmodules under $repo ..."
  find "$repo" -name .gitmodules -type f -print0 2>/dev/null | \
  while IFS= read -r -d '' f; do
    patch_gitmodules_file "$f"
  done
}

prepare_https_submodules() {
  local repo="$1"

  # Global rewrites (user-level) help with nested clones
  git config --global url."https://github.com/".insteadOf "git+ssh://github.com/"
  git config --global url."https://github.com/".insteadOf "git+ssh://git@github.com/"
  git config --global url."https://github.com/".insteadOf "git@github.com:"
  git config --global url."https://github.com/".insteadOf "ssh://git@github.com/"
  git config --global url."https://".insteadOf "git://"

  # Local rewrites in the top repo (belt-and-suspenders)
  (
    cd "$repo"
    git config --local url."https://github.com/".insteadOf "git+ssh://github.com/"
    git config --local url."https://github.com/".insteadOf "git+ssh://git@github.com/"
    git config --local url."https://github.com/".insteadOf "git@github.com:"
    git config --local url."https://github.com/".insteadOf "ssh://git@github.com/"
    git config --local url."https://".insteadOf "git://"
  )

  # Explicitly patch any .gitmodules (including nested ones)
  patch_all_gitmodules "$repo"

  # Sync to propagate .gitmodules URLs into .git/config
  ( cd "$repo" && git submodule sync --recursive || true )
}

# ---------------- main ----------------
OS="$(detect_os)"
say "SkyWater Open PDK installer (Sky130)"
say "OS detected: $OS"
say ""

if ! check_deps; then
  die "Missing dependencies. Ensure git, make, python3, tcsh, find, grep, sed are installed and in PATH."
fi

say "Current working directory:"
say "  $(pwd)"
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
WORKDIR_DEFAULT="${PDK_ROOT}/skywater-pdk"
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

# # Patch URLs BEFORE submodule init/update
# prepare_https_submodules "$WORKDIR"

# say "Updating submodules (pass 1)..."
# ( cd "$WORKDIR" && git submodule update --init --recursive )

# # Patch again after nested submodules appear
# prepare_https_submodules "$WORKDIR"

# say "Updating submodules (pass 2)..."
# ( cd "$WORKDIR" && git submodule update --init --recursive )

# say ""
# say "Build summary:"
# say "  PDK_ROOT          = $PDK_ROOT"
# say "  SKYWATER_PDK_REPO = $SKYWATER_PDK_REPO"
# say "  TARGET            = $TARGET"
# say ""

# ask_yn "Proceed with build?" "y" || die "Aborted."

# say ""
# say "Building SkyWater PDK ..."
# ( cd "$WORKDIR" && make "$TARGET" PDK_ROOT="$PDK_ROOT" )

# say ""
# say "Installation complete."
# say ""
# say "PDK installed at:"
# say "  $PDK_ROOT"
# say ""
# say "ngspice models:"
# say "  $PDK_ROOT/sky130A/libs.tech/ngspice/"
# say ""
# say "This session exports:"
# say "  PDK_ROOT=\"$PDK_ROOT\""
# say "  SKYWATER_PDK_REPO=\"$SKYWATER_PDK_REPO\""
# say ""
# say "To make PDK_ROOT permanent, add to ~/.zshrc:"
# say "  export PDK_ROOT=\"$PDK_ROOT\""
# say "Optional:"
# say "  export SKYWATER_PDK_REPO=\"$SKYWATER_PDK_REPO\""
# say ""
# say "Then:"
# say "  source ~/.zshrc"

#!/usr/bin/env zsh
# Interactive, NO-SUDO SkyWater Sky130 installer with HTTPS-only firewall support.
#
# Key fix vs earlier versions:
#   DO NOT run `git submodule update --init --recursive` first.
#   Instead:
#     1) init first-level submodules (non-recursive)
#     2) patch any newly-checked-out .gitmodules (including nested ones)
#     3) sync
#     4) then recurse
#
# OS-aware sed in-place edits (macOS BSD sed vs Linux GNU sed). No perl required.

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
  if [[ "$OS" == "macos" ]]; then
    sed -i '' -e "$script" "$file"
  else
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

  # Preserve indentation; only rewrite URL prefix.
  sedi 's#\([[:space:]]*url[[:space:]]*=[[:space:]]*\)git+ssh://github\.com/#\1https://github.com/#g' "$f"
  sedi 's#\([[:space:]]*url[[:space:]]*=[[:space:]]*\)git+ssh://git@github\.com/#\1https://github.com/#g' "$f"
  sedi 's#\([[:space:]]*url[[:space:]]*=[[:space:]]*\)ssh://git@github\.com/#\1https://github.com/#g' "$f"
  sedi 's#\([[:space:]]*url[[:space:]]*=[[:space:]]*\)git@github\.com:#\1https://github.com/#g' "$f"
  sedi 's#\([[:space:]]*url[[:space:]]*=[[:space:]]*\)git://#\1https://#g' "$f"
}

patch_all_gitmodules() {
  local repo="$1"
  say "Scanning for .gitmodules under $repo ..."
  find "$repo" -name .gitmodules -type f -print0 2>/dev/null | \
  while IFS= read -r -d '' f; do
    patch_gitmodules_file "$f"
  done
}

set_git_https_rewrites() {
  # Global (user-level) rewrite rules help for clones and deep nesting.
  git config --global url."https://github.com/".insteadOf "git+ssh://github.com/"
  git config --global url."https://github.com/".insteadOf "git+ssh://git@github.com/"
  git config --global url."https://github.com/".insteadOf "git@github.com:"
  git config --global url."https://github.com/".insteadOf "ssh://git@github.com/"
  git config --global url."https://".insteadOf "git://"
}

prepare_https_submodules() {
  local repo="$1"
  set_git_https_rewrites

  # Local rewrite rules too (repo-level)
  (
    cd "$repo"
    git config --local url."https://github.com/".insteadOf "git+ssh://github.com/"
    git config --local url."https://github.com/".insteadOf "git+ssh://git@github.com/"
    git config --local url."https://github.com/".insteadOf "git@github.com:"
    git config --local url."https://github.com/".insteadOf "ssh://git@github.com/"
    git config --local url."https://".insteadOf "git://"
  )

  # Patch any .gitmodules currently present (top + any already-checked-out submodules)
  patch_all_gitmodules "$repo"

  # Sync .gitmodules into configs
  ( cd "$repo" && git submodule sync --recursive || true )
}

# Two-phase submodule init to avoid nested git+ssh URLs being used before we can patch them
submodules_two_phase_update() {
  local repo="$1"

  say "Submodules phase 1: init FIRST-LEVEL only (non-recursive)..."
  ( cd "$repo" && git submodule update --init )

  say "Patching .gitmodules that arrived during phase 1..."
  prepare_https_submodules "$repo"

  say "Submodules phase 2: init/update recursively (now that URLs are patched)..."
  ( cd "$repo" && git submodule update --init --recursive )

  # Optional extra pass: some trees add more nested .gitmodules after recursion
  say "Submodules phase 3: final patch+sync+update (belt-and-suspenders)..."
  prepare_https_submodules "$repo"
  ( cd "$repo" && git submodule update --init --recursive )
}


# ---- interactive target selection ----
# Curated list based on the Makefile you have (make -qp output)
TARGETS=(
  submodules
  libraries-info
  env
  env-info
  enter
  timing
  check
  sky130_fd_sc_hd
  sky130_fd_sc_hdll
  sky130_fd_sc_hs
  sky130_fd_sc_hvl
  sky130_fd_sc_lp
  sky130_fd_sc_ls
  sky130_fd_sc_ms
  sky130_fd_sc_ms-leakage
)

needs_env() {
  # return 0 if the target likely needs the conda/python tooling
  case "$1" in
    timing|check|sky130_fd_sc_*) return 0 ;;
    *) return 1 ;;
  esac
}

select_targets_menu() {
  local choice=""
  say ""
  say "Select what to build:"
  say "  1) One target"
  say "  2) Multiple targets"
  say "  3) All targets"
  say "  4) Just submodules (fastest)"
  say ""
  choice="$(ask "Choice" "4")"

  case "$choice" in
    1)
      say ""
      say "Available targets:"
      local i=1
      for t in "${TARGETS[@]}"; do
        say "  $i) $t"
        i=$((i+1))
      done
      say ""
      local n
      n="$(ask "Enter target number" "1")"
      [[ "$n" =~ '^[0-9]+$' ]] || die "Not a number: $n"
      (( n >= 1 && n <= ${#TARGETS[@]} )) || die "Out of range."
      SELECTED_TARGETS=("${TARGETS[$n]}")
      ;;
    2)
      say ""
      say "Available targets:"
      local i=1
      for t in "${TARGETS[@]}"; do
        say "  $i) $t"
        i=$((i+1))
      done
      say ""
      say "Enter a space-separated list of numbers, e.g.: 1 6 8"
      local nums
      nums="$(ask "Numbers" "1")"
      SELECTED_TARGETS=()
      local n
      for n in ${(z)nums}; do
        [[ "$n" =~ '^[0-9]+$' ]] || die "Not a number: $n"
        (( n >= 1 && n <= ${#TARGETS[@]} )) || die "Out of range: $n"
        SELECTED_TARGETS+=("${TARGETS[$n]}")
      done
      ;;
    3)
      SELECTED_TARGETS=("${TARGETS[@]}")
      ;;
    4)
      SELECTED_TARGETS=(submodules)
      ;;
    *)
      die "Unknown choice: $choice"
      ;;
  esac
}

run_selected_targets() {
  local repo="$1"
  local t

  say ""
  say "Selected targets:"
  for t in "${SELECTED_TARGETS[@]}"; do
    say "  - $t"
  done
  say ""

  # If any target needs env, build env once up front
  local need_env_any=1
  for t in "${SELECTED_TARGETS[@]}"; do
    if needs_env "$t"; then
      need_env_any=0
      break
    fi
  done

  (
    cd "$repo"

    if (( need_env_any == 0 )); then
      say "Ensuring environment exists: make env"
      make env
    fi

    for t in "${SELECTED_TARGETS[@]}"; do
      say ""
      say "== Running: make $t =="
      make "$t"
    done
  )
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

# Ensure git rewrite rules are installed before any submodule activity
set_git_https_rewrites

# Two-phase submodule update to avoid nested git+ssh before patching
submodules_two_phase_update "$WORKDIR"

say ""
say "Build summary:"
say "  PDK_ROOT          = $PDK_ROOT"
say "  SKYWATER_PDK_REPO = $SKYWATER_PDK_REPO"
say "  TARGET            = $TARGET"
say ""

ask_yn "Proceed with build?" "y" || die "Aborted."

select_targets_menu
run_selected_targets "$WORKDIR"

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

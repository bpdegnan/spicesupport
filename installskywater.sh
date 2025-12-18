#!/usr/bin/env zsh
# Root-free / sudo-free installer + builder for SkyWater PDK repo (Sky130 ecosystem)
#
# Features:
# - Robust prompting via /dev/tty
# - OS-aware sed in-place edits (macOS BSD sed vs Linux GNU sed)
# - HTTPS-only firewall support:
#     * global+local git URL rewrites
#     * patches ANY .gitmodules under repo (handles url = git+ssh://...)
#     * two-phase submodule update (non-recursive -> patch -> recursive)
# - Rerun-friendly:
#     * if repo exists, offers "make-only" mode (skip git/submodules)
# - Interactive make target selection:
#     * one / multiple / all / just submodules
# - Optional persistence to ~/.zshrc:
#     * export PDK_ROOT=...
#     * export SKYWATERPDK=...  (repo path)
#     * export SKYWATER_PDK_REPO=... (alias)

set -eu

# ---------------- helpers ----------------
function say() { print -r -- "$*"; }
function err() { print -r -- "ERROR: $*" >&2; }
function die() { err "$@"; exit 1; }
function have() { command -v "$1" >/dev/null 2>&1; }

function ask() {
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

function ask_yn() {
  local prompt="$1" def="${2:-y}" ans=""
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

function detect_os() {
  case "$(uname -s 2>/dev/null || true)" in
    Darwin) print "macos" ;;
    Linux)  print "linux" ;;
    *)      print "other" ;;
  esac
}

function check_deps() {
  local missing=()
  for t in git make python3 tcsh find grep sed awk; do
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
function sedi() {
  local script="$1"
  local file="$2"
  if [[ "$OS" == "macos" ]]; then
    sed -i '' -e "$script" "$file"
  else
    sed -i -e "$script" "$file"
  fi
}

# ---------------- HTTPS-only git fixes ----------------
function set_git_https_rewrites() {
  git config --global url."https://github.com/".insteadOf "git+ssh://github.com/"
  git config --global url."https://github.com/".insteadOf "git+ssh://git@github.com/"
  git config --global url."https://github.com/".insteadOf "git@github.com:"
  git config --global url."https://github.com/".insteadOf "ssh://git@github.com/"
  git config --global url."https://".insteadOf "git://"
}

function patch_gitmodules_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0

  if ! grep -qE 'git\+ssh://|ssh://git@github\.com/|git@github\.com:|git://' "$f"; then
    return 0
  fi

  say "Patching $f (forcing HTTPS URLs)..."

  sedi 's#\([[:space:]]*url[[:space:]]*=[[:space:]]*\)git+ssh://github\.com/#\1https://github.com/#g' "$f"
  sedi 's#\([[:space:]]*url[[:space:]]*=[[:space:]]*\)git+ssh://git@github\.com/#\1https://github.com/#g' "$f"
  sedi 's#\([[:space:]]*url[[:space:]]*=[[:space:]]*\)ssh://git@github\.com/#\1https://github.com/#g' "$f"
  sedi 's#\([[:space:]]*url[[:space:]]*=[[:space:]]*\)git@github\.com:#\1https://github.com/#g' "$f"
  sedi 's#\([[:space:]]*url[[:space:]]*=[[:space:]]*\)git://#\1https://#g' "$f"
}

function patch_all_gitmodules() {
  local repo="$1"
  say "Scanning for .gitmodules under $repo ..."
  find "$repo" -name .gitmodules -type f -print0 2>/dev/null | \
  while IFS= read -r -d '' f; do
    patch_gitmodules_file "$f"
  done
}

function prepare_https_submodules() {
  local repo="$1"
  set_git_https_rewrites

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

function submodules_two_phase_update() {
  local repo="$1"
  say "Submodules phase 1: init FIRST-LEVEL only (non-recursive)..."
  ( cd "$repo" && git submodule update --init )

  say "Patch .gitmodules that arrived during phase 1, then sync..."
  prepare_https_submodules "$repo"

  say "Submodules phase 2: init/update recursively..."
  ( cd "$repo" && git submodule update --init --recursive )

  say "Final patch+sync+update pass (belt-and-suspenders)..."
  prepare_https_submodules "$repo"
  ( cd "$repo" && git submodule update --init --recursive )
}

function conda_accept_tos_if_needed() {
  local conda_bin="$1"   # full path to conda
  [[ -x "$conda_bin" ]] || return 0

  # Try a non-destructive ToS status check; if it fails, accept for the known channels.
  if "$conda_bin" tos status >/dev/null 2>&1; then
    return 0
  fi

  say "Conda ToS may need acceptance for non-interactive installs."
  say "Attempting to accept ToS for required channels (user-level)..."

  "$conda_bin" tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
  "$conda_bin" tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true
}

# ---------------- interactive make target selection ----------------
typeset -a TARGETS
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

function needs_env() {
  case "$1" in
    timing|check|sky130_fd_sc_*) return 0 ;;
    *) return 1 ;;
  esac
}

typeset -a SELECTED_TARGETS
SELECTED_TARGETS=()

function select_targets_menu() {
  local choice=""
  say ""
  say "Select what to run with make:"
  say "  1) One target"
  say "  2) Multiple targets"
  say "  3) All targets"
  say "  4) Just submodules (fastest / recommended first)"
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

function run_selected_targets() {
  local repo="$1" t
  say ""
  say "Selected targets:"
  for t in "${SELECTED_TARGETS[@]}"; do say "  - $t"; done
  say ""

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

  # If the repo-installed conda exists, accept ToS before running make env
  local conda_bin="${repo}/env/conda/bin/conda"
  conda_accept_tos_if_needed "$conda_bin"

  make env
fi

    for t in "${SELECTED_TARGETS[@]}"; do
      say ""
      say "== Running: make $t =="
      make "$t"
    done
  )
}

# ---------------- persist exports to ~/.zshrc ----------------
function persist_exports_to_zshrc() {
  local zshrc="${HOME}/.zshrc"
  local begin="# >>> SKY130 PDK ENV >>>"
  local end="# <<< SKY130 PDK ENV <<<"

  local block
  block=$(cat <<EOF
$begin
# Added by install_skywater_pdks_nosudo.zsh
export PDK_ROOT="$PDK_ROOT"
export SKYWATERPDK="$SKYWATERPDK"
export SKYWATER_PDK_REPO="$SKYWATER_PDK_REPO"
$end
EOF
)

  say ""
  say "Persist exports to $zshrc ?"
  say "  PDK_ROOT=$PDK_ROOT"
  say "  SKYWATERPDK=$SKYWATERPDK"
  say "  SKYWATER_PDK_REPO=$SKYWATER_PDK_REPO"
  say ""
  if ! ask_yn "Append/update ~/.zshrc block?" "y"; then
    say "Skipping ~/.zshrc update."
    return 0
  fi

  if [[ -f "$zshrc" ]] && grep -qF "$begin" "$zshrc"; then
    say "Updating existing block in ~/.zshrc ..."
    awk -v begin="$begin" -v end="$end" -v newblock="$block" '
      BEGIN { inblock=0 }
      $0==begin { print newblock; inblock=1; next }
      $0==end   { inblock=0; next }
      inblock==0 { print }
    ' "$zshrc" > "${zshrc}.tmp.$$"
    mv -f "${zshrc}.tmp.$$" "$zshrc"
  else
    say "Appending new block to ~/.zshrc ..."
    printf "\n%s\n" "$block" >> "$zshrc"
  fi

  say "Done. To apply now:"
  say "  source ~/.zshrc"
}

# ---------------- main ----------------
OS="$(detect_os)"
say "SkyWater PDK installer/builder (no sudo)"
say "OS detected: $OS"
say ""
say "Current working directory:"
say "  $(pwd)"
say ""

if ! check_deps; then
  die "Missing dependencies. Need: git make python3 tcsh find grep sed awk"
fi

PDK_ROOT_DEFAULT="${PDK_ROOT:-${HOME}/pdks}"
PDK_ROOT="$(ask "Where should PDK_ROOT be installed?" "$PDK_ROOT_DEFAULT")"
PDK_ROOT="${PDK_ROOT/#\~/${HOME}}"
[[ -z "$PDK_ROOT" ]] && die "PDK_ROOT cannot be empty."
export PDK_ROOT

if [[ ! -d "$PDK_ROOT" ]]; then
  ask_yn "Create directory $PDK_ROOT?" "y" || die "Cannot proceed."
  mkdir -p "$PDK_ROOT"
fi

REPO_URL_DEFAULT="https://github.com/google/skywater-pdk.git"
REPO_URL="$(ask "SkyWater PDK git URL" "$REPO_URL_DEFAULT")"

WORKDIR_DEFAULT="${SKYWATERPDK:-${SKYWATER_PDK_REPO:-${PDK_ROOT}/skywater-pdk}}"
WORKDIR="$(ask "Where should the repo be cloned/built?" "$WORKDIR_DEFAULT")"
WORKDIR="${WORKDIR/#\~/${HOME}}"

export SKYWATERPDK="$WORKDIR"
export SKYWATER_PDK_REPO="$WORKDIR"

say ""
MODE="full"
if [[ -d "$WORKDIR/.git" ]]; then
  say "Repo already exists at:"
  say "  $WORKDIR"
  say ""
  say "Choose mode:"
  say "  1) Full: update repo + submodules + run selected make targets"
  say "  2) Make-only: skip all git/submodule work, just run selected make targets"
  say ""
  m="$(ask "Choice" "2")"
  case "$m" in
    1) MODE="full" ;;
    2) MODE="make" ;;
    *) die "Unknown choice: $m" ;;
  esac
else
  MODE="full"
fi

if [[ "$MODE" == "full" ]]; then
  say ""
  if [[ -d "$WORKDIR/.git" ]]; then
    if ask_yn "Update repo (git pull --rebase)?" "y"; then
      ( cd "$WORKDIR" && git pull --rebase )
    else
      say "Keeping existing repo state."
    fi
  else
    say "Cloning repository..."
    mkdir -p "$(dirname "$WORKDIR")"
    git clone "$REPO_URL" "$WORKDIR"
  fi

  set_git_https_rewrites
  submodules_two_phase_update "$WORKDIR"
else
  say ""
  say "Make-only mode: skipping git/submodule actions."
fi

select_targets_menu
run_selected_targets "$WORKDIR"

persist_exports_to_zshrc

say ""
say "Done."
say "Exports for this session:"
say "  PDK_ROOT=$PDK_ROOT"
say "  SKYWATERPDK=$SKYWATERPDK"
say "  SKYWATER_PDK_REPO=$SKYWATER_PDK_REPO"

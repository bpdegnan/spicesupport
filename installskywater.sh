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
# - Uses system EDA tools when present:
#     * yosys/netlistsvg/iverilog already on PATH are removed from
#       environment.yml so conda does not try (and fail) to install them
# - Interactive make target selection:
#     * one / multiple / all / submodules+timing (default)
# - Installs the repo's own python package (scripts/python-skywater-pdk)
#   into the conda env so `make timing` works (fixes
#   ModuleNotFoundError: No module named 'skywater_pdk')
# - Stage 2: builds open_pdks (RTimothyEdwards/open_pdks) to produce the
#   tool-ready sky130A tree (tech LEF, merged LEF, ngspice models) under
#   $PDK_ROOT/share/pdk/sky130A -- google/skywater-pdk alone never makes these
# - Optional persistence to ~/.zshrc / ~/.zprofile:
#     * export SKYWATERPDK=...       (raw foundry checkout, source of truth)
#     * export SKYWATER_PDK_REPO=... (alias)
#     * export PDK_ROOT=...          (open_pdks install prefix)
#     * export PDK_ROOT_SKY130A=$PDK_ROOT/share/pdk/sky130A

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

function make_env_with_tos_retry() {
  local repo="$1"
  local logfile
  logfile="$(mktemp -t skywater-make-env.XXXXXX 2>/dev/null || mktemp /tmp/skywater-make-env.XXXXXX)"

  say "Running: make env (log: $logfile)"
  (
    cd "$repo"
    # tee keeps console output while also saving a log we can grep
    make env 2>&1 | tee "$logfile"
  )
  local rc=$?

  if (( rc == 0 )); then
    rm -f "$logfile" || true
    return 0
  fi

  # If env failed, check if it was the Anaconda ToS gate.
  if grep -q "CondaToSNonInteractiveError" "$logfile"; then
    say ""
    say "Detected CondaToSNonInteractiveError. Accepting ToS and retrying make env..."

    local conda_bin="${repo}/env/conda/bin/conda"
    if [[ ! -x "$conda_bin" ]]; then
      die "Expected conda at $conda_bin but it does not exist (make env may have failed too early)."
    fi

    "$conda_bin" tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main || true
    "$conda_bin" tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r || true

    say "Retry: make env"
    ( cd "$repo" && make env )
    rc=$?
  fi

  rm -f "$logfile" || true
  return $rc
}


# ---------------- conda env vs locally installed tools ----------------
# The skywater-pdk environment.yml asks conda for EDA tools (yosys,
# netlistsvg, iverilog) from the litex-hub channel.  On macOS that channel
# has no netlistsvg at all, and its yosys pins python <3.8 which conflicts
# with the file's python=3.8, so "make env" cannot solve.  If a tool is
# already on PATH, drop it from environment.yml and use the system copy.
typeset -a CONDA_EDA_TOOLS
CONDA_EDA_TOOLS=(yosys netlistsvg iverilog)

function patch_conda_env_for_local_tools() {
  local repo="$1"
  local envfile="$repo/environment.yml"
  [[ -f "$envfile" ]] || return 0

  local -a drop missing
  drop=()
  missing=()
  local t
  for t in "${CONDA_EDA_TOOLS[@]}"; do
    grep -qE "^[[:space:]]*-[[:space:]]*${t}[[:space:]]*$" "$envfile" || continue
    if have "$t"; then
      say "Found system $t at $(command -v "$t"); removing it from environment.yml"
      drop+=("$t")
    else
      missing+=("$t")
    fi
  done

  for t in "${missing[@]}"; do
    say ""
    say "WARNING: '$t' is not installed on this system, and conda may not be"
    say "able to provide it either (it is why 'make env' failed)."
    case "$t" in
      netlistsvg) say "  To install it yourself: npm install -g netlistsvg" ;;
      yosys)      say "  To install it yourself: sudo port install yosys  (or: brew install yosys)" ;;
      iverilog)   say "  To install it yourself: sudo port install iverilog  (or: brew install icarus-verilog)" ;;
    esac
    if ask_yn "Remove '$t' from environment.yml anyway so make env can proceed?" "y"; then
      drop+=("$t")
    fi
  done

  (( ${#drop[@]} > 0 )) || return 0

  # Keep one pristine copy for reference.
  [[ -f "${envfile}.orig" ]] || cp "$envfile" "${envfile}.orig"

  # Only rewrite the file when the content actually changes, otherwise the
  # fresh mtime makes conda.mk re-run "conda env update" on every rerun.
  local tmp="${envfile}.tmp.$$"
  local pattern="${(j:|:)drop}"
  grep -vE "^[[:space:]]*-[[:space:]]*(${pattern})[[:space:]]*$" "$envfile" > "$tmp"
  if cmp -s "$tmp" "$envfile"; then
    rm -f "$tmp"
    say "environment.yml already patched; nothing to do."
  else
    mv -f "$tmp" "$envfile"
    say "Patched $envfile (removed: ${drop[*]})"
  fi
}

# The repo's requirements.txt (pulled in by environment.yml's pip section)
# asks for rst_include, a docs-only tool whose lib-log-utils dependency is
# unresolvable with modern pip (ResolutionImpossible).  Worse, when pip dies
# on it the whole pip section is abandoned, so the skywater_pdk package on
# the next line never installs either.  Drop rst_include; it is only used
# to render .. include:: directives in GitHub README previews.
function patch_requirements_for_pip() {
  local repo="$1"
  local reqfile="$repo/requirements.txt"
  [[ -f "$reqfile" ]] || return 0

  grep -qE '^[[:space:]]*rst_include[[:space:]]*$' "$reqfile" || return 0

  say "Removing rst_include from requirements.txt (docs-only; breaks pip resolution)"
  [[ -f "${reqfile}.orig" ]] || cp "$reqfile" "${reqfile}.orig"

  local tmp="${reqfile}.tmp.$$"
  grep -vE '^[[:space:]]*rst_include[[:space:]]*$' "$reqfile" > "$tmp"
  mv -f "$tmp" "$reqfile"
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
    env|enter|timing|check|sky130_fd_sc_*) return 0 ;;
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
  say "  4) submodules + timing (recommended: compiles the .lib files tools need)"
  say "  5) Just submodules (fast, but leaves timing/ as .lib.json sources only)"
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
      # everything except 'enter', which opens an interactive subshell and
      # would stall an unattended run
      SELECTED_TARGETS=("${(@)TARGETS:#enter}")
      ;;
    4)
      SELECTED_TARGETS=(submodules timing)
      ;;
    5)
      SELECTED_TARGETS=(submodules)
      ;;
    *)
      die "Unknown choice: $choice"
      ;;
  esac
}

# After any timing-producing target, refuse to call the run a success unless
# compiled Liberty files actually exist (fresh installs used to end with only
# .lib.json sources and no error).
function verify_compiled_libs() {
  local repo="$1"
  local -a libs
  libs=( "$repo"/libraries/*/*/timing/*.lib(N) )
  if (( ${#libs[@]} == 0 )); then
    die "No compiled .lib files found under $repo/libraries/*/*/timing/ -- the timing build did not produce Liberty output. Check the make output above."
  fi
  say "Timing check: found ${#libs[@]} compiled .lib file(s) (e.g. ${libs[1]:t})."
}

function ensure_conda_tos_accepted() {
  local conda_bin="$1"
  [[ -x "$conda_bin" ]] || return 1

  # Always attempt acceptance (idempotent). This avoids relying on tos status behavior.
  "$conda_bin" tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main >/dev/null 2>&1 || true
  "$conda_bin" tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r    >/dev/null 2>&1 || true

  return 0
}

function make_env_firewall_safe() {
  local repo="$1"
  local conda_bin="${repo}/env/conda/bin/conda"

  # If conda isn't there yet, run make env once to bootstrap it (it may fail on ToS; that's fine).
  if [[ ! -x "$conda_bin" ]]; then
    say "Bootstrapping conda via: make env (first pass)"
    ( cd "$repo" && make env ) || true
  fi

  # Now conda should exist; if it still doesn't, fail loudly.
  [[ -x "$conda_bin" ]] || die "Conda not found at $conda_bin after bootstrap."

  say "Accepting Anaconda ToS (non-interactive)..."
  ensure_conda_tos_accepted "$conda_bin"

  say "Running: make env (second pass)"
  ( cd "$repo" && make env )

  # make env alone leaves the repo's own python package uninstalled, so any
  # timing target dies with: ModuleNotFoundError: No module named 'skywater_pdk'
  install_skywater_python_pkg "$repo"
}

function install_skywater_python_pkg() {
  local repo="$1"
  local envdir="$repo/env/conda/envs/skywater-pdk-scripts"
  local pip_bin="$envdir/bin/pip"

  [[ -x "$pip_bin" ]] || die "pip not found at $pip_bin (make env did not create the skywater-pdk-scripts env?)"

  if "$pip_bin" show skywater-pdk >/dev/null 2>&1; then
    say "skywater-pdk python package already installed in conda env; skipping pip install."
    return 0
  fi

  say "Installing repo python package into conda env:"
  say "  $pip_bin install -e $repo/scripts/python-skywater-pdk"
  "$pip_bin" install -e "$repo/scripts/python-skywater-pdk"
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
  patch_conda_env_for_local_tools "$repo"
  patch_requirements_for_pip "$repo"
  say "Ensuring environment exists: make env"
  make_env_firewall_safe "$repo"
fi

    for t in "${SELECTED_TARGETS[@]}"; do
      say ""
      say "== Running: make $t =="
      make "$t"
    done
  )

  for t in "${SELECTED_TARGETS[@]}"; do
    case "$t" in
      timing|sky130_fd_sc_*)
        verify_compiled_libs "$repo"
        break
        ;;
    esac
  done
}

# ---------------- stage 2: open_pdks (tech LEF / merged LEF / sky130A) ----------------
# google/skywater-pdk never produces a tech LEF or a merged sky130_fd_sc_hd.lef
# under ANY make target.  Those only come from open_pdks, which stages the
# foundry sources into the tool-ready $PDK_ROOT/share/pdk/sky130A tree that
# yosys/OpenROAD/magic/klayout expect.

OPEN_PDKS_URL="https://github.com/RTimothyEdwards/open_pdks.git"

function check_magic() {
  local magic_bin=""
  if have magic; then
    magic_bin="$(command -v magic)"
  elif [[ -x /opt/local/bin/magic ]]; then
    # MacPorts install that is not on PATH yet
    magic_bin="/opt/local/bin/magic"
    export PATH="/opt/local/bin:$PATH"
    say "Found magic at $magic_bin (added /opt/local/bin to PATH for this run)."
  else
    err "magic is required by open_pdks but was not found on PATH."
    err "Install it first, e.g.:  sudo port install magic   (or: brew install magic)"
    return 1
  fi

  local ver major minor rest
  ver="$("$magic_bin" --version 2>/dev/null | head -n1)" || ver=""
  if [[ -z "$ver" ]]; then
    err "Could not determine magic version from $magic_bin --version."
    return 1
  fi

  major="${ver%%.*}"
  rest="${ver#*.}"
  minor="${rest%%.*}"
  if ! [[ "$major" =~ '^[0-9]+$' && "$minor" =~ '^[0-9]+$' ]]; then
    err "Unrecognized magic version string: '$ver'"
    return 1
  fi
  if (( major < 8 || (major == 8 && minor < 3) )); then
    err "magic $ver is too old for open_pdks; need 8.3 or newer (8.3.660 known good)."
    return 1
  fi
  say "magic $ver at $magic_bin -- OK"
  return 0
}

function cpu_count() {
  if [[ "$OS" == "macos" ]]; then
    sysctl -n hw.ncpu 2>/dev/null || print 4
  else
    nproc 2>/dev/null || print 4
  fi
}

function build_open_pdks() {
  local prefix="$1" skywater_src="$2"
  local src="$prefix/open_pdks"
  local sky130a="$prefix/share/pdk/sky130A"

  say ""
  say "== Stage 2: open_pdks -> $sky130a =="

  if [[ -d "$sky130a" ]]; then
    say "An installed sky130A tree already exists at:"
    say "  $sky130a"
    if ! ask_yn "Rebuild and reinstall open_pdks anyway?" "n"; then
      say "Keeping existing sky130A install."
      return 0
    fi
  fi

  check_magic || die "Cannot build open_pdks without a working magic."

  if [[ -d "$src/.git" ]]; then
    say "Existing open_pdks checkout at $src"
    if ask_yn "Update it (git pull --rebase)?" "n"; then
      ( cd "$src" && git pull --rebase )
    fi
  else
    say "Cloning open_pdks into $src ..."
    mkdir -p "$prefix"
    git clone "$OPEN_PDKS_URL" "$src"
  fi

  local ncpu
  ncpu="$(cpu_count)"

  (
    cd "$src"
    say ""
    say "Configuring open_pdks (prefix: $prefix, sky130 sources: $skywater_src)..."
    say "NOTE: open_pdks expects per-library repos, not the google monorepo layout,"
    say "so it will clone its own library copies into $src/sources/ over HTTPS."
    ./configure --prefix="$prefix" \
                --enable-sky130-pdk="$skywater_src" \
                --disable-gf180mcu-pdk
    say ""
    say "Building open_pdks (-j$ncpu)..."
    make -j"$ncpu"
    say ""
    say "Installing into user-owned prefix (no sudo)..."
    make install
  )
}

# ---------------- post-install verification ----------------
function verify_sky130a_install() {
  local sky="$1" fail=0
  local hd="$sky/libs.ref/sky130_fd_sc_hd"

  say ""
  say "== Post-install verification: $sky =="

  local lib="$hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib"
  if [[ -f "$lib" ]]; then
    say "  OK      $lib"
  else
    say "  MISSING $lib"; fail=1
  fi

  local -a tlefs
  tlefs=( "$hd"/techlef/*.tlef(N) )
  if (( ${#tlefs[@]} > 0 )); then
    say "  OK      $hd/techlef/ (${tlefs[1]:t})"
  else
    say "  MISSING $hd/techlef/ (no *.tlef found)"; fail=1
  fi

  local lef="$hd/lef/sky130_fd_sc_hd.lef"
  if [[ -f "$lef" ]]; then
    say "  OK      $lef"
  else
    say "  MISSING $lef"; fail=1
  fi

  local ng="$sky/libs.tech/ngspice"
  local -a ngfiles
  ngfiles=( "$ng"/*(N) )
  if [[ -d "$ng" ]] && (( ${#ngfiles[@]} > 0 )); then
    say "  OK      $ng/ (spice models present)"
  else
    say "  MISSING $ng/ (no spice models)"; fail=1
  fi

  if (( fail )); then
    err "sky130A verification FAILED -- the PDK is NOT tool-ready."
    err "yosys/OpenROAD/magic/klayout will not find LIB/TLEF/LEF under $sky"
    return 1
  fi
  say ""
  say "All checks passed: sky130A is tool-ready."
  return 0
}

# ---------------- persist exports to ~/.zshrc ----------------
function upsert_block_in_file() {
  local file="$1"
  local begin="# >>> SKY130 PDK ENV >>>"
  local end="# <<< SKY130 PDK ENV <<<"

  local block
  block=$(cat <<EOF
$begin
# Added by installskywater.sh
# Raw foundry checkout (source of truth):
export SKYWATERPDK="$SKYWATERPDK"
export SKYWATER_PDK_REPO="$SKYWATER_PDK_REPO"
# open_pdks install prefix and the tool-ready sky130A tree:
export PDK_ROOT="$PDK_ROOT"
export PDK_ROOT_SKY130A="$PDK_ROOT_SKY130A"
$end
EOF
)

  # Ensure file exists
  [[ -f "$file" ]] || : > "$file"

  # Remove any existing block first.  NOTE: do not pass the multiline
  # replacement through awk -v: BSD awk (macOS) rejects newlines in -v
  # strings, which silently left stale blocks in place on earlier runs.
  if grep -qF "$begin" "$file"; then
    awk -v begin="$begin" -v end="$end" '
      BEGIN { inblock=0 }
      $0==begin { inblock=1; next }
      $0==end   { inblock=0; next }
      inblock==0 { print }
    ' "$file" > "${file}.tmp.$$" && mv -f "${file}.tmp.$$" "$file"
  fi

  # Append the fresh block, with exactly one blank separator line.
  if [[ -s "$file" && -n "$(tail -n 1 "$file")" ]]; then
    print "" >> "$file"
  fi
  printf "%s\n" "$block" >> "$file"
}

function persist_exports() {
  local rc1="${HOME}/.zshrc"
  local rc2="${HOME}/.zprofile"

  say ""
  say "Persist these exports for future shells?"
  say "  SKYWATERPDK=$SKYWATERPDK          (raw foundry checkout)"
  say "  SKYWATER_PDK_REPO=$SKYWATER_PDK_REPO"
  say "  PDK_ROOT=$PDK_ROOT          (open_pdks install prefix)"
  say "  PDK_ROOT_SKY130A=$PDK_ROOT_SKY130A"
  say ""
  say "(Any previous SKY130 PDK ENV block -- including stale paths -- will be replaced.)"
  say ""
  say "Where should I write them?"
  say "  1) ~/.zshrc"
  say "  2) ~/.zprofile"
  say "  3) both"
  say "  4) skip"
  local c
  c="$(ask "Choice" "3")"

  case "$c" in
    1) upsert_block_in_file "$rc1" ;;
    2) upsert_block_in_file "$rc2" ;;
    3) upsert_block_in_file "$rc1"; upsert_block_in_file "$rc2" ;;
    4) say "Skipping persistence." ; return 0 ;;
    *) die "Unknown choice: $c" ;;
  esac

  say "Done. Apply now with:"
  say "  source ~/.zshrc"
  say "  source ~/.zprofile"
}

function print_export_banner() {
  say ""
  say "************************************************************"
  say "***   IMPORTANT: SkyWater PDK environment variables     ***"
  say "************************************************************"
  say ""
  say "The following variables define where the SkyWater PDK lives:"
  say ""
  say "  # raw foundry checkout (source of truth)"
  say "  export SKYWATERPDK=\"$SKYWATERPDK\""
  say "  export SKYWATER_PDK_REPO=\"$SKYWATER_PDK_REPO\""
  say "  # open_pdks install prefix; sky130A tree for downstream flows"
  say "  export PDK_ROOT=\"$PDK_ROOT\""
  say "  export PDK_ROOT_SKY130A=\"$PDK_ROOT_SKY130A\""
  say ""
  say "NOTE:"
  say "  - These exports apply automatically in NEW shells"
  say "    *after* ~/.zshrc and/or ~/.zprofile are sourced."
  say "  - This script CANNOT modify the environment of"
  say "    your current shell when run as ./script.zsh."
  say ""
  say "If you want these variables active RIGHT NOW,"
  say "either run:"
  say ""
  say "  source ~/.zshrc"
  say "  source ~/.zprofile"
  say ""
  say "or copy/paste the exports above into your shell."
  say ""
  say "If you prefer, you may also add them by hand to"
  say "  ~/.zshrc  (interactive shells)"
  say "  ~/.zprofile (login shells, macOS Terminal/iTerm)"
  say ""
  say "************************************************************"
  say ""
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

# Ignore inherited env vars that point at directories which no longer exist
# (e.g. a stale export block from an earlier run of this script).
if [[ -n "${PDK_ROOT:-}" && ! -d "${PDK_ROOT}" ]]; then
  say "NOTE: inherited PDK_ROOT='$PDK_ROOT' does not exist (stale export?); ignoring it."
  unset PDK_ROOT
fi

PDK_ROOT_DEFAULT="${PDK_ROOT:-${HOME}/pdks}"
say "PDK_ROOT is the open_pdks install prefix; the tool-ready tree will land at"
say "  \$PDK_ROOT/share/pdk/sky130A"
PDK_ROOT="$(ask "Where should PDK_ROOT be?" "$PDK_ROOT_DEFAULT")"
PDK_ROOT="${PDK_ROOT/#\~/${HOME}}"
[[ -z "$PDK_ROOT" ]] && die "PDK_ROOT cannot be empty."
[[ "$PDK_ROOT" == /* ]] || die "PDK_ROOT must be an absolute path (got: $PDK_ROOT)"
export PDK_ROOT
export PDK_ROOT_SKY130A="${PDK_ROOT}/share/pdk/sky130A"

if [[ ! -d "$PDK_ROOT" ]]; then
  ask_yn "Create directory $PDK_ROOT?" "y" || die "Cannot proceed."
  mkdir -p "$PDK_ROOT"
fi

REPO_URL_DEFAULT="https://github.com/google/skywater-pdk.git"
REPO_URL="$(ask "SkyWater PDK git URL" "$REPO_URL_DEFAULT")"

WORKDIR_DEFAULT=""
for cand in "${SKYWATERPDK:-}" "${SKYWATER_PDK_REPO:-}"; do
  [[ -n "$cand" ]] || continue
  if [[ -d "$cand/.git" ]]; then
    WORKDIR_DEFAULT="$cand"
    break
  fi
  say "NOTE: inherited repo path '$cand' is not a git checkout (stale export?); ignoring it."
done
[[ -z "$WORKDIR_DEFAULT" ]] && WORKDIR_DEFAULT="${PDK_ROOT}/skywater-pdk"

WORKDIR="$(ask "Where should the foundry repo be cloned/built?" "$WORKDIR_DEFAULT")"
WORKDIR="${WORKDIR/#\~/${HOME}}"
[[ "$WORKDIR" == /* ]] || die "Repo path must be an absolute path (got: $WORKDIR)"

export SKYWATERPDK="$WORKDIR"
export SKYWATER_PDK_REPO="$WORKDIR"

persist_exports

print_export_banner

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

# ---- stage 2: open_pdks (tech LEF / merged LEF / sky130A tree) ----
say ""
say "Stage 2 stages the foundry sources into the tool-ready sky130A tree"
say "(tech LEF, merged sky130_fd_sc_hd.lef, ngspice models). Without it,"
say "yosys/OpenROAD/magic/klayout cannot consume this PDK."
if ask_yn "Run stage 2: build and install open_pdks?" "y"; then
  build_open_pdks "$PDK_ROOT" "$SKYWATERPDK"
else
  say "Skipping open_pdks stage."
fi

VERIFY_RC=0
verify_sky130a_install "$PDK_ROOT_SKY130A" || VERIFY_RC=1

say ""
say "Done."
say "Exports for this session:"
say "  SKYWATERPDK=$SKYWATERPDK          (raw foundry checkout)"
say "  SKYWATER_PDK_REPO=$SKYWATER_PDK_REPO"
say "  PDK_ROOT=$PDK_ROOT          (open_pdks install prefix)"
say "  PDK_ROOT_SKY130A=$PDK_ROOT_SKY130A"
say ""
say "Downstream flows should point at the sky130A tree, e.g.:"
say "  PDK_ROOT=\$PDK_ROOT_SKY130A ./run_picorv32_flow.sh"

exit $VERIFY_RC

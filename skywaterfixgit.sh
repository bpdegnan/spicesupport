#!/usr/bin/env zsh
# skywaterfixgit.sh
# Force a repo + its submodules to use HTTPS (firewall-friendly).
# Uses, in priority order:
#   1) first CLI arg (repo dir)
#   2) $SKYWATER_PDK_REPO
#   3) $PDK_ROOT/src/skywater-pdk
#
# BSD/macOS clean. No sudo. Does not require you to be in the repo directory.

set -eu

say() { print -r -- "$*"; }
err() { print -r -- "ERROR: $*" >&2; }
die() { err "$@"; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

[[ -n "${ZSH_VERSION:-}" ]] || die "Please run with zsh."

have git || die "git not found in PATH."

ARG_REPO="${1:-}"

# Expand ~ if used
if [[ -n "$ARG_REPO" ]]; then
  ARG_REPO="${ARG_REPO/#\~/${HOME}}"
fi

# Resolve repo dir without requiring CWD
REPO_DIR=""
if [[ -n "$ARG_REPO" ]]; then
  REPO_DIR="$ARG_REPO"
elif [[ -n "${SKYWATER_PDK_REPO:-}" ]]; then
  REPO_DIR="${SKYWATER_PDK_REPO/#\~/${HOME}}"
elif [[ -n "${PDK_ROOT:-}" ]]; then
  REPO_DIR="${PDK_ROOT/#\~/${HOME}}/src/skywater-pdk"
else
  die "No repo directory provided and neither SKYWATER_PDK_REPO nor PDK_ROOT is set."
fi

[[ -d "$REPO_DIR" ]] || die "Not a directory: $REPO_DIR"
[[ -d "$REPO_DIR/.git" ]] || die "Not a git repo (no .git): $REPO_DIR"

say "Repo: $REPO_DIR"
say "PWD : $(cd "$REPO_DIR" && /bin/pwd)"
say ""

if [[ -f "$REPO_DIR/.gitmodules" ]]; then
  say "Current .gitmodules URLs:"
  ( cd "$REPO_DIR" && git config --file .gitmodules --get-regexp '^submodule\..*\.url$' ) || true
  say ""
else
  say "No .gitmodules found (repo may not use submodules)."
  say ""
fi

say "Applying local URL rewrite rules (SSH/git:// -> HTTPS)..."
(
  cd "$REPO_DIR"

  # GitHub SSH -> HTTPS
  git config --local url."https://github.com/".insteadOf "git@github.com:"
  git config --local url."https://github.com/".insteadOf "ssh://git@github.com/"

  # Generic git:// -> https:// (often blocked)
  git config --local url."https://".insteadOf "git://"

  # Sync submodule URLs into local config then the rewrite rules apply
  git submodule sync --recursive || true
)

say "Attempting submodule init/update over HTTPS..."
(
  cd "$REPO_DIR"
  git submodule update --init --recursive
)

say ""
say "Done."
say "Tip: to persist SKYWATER_PDK_REPO in ~/.zshrc:"
say "  export SKYWATER_PDK_REPO=\"$REPO_DIR\""

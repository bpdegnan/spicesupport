#!/usr/bin/env zsh
# netlist checker for BSIM4 portability issues
set -eu

CIR="${1:-}"
if [[ -z "${CIR}" || ! -f "${CIR}" ]]; then
  echo "netlist checker for BSIM4 portability issues"
  print "usage: $0 your.cir" >&2
  exit 2
fi

# explicit paths (ggrep, etc)
AWK="/usr/bin/awk"
GREP="/usr/bin/grep"
SED="/usr/bin/sed"
SORT="/usr/bin/sort"

print "== 1) MOS instances (M-lines) and their referenced model names =="
# Best-effort: extracts model token from single-line MOS records.
# Handles optional 4th node (bulk) and ignores obvious param tokens.
"${AWK}" '
  BEGIN { IGNORECASE=1 }
  /^[[:space:]]*[*;$]/ { next }          # comment lines: *, ;, $
  /^[[:space:]]*[m]/ {
    # Split on whitespace
    n = split($0, a, /[[:space:]]+/)

    # Find the first token after the nodes that does NOT contain "="
    # SPICE MOS format: Mname nd ng ns [nb] model [params...]
    # We don’t perfectly know if nb exists, so we scan:
    # a[2..] until we see something that looks like a model name.
    # Skip tokens that look like node names? Not reliable.
    # Instead: model is usually the first token after 3 or 4 nodes that is not assignment-like.
    #
    # Heuristic:
    # - Token 1 is device name.
    # - Next tokens are nodes until we hit the model token.
    # - Model token typically has no "=" and is not purely numeric.
    #
    # Start scanning at token 5 (M + 3 nodes => model at 5) and also allow token 6 (with bulk node).
    model=""
    for (i=5; i<=n; i++) {
      if (a[i] ~ /=/) continue
      if (a[i] == "") continue
      # stop if we hit a continuation marker "+"
      if (a[i] == "+") continue
      model=a[i]
      break
    }
    if (model != "") print model
  }
' "${CIR}" | "${SORT}" -u | "${SED}" 's/^/  model: /'

print ""
print "== 2) HSPICE-extension instance vs. ngspice =="
# BSD grep supports -E and -i; -n is line numbers.
# This list is intentionally conservative and includes the MUL* style knobs you care about.
PAT='(WNFLAG|MULID0|MULU0|MULUA|MULUB|MULUC|MULRDSW|MULVTH0)[[:space:]]*='
if ! "${GREP}" -nEi "${PAT}" "${CIR}"; then
  print "  (none found)"
fi

print ""
print "== 3) Look for BSIM4 (LEVEL=54) modelcards in this file =="
if ! "${GREP}" -nEi '^[[:space:]]*\.model[[:space:]].*(level[[:space:]]*=[[:space:]]*54|bsim4)' "${CIR}"; then
  print "  (no .model LEVEL=54 lines found — modelcards may be in .include/.lib files)"
fi

print ""
print "== 4) List .include / .lib statements (modelcard sources) =="
if ! "${GREP}" -nEi '^[[:space:]]*\.(include|lib)[[:space:]]+' "${CIR}"; then
  print "  (none found)"
fi

print ""
print "== 5) Quick check for WNFLAG usage (binning behavior differs) =="
if ! "${GREP}" -nEi 'WNFLAG[[:space:]]*=' "${CIR}"; then
  print "  (no WNFLAG found)"
fi

print ""
print "== 6) Optional: show any .option lines that can affect MOS behavior =="
if ! "${GREP}" -nEi '^[[:space:]]*\.option[[:space:]]+' "${CIR}"; then
  print "  (no .option lines found in this file)"
fi

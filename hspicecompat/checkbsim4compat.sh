#!/usr/bin/env zsh
set -euo pipefail

CIR="${1:-}"
if [[ -z "${CIR}" || ! -f "${CIR}" ]]; then
  echo "usage: $0 your.cir"
  exit 2
fi

echo "== 1) MOS instances (M-lines) and their referenced model names =="
#  M-device lines (ignores comment lines)
awk '
  BEGIN{IGNORECASE=1}
  /^[[:space:]]*[*;$]/ {next}
  /^[[:space:]]*[m]/ {
    # tokenize; spice allows + continuation, so this is best-effort for single-line M records
    # format: Mname nd ng ns [nb] model ...
    n=split($0,a,/[[:space:]]+/)
    # model name usually a[5] or a[6] depending on whether nb is present; best-effort:
    # if token 5 looks like an assignment (L=,W=...), shift
    model=a[5]
    if (model ~ /[=:]/) model=a[6]
    if (model != "" && model !~ /[=:]/) print model
  }
' "$CIR" | sort -u | sed 's/^/  model: /'

echo
echo "== 2) HSPICE-only / HSPICE-extension instance args to flag (common culprits) =="
# HSPICE BSIM4 instance syntax that differs from ngspice
# If these appear in your circuit, ngspice may ignore them or behave differently. 
PAT='(WNFLAG|MULID0|MULU0|DELNFCT|DELVTO|DELVT0|DELK1|DELTOX)\s*='
grep -nEi "$PAT" "$CIR" || echo "  (none found)"

echo
echo "== 3) Look for BSIM4 level/version selectors in modelcards =="
# Helps you spot LEVEL=54 and VERSION mismatches
grep -nEi '^[[:space:]]*\.model[[:space:]].*(level[[:space:]]*=[[:space:]]*(14|54)|bsim4|version[[:space:]]*=)' "$CIR" || \
  echo "  (no .model lines found in this file — models may be in .include files)"

echo
echo "== 4) List .include / .lib statements (where the modelcards probably live) =="
grep -nEi '^[[:space:]]*\.(include|lib)\b' "$CIR" || echo "  (none found)"

echo
echo "== 5) Quick sanity: flag WNFLAG usage (binning behavior can differ by simulator) =="
grep -nEi 'WNFLAG\s*=' "$CIR" || echo "  (no WNFLAG found)"

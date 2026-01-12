#!/usr/bin/env zsh
# Run HSPICE and ngspice PFET drain sweep and compare results
# Usage: ./runme.sh [hspice|ngspice|both|plot]

set -e

NGSPICE_BIN="ngspice"
HSPICE_BIN="hspice"
PYTHON_BIN="python3"

MODE="${1:-both}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error()  { echo -e "${RED}[ERROR]${NC} $1"; }
echo_config() { echo -e "${CYAN}[CONFIG]${NC} $1"; }

show_config() {
    echo_config "NGSPICE_BIN = $NGSPICE_BIN"
    echo_config "HSPICE_BIN  = $HSPICE_BIN"
    echo_config "PYTHON_BIN  = $PYTHON_BIN"
    echo_config "SPICE_LIB   = ${SPICE_LIB:-(not set)}"
    echo ""
}

check_hspice() {
    if command -v "$HSPICE_BIN" &> /dev/null || [[ -x "$HSPICE_BIN" ]]; then
        return 0
    fi
    echo_warn "HSPICE not found: $HSPICE_BIN"
    return 1
}

check_ngspice() {
    if command -v "$NGSPICE_BIN" &> /dev/null || [[ -x "$NGSPICE_BIN" ]]; then
        echo_status "ngspice version:"
        "$NGSPICE_BIN" --version 2>&1 | head -3 | sed 's/^/    /'
        return 0
    fi
    echo_warn "ngspice not found: $NGSPICE_BIN"
    return 1
}

check_spice_lib() {
    if [[ -z "$SPICE_LIB" ]]; then
        echo_error "SPICE_LIB environment variable is not set"
        return 1
    fi
    if [[ ! -d "$SPICE_LIB" ]]; then
        echo_error "SPICE_LIB directory does not exist: $SPICE_LIB"
        return 1
    fi
    if [[ ! -f "$SPICE_LIB/sky130.lib.spice" ]]; then
        echo_error "sky130.lib.spice not found in: $SPICE_LIB"
        return 1
    fi
    echo_status "SPICE_LIB validated: $SPICE_LIB"
    return 0
}

run_hspice() {
    echo_status "Running HSPICE PFET drain sweep..."
    check_hspice || return 1
    
    "$HSPICE_BIN" pfet_drainsweephspice.cir > pfet_drainsweephspice.out 2>&1
    
    if grep -q "job concluded" pfet_drainsweephspice.out; then
        echo_status "HSPICE completed successfully"
        "$PYTHON_BIN" hspice_dc_to_csv.py pfet_drainsweephspice.out pfet_drainsweep_hspice.csv
        echo_status "Created pfet_drainsweep_hspice.csv"
    else
        echo_error "HSPICE failed - check pfet_drainsweephspice.out"
        tail -20 pfet_drainsweephspice.out
        return 1
    fi
}

run_ngspice() {
    echo_status "Running ngspice PFET drain sweep..."
    check_ngspice || return 1
    check_spice_lib || return 1
    
    "$NGSPICE_BIN" -b pfet_drainsweepngspice.cir > pfet_drainsweepngspice.out 2>&1
    
    if grep -q "Done" pfet_drainsweepngspice.out && [[ -f "pfet_drainsweep_ngspice.csv" ]]; then
        echo_status "ngspice completed successfully"
        echo_status "Created pfet_drainsweep_ngspice.csv"
    else
        echo_error "ngspice failed - check pfet_drainsweepngspice.out"
        cat pfet_drainsweepngspice.out
        return 1
    fi
}

plot_results() {
    echo_status "Generating plot..."
    
    PLOT_ARGS=()
    [[ -f "pfet_drainsweep_hspice.csv" ]] && PLOT_ARGS+=(--hspice pfet_drainsweep_hspice.csv) && echo_status "  Including HSPICE data"
    [[ -f "pfet_drainsweep_ngspice.csv" ]] && PLOT_ARGS+=(--ngspice pfet_drainsweep_ngspice.csv) && echo_status "  Including ngspice data"
    
    if [[ ${#PLOT_ARGS[@]} -gt 0 ]]; then
        "$PYTHON_BIN" plot_pfet_drainsweep_comparison.py "${PLOT_ARGS[@]}" -o pfet_drainsweep_comparison.png
        echo_status "Created pfet_drainsweep_comparison.png"
    else
        echo_warn "No data files found"
    fi
}

show_config

case "$MODE" in
    hspice)  run_hspice; plot_results ;;
    ngspice) run_ngspice; plot_results ;;
    both)
        HSPICE_OK=0; NGSPICE_OK=0
        run_hspice && HSPICE_OK=1 || true
        run_ngspice && NGSPICE_OK=1 || true
        [[ $HSPICE_OK -eq 0 && $NGSPICE_OK -eq 0 ]] && echo_error "Both failed" && exit 1
        plot_results ;;
    plot) plot_results ;;
    *) echo "Usage: $0 [hspice|ngspice|both|plot]"; exit 1 ;;
esac

echo_status "Done!"

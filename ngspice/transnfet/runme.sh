#!/usr/bin/env zsh
# Run nfettrans and save output with hostname suffix
# Usage: ./runme.sh [run|plot|clean]
#   run   - run simulation (default)
#   plot  - plot all hostname CSV files for comparison
#   clean - remove generated files

set -e

NGSPICE_BIN="ngspice"
PYTHON_BIN="python3"
HOSTNAME=$(hostname -s)

MODE="${1:-run}"

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
    echo_config "HOSTNAME    = $HOSTNAME"
    echo_config "PYTHON_BIN  = $PYTHON_BIN"
    echo_config "SPICE_LIB   = ${SPICE_LIB:-(not set)}"
    echo ""
}

check_ngspice() {
    if command -v "$NGSPICE_BIN" &> /dev/null || [[ -x "$NGSPICE_BIN" ]]; then
        echo_status "ngspice version:"
        "$NGSPICE_BIN" --version 2>&1 | head -3 | sed 's/^/    /'
        return 0
    fi
    echo_error "ngspice not found: $NGSPICE_BIN"
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

run_simulation() {
    echo_status "Running nfettrans on $HOSTNAME..."
    check_ngspice || return 1
    check_spice_lib || return 1
    
    # Run ngspice
    "$NGSPICE_BIN" -b nfettrans.cir > nfettrans.out 2>&1
    
    if grep -q "Done" nfettrans.out && [[ -f "nfettrans.csv" ]]; then
        # Rename output with hostname
        mv nfettrans.csv "nfettrans.${HOSTNAME}.csv"
        echo_status "Created nfettrans.${HOSTNAME}.csv"
    else
        echo_error "Simulation failed - check nfettrans.out"
        cat nfettrans.out
        return 1
    fi
}

plot_comparison() {
    echo_status "Plotting comparison of all hostname CSV files..."
    
    # Find all hostname CSV files
    CSV_FILES=(nfettrans.*.csv(N))
    
    if [[ ${#CSV_FILES[@]} -eq 0 ]]; then
        echo_error "No CSV files found matching nfettrans.*.csv"
        return 1
    fi
    
    echo_status "Found ${#CSV_FILES[@]} CSV file(s):"
    for f in "${CSV_FILES[@]}"; do
        echo "    $f"
    done
    
    "$PYTHON_BIN" plot_transient_comparison.py "${CSV_FILES[@]}" -o nfettrans_comparison.png
    echo_status "Created nfettrans_comparison.png"
}

clean_files() {
    echo_status "Cleaning generated files..."
    rm -f nfettrans.*.csv nfettrans.out nfettrans_comparison.png
    echo_status "Done"
}

show_config

case "$MODE" in
    run)
        run_simulation
        ;;
    plot)
        plot_comparison
        ;;
    clean)
        clean_files
        ;;
    *)
        echo "Usage: $0 [run|plot|clean]"
        echo ""
        echo "Options:"
        echo "  run   - Run simulation and save as nfettrans.HOSTNAME.csv (default)"
        echo "  plot  - Plot comparison of all nfettrans.*.csv files"
        echo "  clean - Remove generated files"
        exit 1
        ;;
esac

echo_status "Done!"

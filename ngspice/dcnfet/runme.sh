#!/usr/bin/env zsh
# Run nfetdc and save output with hostname suffix
# Usage: ./runme.sh [run|plot|clean] [--note "description"]
#   run   - run simulation (default)
#   plot  - plot all hostname CSV files for comparison
#   clean - remove generated files
#   --note "text" - add a note to the CSV metadata

set -e

NGSPICE_BIN="ngspice"
PYTHON_BIN="python3"
HOSTNAME=$(hostname -s)

CIR_FILE="nfetdc.cir"
CSV_BASE="nfetdc"
PLOT_SCRIPT="plot_dc_currents.py"

MODE=""
NOTE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --note)
            NOTE="$2"
            shift 2
            ;;
        run|plot|clean)
            MODE="$1"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

MODE="${MODE:-run}"

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
    echo_config "CIR_FILE    = $CIR_FILE"
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
    echo_status "Running DC simulation on $HOSTNAME..."
    check_ngspice || return 1
    check_spice_lib || return 1
    
    if [[ ! -f "$CIR_FILE" ]]; then
        echo_error "Circuit file not found: $CIR_FILE"
        return 1
    fi
    
    # Extract metadata
    NGSPICE_VERSION=$("$NGSPICE_BIN" --version 2>&1 | head -1)
    GMIN=$(grep -i '\.option.*gmin' "$CIR_FILE" | sed -E 's/.*gmin[[:space:]]*=[[:space:]]*([^ ]+).*/\1/i' || echo "default")
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Output filename includes gmin
    OUTFILE="${CSV_BASE}.gmin${GMIN}.${HOSTNAME}.csv"
    
    # Run ngspice
    "$NGSPICE_BIN" -b "$CIR_FILE" > "${CSV_BASE}.out" 2>&1
    
    if grep -q "Done" "${CSV_BASE}.out" && [[ -f "${CSV_BASE}.csv" ]]; then
        # Create output with metadata header
        {
            echo "# hostname: $HOSTNAME"
            echo "# ngspice: $NGSPICE_VERSION"
            echo "# gmin: $GMIN"
            echo "# source: $CIR_FILE"
            echo "# timestamp: $TIMESTAMP"
            [[ -n "$NOTE" ]] && echo "# note: $NOTE"
            # Convert whitespace to comma (portable for macOS/Linux)
            # Strip leading/trailing whitespace, then convert remaining whitespace to commas
            sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/[[:space:]]+/,/g' "${CSV_BASE}.csv"
        } > "$OUTFILE"
        rm "${CSV_BASE}.csv"
        echo_status "Created $OUTFILE"
        
        # Show metadata
        echo_status "Metadata:"
        grep '^#' "$OUTFILE" | sed 's/^/    /'
        
        # Show column headers
        echo_status "CSV columns:"
        grep -v '^#' "$OUTFILE" | head -1 | sed 's/^/    /'
    else
        echo_error "Simulation failed - check ${CSV_BASE}.out"
        cat "${CSV_BASE}.out"
        return 1
    fi
}

plot_comparison() {
    echo_status "Plotting comparison of DC CSV files..."
    
    # Find all CSV files
    CSV_FILES=(${CSV_BASE}.*.csv(N))
    
    if [[ ${#CSV_FILES[@]} -eq 0 ]]; then
        echo_error "No CSV files found matching ${CSV_BASE}.*.csv"
        return 1
    fi
    
    echo_status "Found ${#CSV_FILES[@]} CSV file(s):"
    for f in "${CSV_FILES[@]}"; do
        echo "    $f"
    done
    
    if [[ ! -f "$PLOT_SCRIPT" ]]; then
        echo_error "Plot script not found: $PLOT_SCRIPT"
        return 1
    fi
    
    # Let Python auto-generate output filename from gmin
    "$PYTHON_BIN" "$PLOT_SCRIPT" "${CSV_FILES[@]}"
}

clean_files() {
    echo_status "Cleaning generated files..."
    rm -f ${CSV_BASE}.*.csv ${CSV_BASE}.out ${CSV_BASE}.*.png
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
        echo "Usage: $0 [run|plot|clean] [--note \"description\"]"
        echo ""
        echo "Commands:"
        echo "  run   - Run DC simulation and save as nfetdc.gminXX.HOSTNAME.csv"
        echo "  plot  - Plot comparison of all nfetdc.*.csv files"
        echo "  clean - Remove generated files"
        echo ""
        echo "Options:"
        echo "  --note \"text\"  - Add a note to the CSV metadata"
        exit 1
        ;;
esac

echo_status "Done!"

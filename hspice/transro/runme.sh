#!/usr/bin/env zsh
# Run HSPICE ring oscillator simulation
# Usage: ./runme.sh [run|plot|clean]

set -e

HSPICE_BIN="hspice"
PYTHON_BIN="python3"
HOSTNAME=$(hostname -s)

CIR_FILE="ro20nand2.cir"
CSV_BASE="ro20"
PLOT_SCRIPT="plot_ro.py"
PARSER_SCRIPT="hspice_trans_to_csv.py"

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
    echo_config "HSPICE_BIN  = $HSPICE_BIN"
    echo_config "HOSTNAME    = $HOSTNAME"
    echo_config "CIR_FILE    = $CIR_FILE"
    echo ""
}

check_hspice() {
    if command -v "$HSPICE_BIN" &> /dev/null || [[ -x "$HSPICE_BIN" ]]; then
        echo_status "HSPICE found: $HSPICE_BIN"
        return 0
    fi
    echo_error "HSPICE not found: $HSPICE_BIN"
    return 1
}

run_simulation() {
    echo_status "Running HSPICE ring oscillator simulation..."
    check_hspice || return 1
    
    if [[ ! -f "$CIR_FILE" ]]; then
        echo_error "Circuit file not found: $CIR_FILE"
        return 1
    fi
    
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    OUTFILE="${CSV_BASE}.${HOSTNAME}.csv"
    
    # Run HSPICE
    "$HSPICE_BIN" "$CIR_FILE" > "${CSV_BASE}.out" 2>&1
    
    if grep -q "job concluded" "${CSV_BASE}.out"; then
        echo_status "HSPICE completed successfully"
        
        # Show measurements
        echo_status "Measurements:"
        grep -E "^\s*(freq|period|i_vdd|i_vss|power)" "${CSV_BASE}.out" | sed 's/^/    /'
        
        # Parse HSPICE output to CSV
        if [[ -f "$PARSER_SCRIPT" ]]; then
            "$PYTHON_BIN" "$PARSER_SCRIPT" "${CSV_BASE}.out" "${CSV_BASE}.tmp.csv"
            
            # Add metadata header
            {
                echo "# hostname: $HOSTNAME"
                echo "# simulator: hspice"
                echo "# source: $CIR_FILE"
                echo "# timestamp: $TIMESTAMP"
                cat "${CSV_BASE}.tmp.csv"
            } > "$OUTFILE"
            rm "${CSV_BASE}.tmp.csv"
            
            echo_status "Created $OUTFILE"
        else
            echo_warn "Parser script not found: $PARSER_SCRIPT"
        fi
    else
        echo_error "HSPICE failed - check ${CSV_BASE}.out"
        tail -30 "${CSV_BASE}.out"
        return 1
    fi
}

plot_results() {
    echo_status "Plotting ring oscillator results..."
    
    if [[ ! -f "$PLOT_SCRIPT" ]]; then
        echo_error "Plot script not found: $PLOT_SCRIPT"
        return 1
    fi
    
    CSV_FILES=(${CSV_BASE}.*.csv(N))
    if [[ ${#CSV_FILES[@]} -eq 0 ]]; then
        echo_error "No CSV files found"
        return 1
    fi
    
    "$PYTHON_BIN" "$PLOT_SCRIPT" "${CSV_FILES[@]}"
}

clean_files() {
    echo_status "Cleaning generated files..."
    rm -f ${CSV_BASE}.*.csv ${CSV_BASE}.out ${CSV_BASE}.*.png
    rm -f *.st0 *.ic0 *.pa0 *.tr0 *.sw0 *.mt0 *.ma0
    echo_status "Done"
}

show_config

case "$MODE" in
    run)   run_simulation ;;
    plot)  plot_results ;;
    clean) clean_files ;;
    *)
        echo "Usage: $0 [run|plot|clean]"
        exit 1
        ;;
esac

echo_status "Done!"

#!/usr/bin/env zsh
# Run HSPICE nfettrans and save output with hostname suffix
# Usage: ./runme.sh [run|plot|clean] [--note "description"]
#   run   - run simulation (default)
#   plot  - plot all hostname CSV files for comparison
#   clean - remove generated files
#   --note "text" - add a note to the CSV metadata

set -e

HSPICE_BIN="hspice"
PYTHON_BIN="python3"
HOSTNAME=$(hostname -s)

CIR_FILE="nfettrans.cir"
CSV_BASE="nfettrans"
PLOT_SCRIPT="plot_transient_currents.py"
PARSER_SCRIPT="hspice_trans_to_csv.py"

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
    echo_config "HSPICE_BIN  = $HSPICE_BIN"
    echo_config "HOSTNAME    = $HOSTNAME"
    echo_config "PYTHON_BIN  = $PYTHON_BIN"
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
    echo_status "Running HSPICE transient simulation on $HOSTNAME..."
    check_hspice || return 1
    
    if [[ ! -f "$CIR_FILE" ]]; then
        echo_error "Circuit file not found: $CIR_FILE"
        return 1
    fi
    
    # Extract metadata from circuit file
    # GMIN=$(grep -i '\.option.*gmin' "$CIR_FILE" | sed -E 's/.*gmin[[:space:]]*=[[:space:]]*([^ ]+).*/\1/i' || echo "default")
    GMIN=$(grep -oiE '\bgmin\s*=\s*[0-9e.+-]+' "$CIR_FILE" | head -1 | sed -E 's/.*=\s*//' || echo "default")
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    # Output filename includes gmin
    OUTFILE="${CSV_BASE}.gmin${GMIN}.${HOSTNAME}.csv"
    
    # Run HSPICE
    "$HSPICE_BIN" "$CIR_FILE" > "${CSV_BASE}.out" 2>&1
    
    if grep -q "job concluded" "${CSV_BASE}.out"; then
        echo_status "HSPICE completed successfully"
        
        # Parse HSPICE output to CSV
        "$PYTHON_BIN" "$PARSER_SCRIPT" "${CSV_BASE}.out" "${CSV_BASE}.tmp.csv"
        
        # Add metadata header
        {
            echo "# hostname: $HOSTNAME"
            echo "# simulator: hspice"
            echo "# gmin: $GMIN"
            echo "# source: $CIR_FILE"
            echo "# timestamp: $TIMESTAMP"
            [[ -n "$NOTE" ]] && echo "# note: $NOTE"
            cat "${CSV_BASE}.tmp.csv"
        } > "$OUTFILE"
        rm "${CSV_BASE}.tmp.csv"
        
        echo_status "Created $OUTFILE"
        
        # Show metadata
        echo_status "Metadata:"
        grep '^#' "$OUTFILE" | sed 's/^/    /'
        
        # Show column headers
        echo_status "CSV columns:"
        grep -v '^#' "$OUTFILE" | head -1 | sed 's/^/    /'
    else
        echo_error "HSPICE failed - check ${CSV_BASE}.out"
        tail -30 "${CSV_BASE}.out"
        return 1
    fi
}

plot_comparison() {
    echo_status "Plotting comparison of HSPICE transient CSV files..."
    
    # Find all CSV files
    CSV_FILES=(${CSV_BASE}.*.csv(N))
    
    if [[ ${#CSV_FILES[@]} -eq 0 ]]; then
        echo_error "No CSV files found matching ${CSV_BASE}.*.csv"
        return 1
    fi
    
    echo_status "Available CSV files:"
    for i in {1..${#CSV_FILES[@]}}; do
        echo "    $i) ${CSV_FILES[$i]}"
    done
    echo "    a) All files"
    echo ""
    
    echo -n "Select files to plot (e.g., 1 2 3 or 'a' for all): "
    read selection
    
    # Build list of selected files
    SELECTED_FILES=()
    
    if [[ "$selection" == "a" || "$selection" == "A" ]]; then
        SELECTED_FILES=("${CSV_FILES[@]}")
    else
        for sel in ${=selection}; do
            if [[ "$sel" =~ ^[0-9]+$ ]] && [[ "$sel" -ge 1 ]] && [[ "$sel" -le ${#CSV_FILES[@]} ]]; then
                SELECTED_FILES+=("${CSV_FILES[$sel]}")
            else
                echo_warn "Invalid selection: $sel (skipping)"
            fi
        done
    fi
    
    if [[ ${#SELECTED_FILES[@]} -eq 0 ]]; then
        echo_error "No valid files selected"
        return 1
    fi
    
    echo ""
    echo_status "Plotting ${#SELECTED_FILES[@]} file(s):"
    for f in "${SELECTED_FILES[@]}"; do
        echo "    $f"
    done
    
    if [[ ! -f "$PLOT_SCRIPT" ]]; then
        echo_error "Plot script not found: $PLOT_SCRIPT"
        return 1
    fi
    
    "$PYTHON_BIN" "$PLOT_SCRIPT" "${SELECTED_FILES[@]}"
}

clean_files() {
    echo_status "Cleaning generated files..."
    rm -f ${CSV_BASE}.*.csv ${CSV_BASE}.out ${CSV_BASE}.*.png
    rm -f *.st0 *.ic0 *.pa0 *.tr0 *.sw0 *.mt0 *.ma0
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
        echo "  run   - Run HSPICE transient simulation and save as nfettrans.gminXX.HOSTNAME.csv"
        echo "  plot  - Plot comparison of all nfettrans.*.csv files"
        echo "  clean - Remove generated files"
        echo ""
        echo "Options:"
        echo "  --note \"text\"  - Add a note to the CSV metadata"
        exit 1
        ;;
esac

echo_status "Done!"

#!/usr/bin/env zsh
# Run ngspice ring oscillator simulation
# Usage: ./runme.sh [run|plot|clean]

set -e

NGSPICE_BIN="ngspice"
PYTHON_BIN="python3"
HOSTNAME=$(hostname -s)

CIR_FILE="ro20nand2.cir"
CSV_BASE="ro20"
PLOT_SCRIPT="plot_ro.py"

# Device abstraction - change these to swap device types
NMOS_DEVICE="sky130_fd_pr__nfet_01v8"
PMOS_DEVICE="sky130_fd_pr__pfet_01v8"

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
    echo_config "CIR_FILE    = $CIR_FILE"
    echo_config "NMOS_DEVICE = $NMOS_DEVICE"
    echo_config "PMOS_DEVICE = $PMOS_DEVICE"
    echo_config "SPICE_LIB   = ${SPICE_LIB:-(not set)}"
    echo ""
}

check_ngspice() {
    if command -v "$NGSPICE_BIN" &> /dev/null; then
        echo_status "ngspice found: $NGSPICE_BIN"
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
    if [[ ! -f "$SPICE_LIB/sky130.lib.spice" ]]; then
        echo_error "sky130.lib.spice not found in: $SPICE_LIB"
        return 1
    fi
    return 0
}

run_simulation() {
    echo_status "Running ngspice ring oscillator simulation..."
    check_ngspice || return 1
    check_spice_lib || return 1
    
    if [[ ! -f "$CIR_FILE" ]]; then
        echo_error "Circuit file not found: $CIR_FILE"
        return 1
    fi
    
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    OUTFILE="${CSV_BASE}.${HOSTNAME}.csv"
    
    # Create temporary .spiceinit for PDK compatibility
    # The ngbehavior=hsa setting needs to be active before the circuit is parsed,
    # so it cannot be set inside .control blocks. Creating a local .spiceinit
    # to maintain portability (will be cleaned up after simulation).
    SPICEINIT_BACKUP=""
    if [[ -f ".spiceinit" ]]; then
        SPICEINIT_BACKUP=".spiceinit.backup.$$"
        echo_warn "Backing up existing .spiceinit to $SPICEINIT_BACKUP"
        mv ".spiceinit" "$SPICEINIT_BACKUP"
    fi
    
    echo_warn "Creating temporary .spiceinit (ngbehavior=hsa must be set before circuit parsing)"
    
    cat > .spiceinit << 'EOF'
set ngbehavior=hsa
set skywaterpdk
set ng_nomodcheck
EOF
    
    # Create temporary circuit file with device substitution
    # This allows swapping device types without nested subcircuit issues
    TEMP_CIR="${CIR_FILE%.cir}.tmp.cir"
    echo_status "Substituting devices: NMOS=$NMOS_DEVICE, PMOS=$PMOS_DEVICE"
    sed -e "s/abnmos/$NMOS_DEVICE/g" \
        -e "s/abpmos/$PMOS_DEVICE/g" \
        -e '/\.include.*devices.*\.cir/d' \
        "$CIR_FILE" > "$TEMP_CIR"
    
    # Cleanup function
    cleanup_spiceinit() {
        rm -f .spiceinit
        rm -f "$TEMP_CIR"
        if [[ -n "$SPICEINIT_BACKUP" && -f "$SPICEINIT_BACKUP" ]]; then
            mv "$SPICEINIT_BACKUP" .spiceinit
            echo_status "Restored original .spiceinit"
        else
            echo_status "Removed temporary .spiceinit (portability retained)"
        fi
    }
    trap cleanup_spiceinit EXIT
    
    # Run ngspice with temporary circuit file
    "$NGSPICE_BIN" -b "$TEMP_CIR" > "${CSV_BASE}.out" 2>&1
    
    # Cleanup spiceinit immediately after run
    cleanup_spiceinit
    trap - EXIT
    
    if grep -q "Done" "${CSV_BASE}.out" && [[ -f "${CSV_BASE}.csv" ]]; then
        echo_status "ngspice completed successfully"
        
        # Show measurements
        echo_status "Measurements:"
        grep -E "^(t_rise1|freq|period|i_vdd|i_vss)" "${CSV_BASE}.out" | sed 's/^/    /' || true
        
        # Convert whitespace to comma and add metadata
        {
            echo "# hostname: $HOSTNAME"
            echo "# simulator: ngspice"
            echo "# source: $CIR_FILE"
            echo "# timestamp: $TIMESTAMP"
            # Convert whitespace-delimited to comma-delimited
            sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' "${CSV_BASE}.csv" | \
                sed -E 's/[[:space:]]+/,/g'
        } > "$OUTFILE"
        
        rm -f "${CSV_BASE}.csv"
        
        echo_status "Created $OUTFILE"
        
        # Show column headers
        echo_status "CSV columns:"
        grep -v '^#' "$OUTFILE" | head -1 | sed 's/^/    /'
    else
        echo_error "ngspice failed - check ${CSV_BASE}.out"
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
    rm -f ${CSV_BASE}.*.csv ${CSV_BASE}.csv ${CSV_BASE}.out
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

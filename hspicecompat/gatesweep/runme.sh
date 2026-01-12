#!/usr/bin/env zsh
# Run HSPICE and ngspice Id-Vgs gate sweep and compare results
# Usage: ./runme.sh [hspice|ngspice|both|plot]
#   hspice - run HSPICE only
#   ngspice - run ngspice only  
#   both - run both (default)
#   plot - just plot existing data

set -e

#############################################
# CONFIGURATION - Edit these paths as needed
#############################################

# ngspice binary
NGSPICE_BIN="ngspice"

# HSPICE binary
HSPICE_BIN="hspice"

# Python binary
PYTHON_BIN="python3"

#############################################
# END CONFIGURATION
#############################################

MODE="${1:-both}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo_config() {
    echo -e "${CYAN}[CONFIG]${NC} $1"
}

# Show configuration
show_config() {
    echo_config "NGSPICE_BIN = $NGSPICE_BIN"
    echo_config "HSPICE_BIN  = $HSPICE_BIN"
    echo_config "PYTHON_BIN  = $PYTHON_BIN"
    if [[ -n "$SPICE_LIB" ]]; then
        echo_config "SPICE_LIB   = $SPICE_LIB"
    else
        echo_config "SPICE_LIB   = (not set)"
    fi
    echo ""
}

# Check for required tools
check_hspice() {
    if command -v "$HSPICE_BIN" &> /dev/null || [[ -x "$HSPICE_BIN" ]]; then
        return 0
    else
        echo_warn "HSPICE not found: $HSPICE_BIN"
        return 1
    fi
}

check_ngspice() {
    if command -v "$NGSPICE_BIN" &> /dev/null || [[ -x "$NGSPICE_BIN" ]]; then
        # Show version
        echo_status "ngspice version:"
        "$NGSPICE_BIN" --version 2>&1 | head -3 | sed 's/^/    /'
        return 0
    else
        echo_warn "ngspice not found: $NGSPICE_BIN"
        return 1
    fi
}

# Validate SPICE_LIB environment variable
check_spice_lib() {
    # Check if SPICE_LIB is set
    if [[ -z "$SPICE_LIB" ]]; then
        echo_error "SPICE_LIB environment variable is not set"
        echo_error "Set it to your SkyWater PDK models path, e.g.:"
        echo_error "  export SPICE_LIB=/path/to/skywater-pdk/libraries/sky130_fd_pr/latest/models"
        return 1
    fi
    
    # Check if SPICE_LIB directory exists
    if [[ ! -d "$SPICE_LIB" ]]; then
        echo_error "SPICE_LIB directory does not exist: $SPICE_LIB"
        return 1
    fi
    
    # Check if the sky130.lib.spice file exists
    if [[ ! -f "$SPICE_LIB/sky130.lib.spice" ]]; then
        echo_error "sky130.lib.spice not found in SPICE_LIB directory"
        echo_error "Expected: $SPICE_LIB/sky130.lib.spice"
        echo_error ""
        echo_error "Contents of $SPICE_LIB:"
        ls -la "$SPICE_LIB" 2>/dev/null | head -10 || echo "  (unable to list directory)"
        return 1
    fi
    
    echo_status "SPICE_LIB validated: $SPICE_LIB"
    return 0
}

# Run HSPICE simulation
run_hspice() {
    echo_status "Running HSPICE Id-Vgs gate sweep simulation..."
    
    if ! check_hspice; then
        echo_error "Skipping HSPICE (not available)"
        return 1
    fi
    
    "$HSPICE_BIN" gatesweephspice.cir > gatesweephspice.out 2>&1
    
    if grep -q "job concluded" gatesweephspice.out; then
        echo_status "HSPICE completed successfully"
        
        # Convert to CSV
        echo_status "Converting HSPICE output to CSV..."
        "$PYTHON_BIN" hspice_dc_to_csv.py gatesweephspice.out gatesweep_hspice.csv
        echo_status "Created gatesweep_hspice.csv"
    else
        echo_error "HSPICE simulation failed - check gatesweephspice.out"
        tail -20 gatesweephspice.out
        return 1
    fi
}

# Run ngspice simulation
run_ngspice() {
    echo_status "Running ngspice Id-Vgs gate sweep simulation..."
    
    if ! check_ngspice; then
        echo_error "Skipping ngspice (not available)"
        return 1
    fi
    
    # Validate SPICE_LIB
    if ! check_spice_lib; then
        return 1
    fi
    
    "$NGSPICE_BIN" -b gatesweepngspice.cir > gatesweepngspice.out 2>&1
    
    if grep -q "Done" gatesweepngspice.out && [[ -f "gatesweep_ngspice.csv" ]]; then
        echo_status "ngspice completed successfully"
        echo_status "Created gatesweep_ngspice.csv"
    else
        echo_error "ngspice simulation failed - check gatesweepngspice.out"
        echo ""
        cat gatesweepngspice.out
        return 1
    fi
}

# Plot comparison
plot_results() {
    echo_status "Generating comparison plot..."
    
    # Use arrays for proper argument handling in zsh
    PLOT_ARGS=()
    
    if [[ -f "gatesweep_hspice.csv" ]]; then
        PLOT_ARGS+=(--hspice gatesweep_hspice.csv)
        echo_status "  Including HSPICE data"
    fi
    
    if [[ -f "gatesweep_ngspice.csv" ]]; then
        PLOT_ARGS+=(--ngspice gatesweep_ngspice.csv)
        echo_status "  Including ngspice data"
    fi
    
    if [[ ${#PLOT_ARGS[@]} -gt 0 ]]; then
        "$PYTHON_BIN" plot_gatesweep_comparison.py "${PLOT_ARGS[@]}" -o gatesweep_comparison.png
        echo_status "Created gatesweep_comparison.png"
    else
        echo_warn "No data files found to plot"
    fi
}

# Main
show_config

case "$MODE" in
    hspice)
        run_hspice
        plot_results
        ;;
    ngspice)
        run_ngspice
        plot_results
        ;;
    both)
        HSPICE_OK=0
        NGSPICE_OK=0
        
        run_hspice && HSPICE_OK=1 || true
        run_ngspice && NGSPICE_OK=1 || true
        
        if [[ $HSPICE_OK -eq 0 && $NGSPICE_OK -eq 0 ]]; then
            echo_error "Both simulations failed"
            exit 1
        fi
        
        plot_results
        ;;
    plot)
        plot_results
        ;;
    config)
        # Just show config and exit
        ;;
    *)
        echo "Usage: $0 [hspice|ngspice|both|plot|config]"
        echo ""
        echo "Options:"
        echo "  hspice  - Run HSPICE only"
        echo "  ngspice - Run ngspice only"
        echo "  both    - Run both (default)"
        echo "  plot    - Just plot existing data"
        echo "  config  - Show configuration and exit"
        echo ""
        echo "Environment:"
        echo "  SPICE_LIB must be set to the SkyWater PDK models directory"
        echo "  e.g.: export SPICE_LIB=/path/to/sky130_fd_pr/latest/models"
        echo ""
        echo "Edit the CONFIGURATION section at top of script to change paths."
        exit 1
        ;;
esac

echo_status "Done!"

#!/usr/bin/env zsh
# Run HSPICE and ngspice transmission gate AC analysis and compare results
# Usage: ./runme.sh [hspice|ngspice|both|plot]
#   hspice - run HSPICE only
#   ngspice - run ngspice only  
#   both - run both (default)
#   plot - just plot existing data

set -e

MODE="${1:-both}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check for required tools
check_hspice() {
    if command -v hspice &> /dev/null; then
        return 0
    else
        echo_warn "HSPICE not found in PATH"
        return 1
    fi
}

check_ngspice() {
    if command -v ngspice &> /dev/null; then
        return 0
    else
        echo_warn "ngspice not found in PATH"
        return 1
    fi
}

# Run HSPICE simulation
run_hspice() {
    echo_status "Running HSPICE simulation..."
    
    if ! check_hspice; then
        echo_error "Skipping HSPICE (not available)"
        return 1
    fi
    
    hspice tgatehspice.cir > tgatehspice.out 2>&1
    
    if grep -q "job concluded" tgatehspice.out; then
        echo_status "HSPICE completed successfully"
        
        # Convert to CSV
        echo_status "Converting HSPICE output to CSV..."
        python3 hspice_to_csv.py tgatehspice.out tgate_hspice.csv
        echo_status "Created tgate_hspice.csv"
    else
        echo_error "HSPICE simulation failed - check tgatehspice.out"
        return 1
    fi
}

# Run ngspice simulation
run_ngspice() {
    echo_status "Running ngspice simulation..."
    
    if ! check_ngspice; then
        echo_error "Skipping ngspice (not available)"
        return 1
    fi
    
    # Check SPICE_LIB is set
    if [[ -z "$SPICE_LIB" ]]; then
        echo_error "SPICE_LIB environment variable not set"
        echo_error "Set it to your SkyWater PDK models path, e.g.:"
        echo_error "  export SPICE_LIB=/path/to/skywater-pdk/libraries/sky130_fd_pr/latest/models"
        return 1
    fi
    
    ngspice -b tgatengspice.cir > tgatengspice.out 2>&1
    
    if grep -q "ngspice AC analysis complete" tgatengspice.out; then
        echo_status "ngspice completed successfully"
        echo_status "Created tgate_ngspice.csv"
    else
        echo_error "ngspice simulation failed - check tgatengspice.out"
        cat tgatengspice.out
        return 1
    fi
}

# Plot comparison
plot_results() {
    echo_status "Generating comparison plot..."
    
    PLOT_ARGS=""
    
    if [[ -f "tgate_hspice.csv" ]]; then
        PLOT_ARGS="$PLOT_ARGS --hspice tgate_hspice.csv"
        echo_status "  Including HSPICE data"
    fi
    
    if [[ -f "tgate_ngspice.csv" ]]; then
        PLOT_ARGS="$PLOT_ARGS --ngspice tgate_ngspice.csv"
        echo_status "  Including ngspice data"
    fi
    
    if [[ -z "$PLOT_ARGS" ]]; then
        echo_error "No data files found to plot"
        return 1
    fi
    
    python3 plot_ac_comparison.py $PLOT_ARGS -o tgate_comparison.png
    echo_status "Created tgate_comparison.png"
}

# Main
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
    *)
        echo "Usage: $0 [hspice|ngspice|both|plot]"
        exit 1
        ;;
esac

echo_status "Done!"




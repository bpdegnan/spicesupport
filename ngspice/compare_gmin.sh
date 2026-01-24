#!/usr/bin/env zsh
# Compare DC vs Transient simulations for the same gmin value
# Usage: ./compare_gmin.sh

set -e

PYTHON_BIN="python3"
HOSTNAME=$(hostname -s)

DC_DIR="dcnfet"
TRANS_DIR="transnfet"
PLOT_SCRIPT="plot_dc_vs_trans.py"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn()   { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error()  { echo -e "${RED}[ERROR]${NC} $1"; }

echo_status "Hostname: $HOSTNAME"
echo ""

# Check directories exist
if [[ ! -d "$DC_DIR" ]]; then
    echo_error "DC directory not found: $DC_DIR"
    exit 1
fi

if [[ ! -d "$TRANS_DIR" ]]; then
    echo_error "Transient directory not found: $TRANS_DIR"
    exit 1
fi

# Find CSV files for this hostname and extract gmin values
DC_FILES=(${DC_DIR}/nfetdc.gmin*.${HOSTNAME}.csv(N))
TRANS_FILES=(${TRANS_DIR}/nfettrans.gmin*.${HOSTNAME}.csv(N))

if [[ ${#DC_FILES[@]} -eq 0 ]]; then
    echo_error "No DC CSV files found for hostname $HOSTNAME in $DC_DIR"
    exit 1
fi

if [[ ${#TRANS_FILES[@]} -eq 0 ]]; then
    echo_error "No transient CSV files found for hostname $HOSTNAME in $TRANS_DIR"
    exit 1
fi

echo_status "Found DC files:"
for f in "${DC_FILES[@]}"; do
    echo "    $f"
done
echo ""

echo_status "Found transient files:"
for f in "${TRANS_FILES[@]}"; do
    echo "    $f"
done
echo ""

# Extract gmin values from filenames
typeset -A dc_gmin_files
typeset -A trans_gmin_files

for f in "${DC_FILES[@]}"; do
    gmin=$(echo "$f" | sed -E 's/.*\.(gmin[^.]+)\..*/\1/')
    dc_gmin_files[$gmin]="$f"
done

for f in "${TRANS_FILES[@]}"; do
    gmin=$(echo "$f" | sed -E 's/.*\.(gmin[^.]+)\..*/\1/')
    trans_gmin_files[$gmin]="$f"
done

# Find matching gmin values
matching_gmins=()
for gmin in ${(k)dc_gmin_files}; do
    if [[ -n "${trans_gmin_files[$gmin]}" ]]; then
        matching_gmins+=("$gmin")
    fi
done

if [[ ${#matching_gmins[@]} -eq 0 ]]; then
    echo_error "No matching gmin values found between DC and transient"
    echo ""
    echo "DC gmin values: ${(k)dc_gmin_files}"
    echo "Transient gmin values: ${(k)trans_gmin_files}"
    exit 1
fi

# Sort gmin values
matching_gmins=(${(o)matching_gmins})

echo_status "Matching gmin values:"
for i in {1..${#matching_gmins[@]}}; do
    gmin=${matching_gmins[$i]}
    echo "    $i) $gmin"
done
echo ""

# Ask user to select
echo -n "Select gmin to compare (1-${#matching_gmins[@]}): "
read selection

if [[ ! "$selection" =~ ^[0-9]+$ ]] || [[ "$selection" -lt 1 ]] || [[ "$selection" -gt ${#matching_gmins[@]} ]]; then
    echo_error "Invalid selection"
    exit 1
fi

selected_gmin=${matching_gmins[$selection]}
dc_file="${dc_gmin_files[$selected_gmin]}"
trans_file="${trans_gmin_files[$selected_gmin]}"

echo ""
echo_status "Comparing $selected_gmin:"
echo "    DC:        $dc_file"
echo "    Transient: $trans_file"
echo ""

if [[ ! -f "$PLOT_SCRIPT" ]]; then
    echo_error "Plot script not found: $PLOT_SCRIPT"
    exit 1
fi

"$PYTHON_BIN" "$PLOT_SCRIPT" "$dc_file" "$trans_file"

echo_status "Done!"

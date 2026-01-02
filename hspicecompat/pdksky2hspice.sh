#!/usr/bin/env zsh

# Convert entire SkyWater 130nm PDK to HSPICE-compatible format
# Usage: ./pdksky2hspice.sh /path/to/skywater-pdk/libraries/sky130_fd_pr/latest

set -e

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <path_to_sky130_fd_pr>"
    echo "Example: $0 /home/user/skywater-pdk/libraries/sky130_fd_pr/latest"
    exit 1
fi

PDK_PATH="$1"

if [[ ! -d "${PDK_PATH}" ]]; then
    echo "Error: PDK path '${PDK_PATH}' not found"
    exit 1
fi

if [[ ! -d "${PDK_PATH}/models" ]]; then
    echo "Error: models directory not found in '${PDK_PATH}'"
    exit 1
fi

# Create output directory
OUTPUT_DIR="sky130_hspice"
mkdir -p "${OUTPUT_DIR}/models"
mkdir -p "${OUTPUT_DIR}/cells"

echo "========================================"
echo "SkyWater 130nm PDK to HSPICE Converter"
echo "========================================"
echo "Input:  ${PDK_PATH}"
echo "Output: ${OUTPUT_DIR}"
echo ""

# Function to convert a single file
convert_file() {
    local input_file="$1"
    local output_file="$2"
    
    sed -E \
        -e 's/ = /=/g' \
        -e 's/=\{([a-zA-Z_][a-zA-Z0-9_]*)\}/=\1/g' \
        -e 's/\{([a-zA-Z_][a-zA-Z0-9_]*)\}/\1/g' \
        -e 's/\$(.*)$/; \1/g' \
        -e 's/\.model ([a-zA-Z0-9_]+)__model\.0 /.model \1 /g' \
        -e 's/\.model ([a-zA-Z0-9_]+)__model /.model \1 /g' \
        -e 's/([^a-zA-Z0-9_])vt([^a-zA-Z0-9_])/\1local_vt\2/g' \
        -e 's/^vt([^a-zA-Z0-9_])/local_vt\1/g' \
        -e 's/dev\/gauss/; dev\/gauss/g' \
        -e 's/agauss/0 ; agauss/g' \
        -e 's/gauss/0 ; gauss/g' \
        "${input_file}" > "${output_file}"
}

# Function to extract and convert model parameters from a .spice file
# This creates a clean .model card without the subcircuit wrapper
extract_model() {
    local input_file="$1"
    local output_file="$2"
    local model_name="$3"
    local model_type="$4"  # nmos or pmos
    
    # Extract everything from .model to the next .model or .subckt or .ends
    awk -v mname="${model_name}" -v mtype="${model_type}" '
    BEGIN { in_model = 0; }
    /^\.model/ { 
        in_model = 1; 
        # Fix model name and print
        gsub(/__model\.0/, "", $0);
        gsub(/__model/, "", $0);
        gsub(/ = /, "=", $0);
        print $0;
        next;
    }
    /^\.subckt|^\.ends|^[Mm][a-zA-Z0-9_]+ / {
        if (in_model) { in_model = 0; }
        next;
    }
    in_model {
        # Convert parameter syntax
        gsub(/ = /, "=", $0);
        gsub(/\{([a-zA-Z_][a-zA-Z0-9_]*)\}/, "\\1", $0);
        gsub(/\$.*$/, "", $0);  # Remove $ comments
        if (length($0) > 1) print $0;
    }
    ' "${input_file}" >> "${output_file}"
}

echo "Step 1: Converting model files..."
echo "-----------------------------------"

# Process corner files
for corner_file in "${PDK_PATH}"/models/corners/*.spice; do
    if [[ -f "${corner_file}" ]]; then
        filename=$(basename "${corner_file}")
        output_file="${OUTPUT_DIR}/models/${filename:r}.l"
        echo "  Converting: ${filename}"
        convert_file "${corner_file}" "${output_file}"
    fi
done

# Process parameters files
for param_file in "${PDK_PATH}"/models/parameters/*.spice; do
    if [[ -f "${param_file}" ]]; then
        filename=$(basename "${param_file}")
        output_file="${OUTPUT_DIR}/models/${filename:r}.l"
        echo "  Converting: ${filename}"
        convert_file "${param_file}" "${output_file}"
    fi
done

echo ""
echo "Step 2: Converting cell model files..."
echo "---------------------------------------"

# Process all cell spice files
cell_count=0
for cell_dir in "${PDK_PATH}"/cells/*/; do
    cell_name=$(basename "${cell_dir}")
    mkdir -p "${OUTPUT_DIR}/cells/${cell_name}"
    
    for spice_file in "${cell_dir}"*.spice; do
        if [[ -f "${spice_file}" ]]; then
            filename=$(basename "${spice_file}")
            output_file="${OUTPUT_DIR}/cells/${cell_name}/${filename:r}.l"
            convert_file "${spice_file}" "${output_file}"
            ((cell_count++))
        fi
    done
done
echo "  Converted ${cell_count} cell files"

echo ""
echo "Step 3: Creating master library file..."
echo "----------------------------------------"

# Create the master sky130_hspice.lib file
cat > "${OUTPUT_DIR}/sky130_hspice.lib" << 'LIBHEADER'
* SkyWater 130nm PDK - HSPICE Compatible Library
* Auto-generated from ngspice PDK
* 
* Usage: .lib 'sky130_hspice.lib' tt
*

LIBHEADER

# Create TT corner section
cat >> "${OUTPUT_DIR}/sky130_hspice.lib" << 'TTHEAD'
.lib tt
* Typical-Typical Corner

* Options for SkyWater PDK
.option scale=1e-6

TTHEAD

# Include the converted corner file if it exists
if [[ -f "${OUTPUT_DIR}/models/tt.l" ]]; then
    echo ".include 'models/tt.l'" >> "${OUTPUT_DIR}/sky130_hspice.lib"
fi

# Add basic NMOS and PMOS models
cat >> "${OUTPUT_DIR}/sky130_hspice.lib" << 'MODELS'

* ============================================
* NMOS 1.8V Model - sky130_fd_pr__nfet_01v8
* ============================================
MODELS

# Try to find and include the nfet model
if [[ -f "${OUTPUT_DIR}/cells/nfet_01v8/sky130_fd_pr__nfet_01v8__tt.pm3.l" ]]; then
    echo ".include 'cells/nfet_01v8/sky130_fd_pr__nfet_01v8__tt.pm3.l'" >> "${OUTPUT_DIR}/sky130_hspice.lib"
fi

cat >> "${OUTPUT_DIR}/sky130_hspice.lib" << 'MODELS2'

* ============================================
* PMOS 1.8V Model - sky130_fd_pr__pfet_01v8  
* ============================================
MODELS2

# Try to find and include the pfet model
if [[ -f "${OUTPUT_DIR}/cells/pfet_01v8/sky130_fd_pr__pfet_01v8__tt.pm3.l" ]]; then
    echo ".include 'cells/pfet_01v8/sky130_fd_pr__pfet_01v8__tt.pm3.l'" >> "${OUTPUT_DIR}/sky130_hspice.lib"
fi

echo "" >> "${OUTPUT_DIR}/sky130_hspice.lib"
echo ".endl tt" >> "${OUTPUT_DIR}/sky130_hspice.lib"

# Create FF corner section
cat >> "${OUTPUT_DIR}/sky130_hspice.lib" << 'FFHEAD'

.lib ff
* Fast-Fast Corner
.option scale=1e-6

FFHEAD

if [[ -f "${OUTPUT_DIR}/models/ff.l" ]]; then
    echo ".include 'models/ff.l'" >> "${OUTPUT_DIR}/sky130_hspice.lib"
fi
if [[ -f "${OUTPUT_DIR}/cells/nfet_01v8/sky130_fd_pr__nfet_01v8__ff.pm3.l" ]]; then
    echo ".include 'cells/nfet_01v8/sky130_fd_pr__nfet_01v8__ff.pm3.l'" >> "${OUTPUT_DIR}/sky130_hspice.lib"
fi
if [[ -f "${OUTPUT_DIR}/cells/pfet_01v8/sky130_fd_pr__pfet_01v8__ff.pm3.l" ]]; then
    echo ".include 'cells/pfet_01v8/sky130_fd_pr__pfet_01v8__ff.pm3.l'" >> "${OUTPUT_DIR}/sky130_hspice.lib"
fi
echo ".endl ff" >> "${OUTPUT_DIR}/sky130_hspice.lib"

# Create SS corner section
cat >> "${OUTPUT_DIR}/sky130_hspice.lib" << 'SSHEAD'

.lib ss
* Slow-Slow Corner
.option scale=1e-6

SSHEAD

if [[ -f "${OUTPUT_DIR}/models/ss.l" ]]; then
    echo ".include 'models/ss.l'" >> "${OUTPUT_DIR}/sky130_hspice.lib"
fi
if [[ -f "${OUTPUT_DIR}/cells/nfet_01v8/sky130_fd_pr__nfet_01v8__ss.pm3.l" ]]; then
    echo ".include 'cells/nfet_01v8/sky130_fd_pr__nfet_01v8__ss.pm3.l'" >> "${OUTPUT_DIR}/sky130_hspice.lib"
fi
if [[ -f "${OUTPUT_DIR}/cells/pfet_01v8/sky130_fd_pr__pfet_01v8__ss.pm3.l" ]]; then
    echo ".include 'cells/pfet_01v8/sky130_fd_pr__pfet_01v8__ss.pm3.l'" >> "${OUTPUT_DIR}/sky130_hspice.lib"
fi
echo ".endl ss" >> "${OUTPUT_DIR}/sky130_hspice.lib"

echo ""
echo "Step 4: Creating device abstraction file..."
echo "--------------------------------------------"

# Create devices_hspice.cir for easy use
cat > "${OUTPUT_DIR}/devices_hspice.cir" << 'DEVICES'
* SkyWater 130nm Abstract Devices for HSPICE
* These bypass the ngspice-specific subcircuit wrappers
*
* Usage:
*   .include 'devices_hspice.cir'
*   Xn1 drain gate source bulk abnmos l=0.15 w=1
*   Xp1 drain gate source bulk abpmos l=0.15 w=1

* NMOS transistor subcircuit definition
.subckt abnmos D G S B l=0.15 w=1 m=1 nf=1
M1 D G S B sky130_fd_pr__nfet_01v8 l=l w=w m=m nf=nf
.ends abnmos

* PMOS transistor subcircuit definition
.subckt abpmos D G S B l=0.15 w=1 m=1 nf=1
M1 D G S B sky130_fd_pr__pfet_01v8 l=l w=w m=m nf=nf
.ends abpmos

* NMOS 1.8V High-Vt
.subckt abnmos_hvt D G S B l=0.15 w=1 m=1 nf=1
M1 D G S B sky130_fd_pr__nfet_01v8_hvt l=l w=w m=m nf=nf
.ends abnmos_hvt

* PMOS 1.8V High-Vt
.subckt abpmos_hvt D G S B l=0.15 w=1 m=1 nf=1
M1 D G S B sky130_fd_pr__pfet_01v8_hvt l=l w=w m=m nf=nf
.ends abpmos_hvt

* NMOS 1.8V Low-Vt
.subckt abnmos_lvt D G S B l=0.15 w=1 m=1 nf=1
M1 D G S B sky130_fd_pr__nfet_01v8_lvt l=l w=w m=m nf=nf
.ends abnmos_lvt

* PMOS 1.8V Low-Vt
.subckt abpmos_lvt D G S B l=0.15 w=1 m=1 nf=1
M1 D G S B sky130_fd_pr__pfet_01v8_lvt l=l w=w m=m nf=nf
.ends abpmos_lvt

DEVICES

echo ""
echo "Step 5: Creating test file..."
echo "------------------------------"

# Create a simple test file
cat > "${OUTPUT_DIR}/test_inverter.cir" << 'TESTFILE'
* Simple Inverter Test - HSPICE with SkyWater 130nm
* Run with: hspice test_inverter.cir

.option post accurate

* Include the HSPICE-compatible library
.lib 'sky130_hspice.lib' tt

* Include device abstractions
.include 'devices_hspice.cir'

* Power supply
Vdd vdd 0 DC 1.8

* Input
Vin in 0 PULSE(0 1.8 0 100p 100p 5n 10n)

* Inverter using abstract devices
Xp1 out in vdd vdd abpmos l=0.15 w=1
Xn1 out in 0 0 abnmos l=0.15 w=0.5

* Load capacitor
Cload out 0 10f

* Analysis
.tran 10p 20n

* Output
.print tran v(in) v(out)
.probe tran v(in) v(out)

.end
TESTFILE

echo ""
echo "Step 6: Post-processing fixes..."
echo "---------------------------------"

# Additional fixes that need file-by-file processing
echo "  Fixing .endl statements..."
find "${OUTPUT_DIR}" -name "*.l" -exec sed -i '' -E 's/^\.endl ([a-zA-Z0-9_]+) \1$/.endl \1/g' {} \; 2>/dev/null || true

echo "  Removing malformed includes..."
find "${OUTPUT_DIR}" -name "*.l" -exec sed -i '' -E 's/^\.include.*nfet_05v0_nvt.*$/; Removed: nfet_05v0_nvt include/g' {} \; 2>/dev/null || true

echo "  Fixing option scale statements..."
find "${OUTPUT_DIR}" -name "*.l" -exec sed -i '' -E 's/^option scale/.option scale/g' {} \; 2>/dev/null || true

echo ""
echo "========================================"
echo "Conversion complete!"
echo "========================================"
echo ""
echo "Output directory: ${OUTPUT_DIR}/"
echo ""
echo "Files created:"
echo "  - sky130_hspice.lib    : Master library file"
echo "  - devices_hspice.cir   : Device abstraction subcircuits"
echo "  - test_inverter.cir    : Simple test circuit"
echo "  - models/              : Converted corner and parameter files"
echo "  - cells/               : Converted cell model files"
echo ""
echo "Usage in HSPICE:"
echo "  .lib '${OUTPUT_DIR}/sky130_hspice.lib' tt"
echo "  .include '${OUTPUT_DIR}/devices_hspice.cir'"
echo ""
echo "IMPORTANT NOTES:"
echo "  1. This is an automated conversion - manual verification recommended"
echo "  2. Some advanced features (agauss, etc.) have been disabled"
echo "  3. The subcircuit wrappers are bypassed for compatibility"
echo "  4. Test with simple circuits before complex simulations"
echo ""
echo "Known issues that may require manual fixes:"
echo "  - Monte Carlo (agauss/gauss) functions are commented out"
echo "  - Some device-specific parameters may need adjustment"
echo "  - High-voltage devices (5V) may need additional work"
echo ""
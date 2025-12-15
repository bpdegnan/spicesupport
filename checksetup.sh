#!/usr/bin/env zsh

# Directory containing PDK support directories
SUPPORT_DIR="abstractdevice"

# Check if SPICE_LIB is set
if [[ -z "${SPICE_LIB}" ]]; then
    echo "Error: The SPICE models are not found because SPICE_LIB is not set in shell" >&2
    exit 1
fi

# Check if spicesupport directory exists
if [[ ! -d "${SUPPORT_DIR}" ]]; then
    echo "Error: ${SUPPORT_DIR} directory not found" >&2
    exit 1
fi

# Get list of subdirectories
pdks=("${SUPPORT_DIR}"/*(/:t))

# Check if any PDKs were found
if [[ ${#pdks[@]} -eq 0 ]]; then
    echo "Error: No PDK directories found in ${SUPPORT_DIR}" >&2
    exit 1
fi

# Present menu to user
echo "Available PDKs:"
for i in {1..${#pdks[@]}}; do
    echo "  $i) ${pdks[$i]}"
done

# Get user selection
echo ""
read "selection?Select PDK [1-${#pdks[@]}]: "

# Validate selection
if [[ ! "${selection}" =~ ^[0-9]+$ ]] || (( selection < 1 || selection > ${#pdks[@]} )); then
    echo "Error: Invalid selection" >&2
    exit 1
fi

# Set the selected PDK
selected_pdk="${pdks[$selection]}"
devices_file="${SUPPORT_DIR}/${selected_pdk}/devices.cir"

# Verify devices.cir exists
if [[ ! -f "${devices_file}" ]]; then
    echo "Error: ${devices_file} not found" >&2
    exit 1
fi

echo ""
echo "Using models at: ${SPICE_LIB}"
echo "Using device abstractions from: ${devices_file}"

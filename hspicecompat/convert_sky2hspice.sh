#!/usr/bin/env zsh

# Convert SkyWater 130nm PDK model files to HSPICE-compatible format

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <input_model_file>"
    exit 1
fi

INPUT_FILE="$1"

if [[ ! -f "${INPUT_FILE}" ]]; then
    echo "Error: File '${INPUT_FILE}' not found"
    exit 1
fi

# Create output filename with .l suffix
OUTPUT_FILE="${INPUT_FILE:r}.l"

echo "Converting ${INPUT_FILE} to ${OUTPUT_FILE}"

# Process the file:
# 1. Remove spaces around = signs
# 2. Convert {param} to param (remove curly braces)
# 3. Fix model name .0 suffix issue
# 4. Remove the problematic subckt wrapper lines

sed -E \
    -e 's/ = /=/g' \
    -e 's/\{([a-zA-Z0-9_]+)\}/\1/g' \
    -e 's/\.model ([a-zA-Z0-9_]+)__model\.0/.model \1/g' \
    -e 's/\.model ([a-zA-Z0-9_]+)__model /.model \1 /g' \
    "${INPUT_FILE}" > "${OUTPUT_FILE}"

echo "Done. Output written to ${OUTPUT_FILE}"
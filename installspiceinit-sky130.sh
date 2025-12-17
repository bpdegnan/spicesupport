#!/bin/zsh

# Path to the source spiceinit.txt
SOURCE_FILE="spiceinit.txt"

# Check if the source file exists
if [[ ! -f "$SOURCE_FILE" ]]; then
    echo "Source file spiceinit.txt not found!"
    exit 1
fi

# Loop through each subdirectory
for dir in */; do
    # Check if it's a directory
    if [[ -d "$dir" ]]; then
        # Check if .spiceinit file exists in the subdirectory
        if [[ ! -f "${dir}.spiceinit" ]]; then
            # Copy spiceinit.txt to .spiceinit in the subdirectory
            cp "$SOURCE_FILE" "${dir}.spiceinit"
            echo "Copied spiceinit.txt to ${dir}.spiceinit"
        else
            echo ".spiceinit already exists in $dir"
        fi
    fi
done

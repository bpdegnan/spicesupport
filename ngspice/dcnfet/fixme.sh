#!/usr/bin/env zsh
# clean up macOS attributes and make scripts executable
if [[ "$(uname)" == "Darwin" ]]; then
    xattr -rc .
fi

chmod +x runme.sh
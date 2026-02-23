#!/bin/bash
# Double-click this file in Finder to launch Egnyte Prep.
# It will open Terminal and guide you through the process.

# Get the directory where this .command file lives
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Check if egnyte-prep.sh exists alongside this file
if [[ -f "$SCRIPT_DIR/egnyte-prep.sh" ]]; then
    chmod +x "$SCRIPT_DIR/egnyte-prep.sh"
    "$SCRIPT_DIR/egnyte-prep.sh"
else
    # If installed via curl, it'll be in /usr/local/bin
    if command -v egnyte-prep &>/dev/null; then
        egnyte-prep
    else
        echo ""
        echo "Error: Can't find egnyte-prep.sh"
        echo "Make sure egnyte-prep.sh is in the same folder as this file."
        echo ""
    fi
fi

echo ""
echo "Press any key to close this window..."
read -n 1 -s

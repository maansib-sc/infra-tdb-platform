 #!/usr/bin/env bash
set -euo pipefail

# Base directory (current directory by default)
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "Cleaning logs folders in module-* and package-* directories under:"
echo "  $BASE_DIR"
echo

for dir in "$BASE_DIR"/module-* "$BASE_DIR"/package-*; do
    # Skip if glob doesn't match anything
    [ -d "$dir" ] || continue

    LOG_DIR="$dir/logs"

    if [ -d "$LOG_DIR" ]; then
        echo "Removing: $LOG_DIR"
        sudo rm -rf "$LOG_DIR"
    else
        echo "No logs folder in: $dir"
    fi
done

echo "Done."

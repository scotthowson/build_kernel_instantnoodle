#!/bin/bash
# Download the third-party recovery images listed in build.conf (RECOVERY_IMAGES).
# These are only convenience downloads for flashing; they are not used by the build.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"
source ./build.conf
for entry in "${RECOVERY_IMAGES[@]}"; do
    IFS='|' read -r file url <<< "$entry"
    mkdir -p "$(dirname "$file")"
    echo "Downloading $file"
    wget -q -O "$file" "$url"
done
echo "Done."

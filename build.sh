#!/bin/bash
# Thin wrapper around the UBports generic adaptation build tools.
#
#   ./build.sh                 build boot/recovery/dtbo images + device tarball into ./out
#   ./build.sh -b <dir>        same, using <dir> as the download/build directory
#   ./build.sh -c              also run menuconfig before the kernel build
#   see ./build/build.sh -h for every option
#
# Everything device specific is read from ./deviceinfo. Nothing in the build
# tools or in deviceinfo is patched at runtime any more: the tools detect dynamic
# partitions from "systempart=/dev/mapper" in the cmdline themselves, and
# parallelism follows $(nproc) (override with MAKEFLAGS if you need fewer jobs).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"
source ./build.conf

if [ ! -d build ]; then
    echo "Cloning build tools (${BUILD_TOOLS_BRANCH})..."
    git clone -b "$BUILD_TOOLS_BRANCH" "$BUILD_TOOLS_REPO" build
else
    echo "Updating build tools..."
    git -C build pull --ff-only origin "$BUILD_TOOLS_BRANCH" || echo "WARNING: could not update build tools, using the checked out copy"
fi

if [ -n "${OVERLAY_REPO:-}" ]; then
    echo "Fetching external overlay ${OVERLAY_REPO} (${OVERLAY_BRANCH:-default branch})..."
    rm -rf overlay
    tmp="$(mktemp -d)"
    git clone --depth 1 ${OVERLAY_BRANCH:+-b "$OVERLAY_BRANCH"} "$OVERLAY_REPO" "$tmp"
    cp -a "$tmp/overlay" overlay
    rm -rf "$tmp"
fi

[ -d overlay/system ] || { echo "ERROR: ./overlay/system is missing"; exit 1; }

echo "Starting build..."
exec ./build/build.sh "$@"

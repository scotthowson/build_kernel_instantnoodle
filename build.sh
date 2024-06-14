#!/bin/bash
set -xe

# Define branches for adaptation tools and overlay
ADAPTATION_TOOLS_BRANCH=main
ADAPTATION_OVERLAY_BRANCH=android-10

# Clone the build tools repository if the build directory doesn't exist
if [ ! -d build ]; then
  echo "Cloning build tools..."
  git clone -b $ADAPTATION_TOOLS_BRANCH https://gitlab.com/ubports/community-ports/halium-generic-adaptation-build-tools build
fi

# Clone the overlay repository into a temporary directory if the overlay directory doesn't exist
if [ ! -d overlay ]; then
  echo "Cloning overlay repository..."
  TEMP_DIR=$(mktemp -d)
  git clone -b $ADAPTATION_OVERLAY_BRANCH https://github.com/scotthowson/oneplus8_ubuntu_adaptation $TEMP_DIR

  # Move all files and directories, including hidden ones, excluding .git to prevent conflicts
  echo "Moving files from temporary directory..."
  shopt -s dotglob
  mv $TEMP_DIR/* $TEMP_DIR/.* . || true
  shopt -u dotglob

  # Remove the temporary directory
  echo "Removing temporary directory..."
  rm -rf $TEMP_DIR
fi

# Insert HAS_DYNAMIC_PARTITIONS=true at line 43 in make-bootimage.sh
echo "Inserting HAS_DYNAMIC_PARTITIONS=true in make-bootimage.sh..."
sed -i '43 i\    HAS_DYNAMIC_PARTITIONS=true' ./build/make-bootimage.sh

# Insert clear command at line 2 in build.sh
# echo "Inserting clear command in build.sh..."
# sed -i '2 i\clear' ./build/build.sh

# Execute the build script with passed arguments
echo "Starting build process..."
./build/build.sh "$@"

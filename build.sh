#!/bin/bash
set -xe

# Define branches for adaptation tools and overlay
ADAPTATION_TOOLS_BRANCH=main
ADAPTATION_OVERLAY_BRANCH=android-10

# Function to download a file using wget or curl
download_file() {
    local url=$1
    local file=$2
    local option=$3
    local option_url=$4

    echo "Downloading: $file"
    if [[ $option == "wget" ]]; then
        wget -O "$file" "$url" &> /dev/null
    elif [[ $option == "curl" ]]; then
        curl --referer "$option_url" -k -o "$file" "$url" &> /dev/null
    fi
    echo "✅ Downloaded: $file"
}

# Function to download multiple files
download_files() {
    local files=(
        "Images/recovery/ofox.img|wget|https://github.com/Wishmasterflo/android_device_oneplus_kebab/releases/download/V15/OrangeFox-R11.1-Unofficial-OnePlus8T_9R-V15.img"
        "Images/recovery/twrp.img|wget|https://github.com/scotthowson/twrp_device_oneplus_instantnoodle/releases/download/v1.0.12/twrp-howsondev-v1.0.12.img"
        "Images/recovery/los.img|wget|https://github.com/IllSaft/los18.1-recovery/releases/download/0.1/LineageOS-18.1-Recovery.img"
    )

    for entry in "${files[@]}"; do
        IFS='|' read -r file option url option_url <<< "$entry"
        download_file "$url" "$file" "$option" "$option_url"
    done

    echo "🎉 All recovery files downloaded successfully."
}

# Clone or update the build tools repository
if [ ! -d build ]; then
    echo "Cloning build tools..."
    git clone -b $ADAPTATION_TOOLS_BRANCH https://gitlab.com/ubports/community-ports/halium-generic-adaptation-build-tools build
else
    echo "Updating build tools..."
    git config --global --add safe.directory /Android-10/OnePlus/build
    cd build
    git pull origin $ADAPTATION_TOOLS_BRANCH
    cd ..
fi

# Always remove and clone the overlay repository
echo "Removing old overlay directory..."
rm -rf overlay

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

# Insert HAS_DYNAMIC_PARTITIONS=true at line 43 in make-bootimage.sh if not already present
echo "Inserting HAS_DYNAMIC_PARTITIONS=true in make-bootimage.sh..."
grep -qxF '    HAS_DYNAMIC_PARTITIONS=true' ./build/make-bootimage.sh || sed -i '43 i\    HAS_DYNAMIC_PARTITIONS=true' ./build/make-bootimage.sh

# Disable set -x for recovery downloads
set +x
# Create the Images/recovery directory and download recovery images if it doesn't exist
if [ ! -d Images/recovery ]; then
    echo "Creating Images/recovery directory and downloading recovery images..."
    mkdir -p Images/recovery
    download_files
fi

# Modify line 57 in build-kernel.sh
echo "Modifying line 57 in build-kernel.sh..."
sed -i '57s/.*/make O="$OUT" $MAKEOPTS -j12/' ./build/build-kernel.sh

# Re-enable set -x
set -x

# Insert clear command at line 2 in build.sh (commented out, if needed uncomment)
# echo "Inserting clear command in build.sh..."
# sed -i '2 i\clear' ./build/build.sh

# Execute the build script with passed arguments
echo "Starting build process..."
./build/build.sh "$@"

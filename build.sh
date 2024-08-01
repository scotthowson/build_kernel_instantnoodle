#!/bin/bash
set -xe

# Load configuration file
source build.conf

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
    for entry in "${RECOVERY_IMAGES[@]}"; do
        IFS='|' read -r file option url option_url <<< "$entry"
        download_file "$url" "$file" "$option" "$option_url"
    done

    echo "🎉 All recovery files downloaded successfully."
}

# Function to modify system-image-from-ota.sh
modify_system_image_script() {
    local script_path="./build/system-image-from-ota.sh"
    if [ -f "$script_path" ]; then
        if [ "$RENAME_UBUNTU" = true ]; then
            echo "Modifying system-image-from-ota.sh to rename rootfs.img to ubuntu.img..."
            sed -i 's|\$OUT/rootfs.img|\$OUT/ubuntu.img|g' "$script_path"
        fi
    fi
}

# Function to set or unset options in deviceinfo file
set_deviceinfo_option() {
    local option=$1
    local value=$2
    local deviceinfo_file="./deviceinfo"
    if [ -f "$deviceinfo_file" ]; then
        if [ "$value" = true ]; then
            echo "Setting $option option in deviceinfo..."
            # Uncomment the line if it is commented
            sed -i "s|# $option=\"true\"|$option=\"true\"|g" "$deviceinfo_file"
            # Add the line if it does not exist
            grep -qxF "$option=\"true\"" "$deviceinfo_file" || echo "$option=\"true\"" >> "$deviceinfo_file"
        else
            echo "Removing $option option in deviceinfo..."
            # Comment the line if it is uncommented
            sed -i "s|^$option=\"true\"|# $option=\"true\"|g" "$deviceinfo_file"
        fi
    fi
}

# Clone or update the build tools repository
if [ ! -d build ]; then
    echo "Cloning build tools..."
    git clone -b $BUILD_TOOLS_BRANCH $BUILD_TOOLS_REPO build
else
    echo "Updating build tools..."
    git config --global --add safe.directory /Android-10/OnePlus/build
    cd build
    git pull origin $BUILD_TOOLS_BRANCH
    cd ..
fi

# Always remove and clone the overlay repository
echo "Removing old overlay directory..."
rm -rf overlay

echo "Cloning overlay repository..."
TEMP_DIR=$(mktemp -d)
git clone -b $ADAPTATION_OVERLAY_BRANCH $OVERLAY_REPO $TEMP_DIR

# Check if cloning was successful
if [ $? -ne 0 ]; then
    echo "Failed to clone overlay repository"
    exit 1
fi

# Move all files and directories, excluding .git, from temporary directory
echo "Moving files from temporary directory..."
shopt -s dotglob
mv $TEMP_DIR/* $TEMP_DIR/.[!.]* . 2>/dev/null || true
shopt -u dotglob

# Remove the temporary directory
echo "Removing temporary directory..."
rm -rf $TEMP_DIR

# Insert HAS_DYNAMIC_PARTITIONS=true in make-bootimage.sh if needed
if [ "$HAS_DYNAMIC_PARTITIONS" = true ]; then
    echo "Inserting HAS_DYNAMIC_PARTITIONS=true in make-bootimage.sh..."
    grep -qxF '    HAS_DYNAMIC_PARTITIONS=true' ./build/make-bootimage.sh || sed -i '43 i\    HAS_DYNAMIC_PARTITIONS=true' ./build/make-bootimage.sh
fi

# Modify system-image-from-ota.sh
modify_system_image_script

# Set recovery partition option in deviceinfo
set_deviceinfo_option "deviceinfo_has_recovery_partition" $INCLUDE_RECOVERY_PARTITION

# Set vbmeta option in deviceinfo
set_deviceinfo_option "deviceinfo_bootimg_append_vbmeta" $INCLUDE_VBMETA

# Disable set -x for recovery downloads
set +x
# Create the Images/recovery directory and download recovery images if it doesn't exist
if [ ! -d Images/recovery ]; then
    echo "Creating Images/recovery directory and downloading recovery images..."
    mkdir -p Images/recovery
    download_files
fi

# Modify line 57 in build-kernel.sh to use the number of cores specified in the config
echo "Modifying line 57 in build-kernel.sh..."
sed -i "57s/.*/make O=\"\$OUT\" \$MAKEOPTS -j$MAKE_CORES/" ./build/build-kernel.sh

# Insert clear command at line 2 in build.sh if needed
if [ "$INSERT_CLEAR_COMMAND" = true ]; then
    echo "Inserting clear command in build.sh..."
    sed -i '2 i\clear' ./build/build.sh
fi

# Check if vbmeta.img exists and copy it to the partitions directory
if [ "$INCLUDE_VBMETA" = true ]; then
    echo "Copying vbmeta.img to partitions..."
    if [ -f "${TMPDOWN}/vbmeta.img" ]; then
        cp "${TMPDOWN}/vbmeta.img" "${TMP}/partitions/vbmeta.img"
    fi
fi

# Re-enable set -x
set -x

# Execute the build script with passed arguments
echo "Starting build process..."
./build/build.sh "$@"

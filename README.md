# Ubuntu Touch for OnePlus 8 (instantnoodle)

## Contents
- [Ubuntu Touch Device Tree for the OnePlus 8 (instantnoodle)](#ubuntu-touch-device-tree-for-the-oneplus-8-instantnoodle)
  - [Contents](#contents)
- [Prerequisites and Warnings](#prerequisites-and-warnings)
  - [Setting up Your Build Environment](#setting-up-your-build-environment)
    - [How to Build](#how-to-build)
      - [How to Flash](#how-to-flash)
      - [Flashing Recovery](#flashing-recovery)
## Prerequisites and Warnings
> [!NOTE] 
> OnePlus 8 (instantnoodle).

> [!CAUTION]
> This guide involves procedures like unlocking the bootloader, flashing firmware, and modifying system components. These actions can potentially lead to negative outcomes, such as voiding your warranty, bricking your device, or compromising its security. Proceed with full understanding of the risks and ensure you follow the instructions carefully.

## Setting up Your Build Environment
**For amd64 architecture (commonly referred to as 64 bit)**:

Docker-Compose:
```bash
git clone https://github.com/scotthowson/Portable-Docker-Ubuntu
cd Portable-Docker-Ubuntu
```

Modify any Environment Variable that you need.
```bash
nano .env
```

```bash
docker-compose build --no-cache                                                                                                 ─╯
docker-compose up -d
docker exec -it Ubuntu-20.04 bash
```

### How to Build

```bash
git clone -b android-10-testing https://github.com/scotthowson/build_kernel_instantnoodle
cd build_kernel_instantnoodle
./build.sh                                                   # boot.img, recovery.img, dtbo.img, device tarball -> out/
./build/prepare-fake-ota.sh out/device_instantnoodle.tar.xz ota
./build/system-image-from-ota.sh ota/ubuntu_command out      # out/rootfs.img (flash as system)
```

The overlay lives in `./overlay`, the kernel defconfig fixes in `./kernel/`, and the review
notes in `PORTING_NOTES.md`. A GitHub Actions workflow (`.github/workflows/build.yml`) runs the
same build on a self-hosted runner.

To rebuild from scratch: `rm -rf build downloads out ota`.

## Delete logic partitions:
```console
fastboot delete-logical-partition system_ext_a
fastboot delete-logical-partition system_ext_b
fastboot delete-logical-partition product_a
fastboot delete-logical-partition product_b
fastboot delete-logical-partition system_b
fastboot delete-logical-partition vendor_b
fastboot delete-logical-partition odm_b
```

## How to Flash
### Using System Partition
```bash
adb devices
adb reboot fastboot
fastboot delete-logical-partition product_a
fastboot flash boot boot.img
fastboot flash system system.img
fastboot flash vbmeta --disable-verity --disable-verification vbmeta.img
```

# Formatting `userdata` (required for encryption)

The setup wizard only offers encryption when the ext4 filesystem on `userdata` has the `encrypt`
feature. `fastboot -w` and a plain `mkfs.ext4` do not set it. Format from recovery like this
before the first boot of a fresh install:

```sh
adb reboot recovery
adb shell umount /data 2>/dev/null
adb shell mke2fs -t ext4 -O encrypt,quota -F /dev/block/bootdevice/by-name/userdata
adb reboot
```

To keep an existing install and only add the feature (the wizard will not run again, so this is
useful for apps that use fscrypt directly, not for turning on home encryption):

```sh
adb shell tune2fs -O encrypt /dev/block/bootdevice/by-name/userdata   # from recovery, /data unmounted
```

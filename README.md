# Ubuntu Touch for the OnePlus 8 (instantnoodle)

Device adaptation for the OnePlus 8 on **Ubuntu Touch 24.04-2.x** (Halium 10, Android 10 vendor).
This repository holds everything except the kernel: the `deviceinfo` for the UBports generic
adaptation build tools, the system overlay, the recovery ramdisk and the CI workflows that
build and publish flashable images.

| Part | Repository / branch |
|---|---|
| This port | `scotthowson/build_kernel_instantnoodle`, branch `android-10-testing` |
| Kernel (4.19.81, ElementalX base) | `scotthowson/Ubuntu_ElementalX_OnePlus8`, branch `Halium-10` |
| Build tools | UBports `halium-generic-adaptation-build-tools`, branch `main` |

> [!CAUTION]
> Flashing requires an unlocked bootloader and replaces the Android system. It can void the
> warranty or brick the phone if done wrong. Read the whole install section before starting.

## Status

| Area | State |
|---|---|
| Boot, Lomiri UI, Android container (binderfs) | Working |
| Install wizard, home encryption | Working when userdata is formatted with the `encrypt` feature (see below) |
| WiFi (in-tree qcacld-3.0) | Working, MAC derived from the Bluetooth address |
| Bluetooth pairing | Working |
| Bluetooth audio | Not working (pulseaudio cannot load the Bluetooth audio HAL) |
| Cellular, SMS, data | Untested |
| Camera, sensors, GPS, NFC | Untested |
| Under-display fingerprint | Not working (HAL prerequisites and kernel hooks in place, userspace illumination pending) |
| Display | Working; occasional thin black dashes in GPU-rendered content under investigation |
| MTP, USB tethering, ADB, SSH | Working through usb-moded |

The full history, diagnoses and the ordered to-do list are in [`PORTING_NOTES.md`](PORTING_NOTES.md).

## Repository layout

| Path | Purpose |
|---|---|
| `deviceinfo` | Device description for the build tools: partitions, cmdline, kernel source, DTB/DTBO lists |
| `overlay/system/` | Files copied onto the rootfs (systemd units, udev rules, `halium.yaml`, Android property and init overrides) |
| `ramdisk-recovery.img`, `ramdisk-recovery-overlay/` | Prebuilt recovery ramdisk and its overrides (the recovery works and is kept as is) |
| `build.sh`, `build.conf` | Thin wrapper that clones the build tools and runs them |
| `tools/download-recovery-images.sh` | Fetches third-party recovery images for flashing; not used by the build |
| `.forgejo/workflows/`, `.github/workflows/` | CI that builds and publishes releases on a self-hosted runner |
| `kernel/` | Notes on the `Halium-10` kernel branch and the handoff log with the kernel work |
| `docs/UBUNTU-TOUCH-24.04.md` | What 24.04 changes for a Halium 10 port and how this port handles it |
| `RUNNER.md` | Setting up the GitHub or Forgejo runner |

## Building

Local build on any Debian/Ubuntu machine with the usual build packages (see the workflow for
the exact list):

```bash
git clone -b android-10-testing https://github.com/scotthowson/build_kernel_instantnoodle
cd build_kernel_instantnoodle
./build.sh                                                   # kernel + images, device tarball -> out/
./build/prepare-fake-ota.sh out/device_instantnoodle.tar.xz ota
./build/system-image-from-ota.sh ota/ubuntu_command out      # out/rootfs.img -> flash as system
```

`boot.img`, `dtbo.img` and `recovery.img` are inside `out/device_instantnoodle.tar.xz` under
`partitions/`. Use `./build.sh -c` to run menuconfig first, and `rm -rf build downloads out ota`
to start over.

## CI and releases

Every push to `android-10-testing` runs the build on the self-hosted runner and publishes a
pre-release `test-<run number>` containing:

- `boot.img`, `dtbo.img`, `recovery.img`
- `device_instantnoodle.tar.xz`
- `ubuntu.img.zst` (the system image, ready to flash after decompression)

A tag `v*` publishes a full release. A manual run can skip the flashable rootfs or the release,
and can build another kernel branch. Runner setup, caching and the Forgejo specifics are in
[`RUNNER.md`](RUNNER.md).

## Installing

Prerequisites: unlocked bootloader, OxygenOS 10 firmware on both slots (Android 10 vendor is
what the container runs), `adb` and `fastboot` on the PC, and the files from a release.

1. Format userdata **with the `encrypt` feature**. `fastboot -w` and a plain `mkfs.ext4` leave
   it out and the wizard then silently skips encryption. Erase from fastboot first: with an
   existing filesystem on the partition the recovery holds the device (even though `mount`
   shows nothing) and `mke2fs` refuses with "is mounted".

   ```sh
   adb reboot bootloader
   fastboot erase userdata
   fastboot reboot recovery
   adb wait-for-recovery
   adb shell mke2fs -t ext4 -O encrypt,quota -F /dev/block/bootdevice/by-name/userdata
   adb shell tune2fs -l /dev/block/bootdevice/by-name/userdata | grep -i features   # must list encrypt
   ```

2. Free space in `super` once (first install only):

   ```sh
   adb reboot bootloader
   fastboot reboot fastboot
   fastboot delete-logical-partition system_ext_a
   fastboot delete-logical-partition system_ext_b
   fastboot delete-logical-partition product_a
   fastboot delete-logical-partition product_b
   fastboot delete-logical-partition system_b
   fastboot delete-logical-partition vendor_b
   fastboot delete-logical-partition odm_b
   ```

3. Flash:

   ```sh
   fastboot reboot bootloader
   fastboot flash boot boot.img
   fastboot flash dtbo dtbo.img
   fastboot flash recovery recovery.img
   fastboot flash vbmeta --disable-verity --disable-verification vbmeta.img
   fastboot reboot fastboot
   zstd -d ubuntu.img.zst
   fastboot flash system ubuntu.img
   fastboot reboot
   ```

To add the `encrypt` feature to an existing install without wiping (for apps using fscrypt
directly; the wizard will not run again):

```sh
adb shell tune2fs -O encrypt /dev/block/bootdevice/by-name/userdata   # from recovery, /data unmounted
```

## Getting at the device

- `adb shell` works once the phone is booted and developer mode is enabled in System Settings.
- SSH over USB: `sudo systemctl enable --now ssh` on the phone once, then on the PC
  `adb forward tcp:2222 tcp:22` and `ssh -p 2222 phablet@localhost`.
- Logs: `journalctl -b`, `dmesg`, `lxc-info -n android`,
  `lxc-attach -n android -- logcat -d`. More in `docs/UBUNTU-TOUCH-24.04.md`.

## Documentation

- [`PORTING_NOTES.md`](PORTING_NOTES.md): review of the port, every fix with its reason, device
  findings, fingerprint status, ordered to-do list.
- [`docs/UBUNTU-TOUCH-24.04.md`](docs/UBUNTU-TOUCH-24.04.md): 24.04 reference for this device
  (boot chain, overlay files, install, access, logs, kernel requirements).
- [`kernel/README.md`](kernel/README.md) and [`kernel/HANDOFF.md`](kernel/HANDOFF.md): what the
  `Halium-10` kernel branch carries and the running handoff between the overlay and kernel work.
- [`RUNNER.md`](RUNNER.md): GitHub and Forgejo runner setup.

Reference ports used for comparison: UBports OnePlus Nord N10 (`oneplus-billie`) and
Nord N100 (`oneplus-billie2`).

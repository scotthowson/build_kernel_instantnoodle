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
| `docs/INSTALL.md` | Install guide for users and testers |
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

The full guide is [`docs/INSTALL.md`](docs/INSTALL.md): encrypted and unencrypted paths,
bootloader vs fastbootd, updates that keep data, kernel-only flashes, `fastboot boot` tests,
button combinations and troubleshooting. The short version for an encrypted fresh install
(slot A, logical partitions already trimmed as the guide describes):

```sh
adb reboot bootloader
fastboot set_active a
fastboot erase userdata                       # recovery otherwise holds the old fs
fastboot reboot recovery && adb wait-for-recovery
adb shell mke2fs -t ext4 -O encrypt,quota -F /dev/block/bootdevice/by-name/userdata
adb reboot bootloader
fastboot flash boot_a boot.img
fastboot flash dtbo_a dtbo.img
fastboot flash recovery_a recovery.img
fastboot flash vbmeta_a --disable-verity --disable-verification vbmeta.img
fastboot reboot fastboot                      # fastbootd
zstd -d ubuntu.img.zst && fastboot flash system_a ubuntu.img
fastboot reboot
```

For an unencrypted install replace the recovery lines with `fastboot format:ext4 userdata`.
`fastboot -w`, `fastboot format` and plain `mkfs.ext4` do not set the ext4 `encrypt` feature, and
the wizard then silently skips encryption.

## Getting at the device

- `adb shell` works once the phone is booted and developer mode is enabled in System Settings.
- SSH over USB: `sudo systemctl enable --now ssh` on the phone once, then on the PC
  `adb forward tcp:2222 tcp:22` and `ssh -p 2222 phablet@localhost`.
- Logs: `journalctl -b`, `dmesg`, `lxc-info -n android`,
  `lxc-attach -n android -- logcat -d`. More in `docs/UBUNTU-TOUCH-24.04.md`.

## Documentation

- [`PORTING_NOTES.md`](PORTING_NOTES.md): review of the port, every fix with its reason, device
  findings, fingerprint status, ordered to-do list.
- [`docs/INSTALL.md`](docs/INSTALL.md): install guide, encrypted and unencrypted, updating,
  troubleshooting.
- [`docs/UBUNTU-TOUCH-24.04.md`](docs/UBUNTU-TOUCH-24.04.md): 24.04 reference for this device
  (boot chain, overlay files, install, access, logs, kernel requirements).
- [`kernel/README.md`](kernel/README.md) and [`kernel/HANDOFF.md`](kernel/HANDOFF.md): what the
  `Halium-10` kernel branch carries and the running handoff between the overlay and kernel work.
- [`RUNNER.md`](RUNNER.md): GitHub and Forgejo runner setup.

Reference ports used for comparison: UBports OnePlus Nord N10 (`oneplus-billie`) and
Nord N100 (`oneplus-billie2`).

# Installing Ubuntu Touch on the OnePlus 8 (instantnoodle)

This guide takes a OnePlus 8 from OxygenOS 10 to Ubuntu Touch using the files from one release
of this repository. It covers an **encrypted** and an **unencrypted** install, updates that keep
your data, kernel testing, and what to do when the phone does not come back.

> [!CAUTION]
> A fresh install erases the user partition. The bootloader must be unlocked, which wipes the
> phone and may void the warranty. Follow the steps in order and use the images of a single
> release together; mixing releases is only for the kernel tests in section 8.

## Contents

1. [Before you start](#1-before-you-start)
2. [Bootloader or fastbootd?](#2-bootloader-or-fastbootd)
3. [One-time preparation: free space in super](#3-one-time-preparation-free-space-in-super)
4. [Choose: encrypted or unencrypted](#4-choose-encrypted-or-unencrypted)
5. [Format userdata](#5-format-userdata)
   - [Path A: encrypted](#path-a-encrypted)
   - [Path B: unencrypted](#path-b-unencrypted)
6. [Flash the images](#6-flash-the-images)
7. [First boot and checks](#7-first-boot-and-checks)
8. [Updating, kernel-only flashes and kernel tests](#8-updating-kernel-only-flashes-and-kernel-tests)
9. [Switching between encrypted and unencrypted](#9-switching-between-encrypted-and-unencrypted)
10. [Buttons](#10-buttons)
11. [Troubleshooting](#11-troubleshooting)

## 1. Before you start

**On the phone**

- OxygenOS **10** on both slots. The Android 10 vendor partition stays and is what the Ubuntu
  Touch container runs on. OxygenOS 11 or later firmware is not supported by this port.
- Bootloader unlocked (Settings, Developer options, OEM unlocking, then `fastboot oem unlock`).
- USB debugging enabled so `adb` works in Android and in recovery.

**On the PC**

- `adb` and `fastboot` from a recent Android platform-tools release.
- `zstd` to decompress the system image.
- The files from one release (Forgejo or GitHub releases, tag `test-<n>` or `v*`):

| File | Flashed to | Notes |
|---|---|---|
| `boot.img` | `boot_a` | Kernel and Halium ramdisk |
| `dtbo.img` | `dtbo_a` | Device tree overlays built from the kernel source |
| `recovery.img` | `recovery_a` | Recovery used for formatting and for pulling logs |
| `ubuntu.img.zst` | `system_a` (fastbootd) | The rootfs; decompress first |
| `vbmeta.img` | `vbmeta_a` | Stock file from the OxygenOS 10 firmware on the phone |

```sh
mkdir instantnoodle-ut && cd instantnoodle-ut
# copy boot.img dtbo.img recovery.img ubuntu.img.zst vbmeta.img here
zstd -d ubuntu.img.zst          # produces ubuntu.img
adb devices                     # phone listed as "device"
```

Slot **A** is used throughout. Partition names below carry the `_a` suffix so a command never
lands on the wrong slot.

## 2. Bootloader or fastbootd?

The phone has two fastboot modes and each accepts different commands.

```sh
fastboot getvar is-userspace
```

| Answer | Mode | Can do |
|---|---|---|
| `no` | bootloader | erase, format and flash of raw partitions (`boot`, `dtbo`, `recovery`, `vbmeta`, `userdata`), `boot <img>`, `set_active` |
| `yes` | fastbootd | flash of logical partitions (`system`, `vendor`, `product`), `delete-logical-partition` |

Switch with `fastboot reboot bootloader` and `fastboot reboot fastboot`. "partition size: 0" or
"Unrecognized command boot" means you are in the wrong one.

## 3. One-time preparation: free space in super

Ubuntu Touch's system image is larger than the OxygenOS `system_a` logical partition. On the
first install, delete the logical partitions Ubuntu Touch does not use so `system_a` can grow.
This is done once; repeat installs skip it.

```sh
adb reboot bootloader
fastboot reboot fastboot             # fastbootd; the screen says FASTBOOTD
fastboot delete-logical-partition system_ext_a
fastboot delete-logical-partition system_ext_b
fastboot delete-logical-partition product_a
fastboot delete-logical-partition product_b
fastboot delete-logical-partition system_b
fastboot delete-logical-partition vendor_b
fastboot delete-logical-partition odm_b
fastboot reboot bootloader
```

"Partition does not exist" on any of these means it was already deleted; carry on.

## 4. Choose: encrypted or unencrypted

| | Encrypted (Path A) | Unencrypted (Path B) |
|---|---|---|
| What is protected | `/home/phablet` and app data, fscrypt policy v2 | Nothing; data readable from recovery |
| Set up by | The first-boot wizard, when it finds the `encrypt` feature on userdata | Nothing to do; the wizard skips the encryption page |
| Unlock | Passcode or password required at boot | Lock screen only |
| Recovery access to `/data` | Home is encrypted; logs under `/data/system-data/var/log` stay readable | Everything readable |
| Good for | Daily use, a phone that leaves the house | Kernel testing, debugging a boot problem, throwaway tests |

The only difference between the two paths is **how userdata is formatted**. Everything else is
identical. The wizard offers encryption only when the ext4 filesystem on userdata carries the
`encrypt` feature flag; `fastboot -w`, `fastboot format userdata` and a plain `mkfs.ext4` do not
set it. While a kernel is under test, use Path B or skip the encryption page in the wizard so the
data stays readable from recovery.

## 5. Format userdata

Both paths start in the bootloader (`is-userspace: no`):

```sh
adb reboot bootloader
fastboot set_active a
```

### Path A: encrypted

Erase first. If a filesystem is already on the partition, the recovery holds the block device in
a way `mount` does not show, and `mke2fs` refuses with "is mounted". Erasing removes the
superblock so the recovery has nothing to grab.

```sh
fastboot erase userdata
fastboot reboot recovery
adb wait-for-recovery
adb shell mke2fs -t ext4 -O encrypt,quota -F /dev/block/bootdevice/by-name/userdata
```

Verify before leaving recovery. The features line **must** contain `encrypt`:

```sh
adb shell tune2fs -l /dev/block/bootdevice/by-name/userdata | grep -i features
# Filesystem features: has_journal ext_attr ... extent encrypt sparse_super ... quota
adb reboot bootloader
```

### Path B: unencrypted

Two commands from the bootloader; the result is ext4 without the `encrypt` feature:

```sh
fastboot erase userdata
fastboot format:ext4 userdata
```

`fastboot -w` does the same and also clears the `metadata` partition.

## 6. Flash the images

Raw partitions from the bootloader, the system image from fastbootd.

```sh
# bootloader (is-userspace: no)
fastboot flash boot_a boot.img
fastboot flash dtbo_a dtbo.img
fastboot flash recovery_a recovery.img
fastboot flash vbmeta_a --disable-verity --disable-verification vbmeta.img
fastboot reboot fastboot

# fastbootd (is-userspace: yes)
fastboot flash system_a ubuntu.img        # "Invalid sparse file format" warning is normal
fastboot reboot
```

The first boot takes a few minutes while the rootfs is set up.

## 7. First boot and checks

Walk through the wizard. On Path A it asks for a passcode or password and shows an encryption
step; on Path B it does not. Enable Developer Mode (Settings, About, Developer Mode) for `adb`.

```sh
adb shell
sudo fscrypt status /home/phablet           # Path A: "encrypted", policy version 2
                                            # Path B: "not encrypted" / "encryption not enabled"
cat /sys/class/net/wlan0/address            # 5c:17:cf:17:17:86 style, derived from the BT address
lxc-info -n android                         # STATE: RUNNING
uname -r; cat /proc/device-tree/model       # kernel version, "kona MTP dvt 19821 19855 14 15"
```

SSH over USB:

```sh
sudo systemctl enable --now ssh             # on the phone, once
adb forward tcp:2222 tcp:22                 # on the PC
ssh -p 2222 phablet@localhost
```

## 8. Updating, kernel-only flashes and kernel tests

**Full update, keeps data and encryption state.** Skip sections 3 and 5:

```sh
adb reboot bootloader
fastboot flash boot_a boot.img
fastboot flash dtbo_a dtbo.img
fastboot flash recovery_a recovery.img
fastboot reboot fastboot
fastboot flash system_a ubuntu.img
fastboot reboot
```

**Kernel only, keeps data and rootfs.** Bootloader:

```sh
fastboot flash boot_a boot.img
fastboot flash dtbo_a dtbo.img
fastboot flash recovery_a recovery.img
fastboot reboot
```

**Testing a kernel without flashing it.** The flashed kernel stays as the fallback; the test
kernel runs once from RAM with the flashed `dtbo`:

```sh
fastboot boot boot.img          # bootloader only; wait and watch
```

If it does not boot, force a reset and catch the bootloader (section 10), then:

```sh
fastboot set_active a           # a failed boot burns the slot's retry counter
fastboot reboot                 # back on the flashed kernel
```

For each test kernel, report: boots to UI, loops, or hangs, and the seconds from the OnePlus
logo to the reset.

## 9. Switching between encrypted and unencrypted

The wizard runs only on a fresh userdata, so switching means a wipe either way.

- **Unencrypted to encrypted:** back up, then [Path A](#path-a-encrypted) and [section 6](#6-flash-the-images).
- **Encrypted to unencrypted:** back up, then [Path B](#path-b-unencrypted) and [section 6](#6-flash-the-images).

Adding the `encrypt` feature to an existing unencrypted filesystem without wiping:

```sh
# from recovery, nothing mounted on /data
adb shell tune2fs -O encrypt /dev/block/bootdevice/by-name/userdata
```

This does **not** encrypt the home directory, because the wizard will not run again. It only lets
applications that use fscrypt directly create encrypted directories. For home encryption, wipe
and use Path A.

## 10. Buttons

| Want | Do |
|---|---|
| Force reset | hold Power + Volume Up about 10 s (up to 30 s from EDL) |
| Bootloader (fastboot) | from off, or right after the reset vibration: hold Volume Up + Volume Down, **cable unplugged** |
| Recovery | bootloader menu, or `fastboot reboot recovery` |
| Exit EDL (9008) | unplug the cable, hold Power + Volume Up until it restarts |

Volume Up + Volume Down with the cable plugged in enters EDL, not fastboot.

## 11. Troubleshooting

**`mke2fs` says "is mounted; will not make a filesystem here" while `mount` shows nothing.**
The recovery holds the existing filesystem; `umount /data` answers "Invalid argument" for the
same reason. Back to the bootloader, `fastboot erase userdata`, then Path A again.

**The wizard never showed an encryption step.**
Userdata was formatted without the `encrypt` feature (`fastboot -w`, `fastboot format` or
`mkfs.ext4`). Check with `tune2fs -l ... | grep features` from recovery. For encryption, wipe and
use Path A.

**`fscrypt status` says "encryption not enabled on filesystem /userdata".**
Same cause as above.

**A journal line `pam_fscrypt ... setting groups: operation not permitted` appears.**
Harmless on an unencrypted home. It is the lock screen's PAM stack finding nothing to unlock.

**`fastboot flash system_a` fails with "not enough space" or "partition too small".**
Section 3 was not done, or the phone is on slot B. In fastbootd run the delete commands again and
check `fastboot getvar current-slot` is `a`.

**The phone will not boot the kernel you just flashed.**
`fastboot getvar current-slot` and `fastboot getvar slot-unbootable:a`. After several failed
boots the bootloader marks the slot unbootable and switches to slot B, which has no rootfs.
`fastboot set_active a` fixes it. Then see whether the kernel got anywhere: `lsusb | grep -i 2a70`
and `ip link` on the PC (a new `enx...` or OnePlus 8 interface). No device at all means the
kernel did not reach the USB gadget. Device present but no UI means the kernel is up; ssh in and
read `dmesg`. ramoops/pstore does not survive a reset on this device; do not rely on it.

**The phone stays on the OnePlus logo or bootloops, and USB is up.**
Pull the journal from recovery and read it on the PC:

```sh
adb reboot recovery
adb shell mount /dev/block/bootdevice/by-name/userdata /data
adb pull /data/system-data/var/log/journal ./journal
journalctl -D ./journal --list-boots
journalctl -D ./journal -b -1 -p warning
```

On an encrypted install the journal is outside the encrypted home and is still readable this way.
More in `docs/UBUNTU-TOUCH-24.04.md`, section 6.

**Going back to Android.**
Flash a full OxygenOS 10 package with the MSM tool or a fastboot ROM. The stock `super` image
recreates the deleted logical partitions.

## Building the rootfs image yourself

```sh
./build.sh
./build/prepare-fake-ota.sh out/device_instantnoodle.tar.xz ota
./build/system-image-from-ota.sh ota/ubuntu_command out    # out/rootfs.img, flash as system_a
```

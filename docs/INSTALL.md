# Installing Ubuntu Touch on the OnePlus 8 (instantnoodle)

This guide takes a OnePlus 8 from OxygenOS to Ubuntu Touch using the files from a release of
this repository. It covers both an **encrypted** and an **unencrypted** install, and how to go
from one to the other.

> [!CAUTION]
> Everything on the phone's user partition is erased. The bootloader must be unlocked, which
> wipes the phone and may void the warranty. Follow the steps in order.

## Contents

1. [Before you start](#1-before-you-start)
2. [Choose: encrypted or unencrypted](#2-choose-encrypted-or-unencrypted)
3. [Format userdata](#3-format-userdata)
   - [Path A: encrypted](#path-a-encrypted)
   - [Path B: unencrypted](#path-b-unencrypted)
4. [First install only: free space in super](#4-first-install-only-free-space-in-super)
5. [Flash the images](#5-flash-the-images)
6. [First boot and checks](#6-first-boot-and-checks)
7. [Updating an existing install](#7-updating-an-existing-install)
8. [Switching between encrypted and unencrypted](#8-switching-between-encrypted-and-unencrypted)
9. [Troubleshooting](#9-troubleshooting)

## 1. Before you start

**On the phone**

- OxygenOS **10** installed on both slots. The Android 10 vendor partition stays and is what
  the Ubuntu Touch container runs on. OxygenOS 11 or later firmware is not supported by this port.
- Bootloader unlocked (Settings, Developer options, OEM unlocking, then `fastboot oem unlock`).
- USB debugging enabled so `adb` works in Android and in recovery.

**On the PC**

- `adb` and `fastboot` from a recent Android platform-tools release.
- `zstd` to decompress the system image.
- The release files from this repository (Forgejo or GitHub releases, tag `test-<n>` or `v*`):

| File | Flashed to | Notes |
|---|---|---|
| `boot.img` | `boot` | Kernel and Halium ramdisk |
| `dtbo.img` | `dtbo` | Device tree overlays built from the kernel source |
| `recovery.img` | `recovery` | Recovery used for formatting and for pulling logs |
| `ubuntu.img.zst` | `system` (via fastbootd) | The rootfs; decompress first |
| `vbmeta.img` | `vbmeta` | Take it from the OxygenOS 10 firmware you have on the phone |

Download and unpack:

```sh
mkdir instantnoodle-ut && cd instantnoodle-ut
# copy boot.img dtbo.img recovery.img ubuntu.img.zst vbmeta.img here
zstd -d ubuntu.img.zst          # produces ubuntu.img
```

Quick sanity check of the connection:

```sh
adb devices          # phone listed as "device"
```

## 2. Choose: encrypted or unencrypted

| | Encrypted (Path A) | Unencrypted (Path B) |
|---|---|---|
| What is protected | `/home/phablet` and app data, with fscrypt policy v2 | Nothing; data readable from recovery |
| Set up by | The first-boot wizard, when it finds the `encrypt` feature on userdata | Nothing to do; the wizard skips the encryption page |
| Unlock | Passcode or password required at boot | Lock screen only |
| Recovery access to `/data` | Files are encrypted; logs under `/data/system-data/var/log` are still readable | Everything readable |
| Good for | Daily use, a phone that leaves the house | Debugging a boot problem, quick throwaway tests |

The only difference between the two paths is **how userdata is formatted**. Everything else is
identical. The wizard offers encryption only when the ext4 filesystem on userdata carries the
`encrypt` feature flag; `fastboot -w`, `fastboot format userdata` and a plain `mkfs.ext4` do not
set it.

## 3. Format userdata

Both paths start in fastboot:

```sh
adb reboot bootloader
fastboot devices        # phone listed
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
```

Then back to the bootloader:

```sh
adb reboot bootloader
```

### Path B: unencrypted

One command from fastboot; it creates an ext4 filesystem without the `encrypt` feature:

```sh
fastboot format userdata
```

Alternatively `fastboot -w`, which also clears the `metadata` partition. Either way the wizard
will not show an encryption page, and the phone comes up unencrypted.

## 4. First install only: free space in super

Ubuntu Touch's system image is larger than the OxygenOS `system_a` logical partition. On the
first install, delete the logical partitions that Ubuntu Touch does not use so `system_a` can
grow. This is done once; repeat installs skip it.

```sh
fastboot reboot fastboot          # enters fastbootd (userspace fastboot); the screen says FASTBOOTD
fastboot delete-logical-partition system_ext_a
fastboot delete-logical-partition system_ext_b
fastboot delete-logical-partition product_a
fastboot delete-logical-partition product_b
fastboot delete-logical-partition system_b
fastboot delete-logical-partition vendor_b
fastboot delete-logical-partition odm_b
```

"Partition does not exist" on any of these means it was already deleted; carry on. Stay in
fastbootd for the next section.

## 5. Flash the images

The physical partitions are flashed from the bootloader, the system image from fastbootd.

```sh
fastboot reboot bootloader
fastboot flash boot boot.img
fastboot flash dtbo dtbo.img
fastboot flash recovery recovery.img
fastboot flash vbmeta --disable-verity --disable-verification vbmeta.img

fastboot reboot fastboot          # fastbootd again
fastboot flash system ubuntu.img
fastboot reboot
```

The first boot takes a minute or two longer than usual while the rootfs is set up.

## 6. First boot and checks

Walk through the wizard. On Path A it asks for a passcode or password and shows an encryption
step; on Path B it does not.

Once on the home screen, from the PC:

```sh
adb shell                                   # developer mode must be on in System Settings
sudo fscrypt status /home/phablet           # Path A: "encrypted" with policy version 2
                                            # Path B: "not encrypted" / "encryption not enabled"
cat /sys/class/net/wlan0/address            # 5c:17:cf:17:17:86 style address derived from the BT address
lxc-info -n android                         # STATE: RUNNING
uname -r; cat /proc/device-tree/model       # kernel version, "kona MTP dvt 19821 19855 14 15"
```

SSH over USB, if preferred:

```sh
# on the phone, once
sudo systemctl enable --now ssh
# on the PC
adb forward tcp:2222 tcp:22
ssh -p 2222 phablet@localhost
```

## 7. Updating an existing install

To move to a newer release and **keep your data and the encryption state**, skip sections 3 and
4 and flash only what changed:

```sh
adb reboot bootloader
fastboot flash boot boot.img
fastboot flash dtbo dtbo.img
fastboot reboot fastboot
fastboot flash system ubuntu.img
fastboot reboot
```

`recovery.img` and `vbmeta.img` only need reflashing when the release notes say so.

## 8. Switching between encrypted and unencrypted

The wizard runs only on a fresh userdata, so switching means a wipe either way.

- **Unencrypted to encrypted:** back up what you need, then do [Path A](#path-a-encrypted) and
  [section 5](#5-flash-the-images).
- **Encrypted to unencrypted:** back up, then [Path B](#path-b-unencrypted) and
  [section 5](#5-flash-the-images).

Adding the `encrypt` feature to an existing unencrypted filesystem without wiping is possible:

```sh
# from recovery, nothing mounted on /data
adb shell tune2fs -O encrypt /dev/block/bootdevice/by-name/userdata
```

This does **not** encrypt the home directory, because the wizard will not run again. It only
lets applications that use fscrypt directly create encrypted directories. For home encryption,
wipe and use Path A.

## 9. Troubleshooting

**`mke2fs` says "is mounted; will not make a filesystem here" while `mount` shows nothing.**
The recovery holds the existing filesystem. `umount /data` answers "Invalid argument" for the
same reason. Go back to the bootloader and run `fastboot erase userdata` first, as in Path A.

**The wizard never showed an encryption step.**
Userdata was formatted without the `encrypt` feature (`fastboot -w`, `fastboot format` or
`mkfs.ext4`). Check with `tune2fs -l ... | grep features` from recovery. To get encryption, wipe
and use Path A.

**`fscrypt status` says "encryption not enabled on filesystem /userdata".**
Same cause as above.

**A journal line `pam_fscrypt ... setting groups: operation not permitted` appears.**
Harmless on an unencrypted home. It is the lock screen's PAM stack finding nothing to unlock.

**`fastboot flash system` fails with "not enough space" or "partition too small".**
The logical partitions from section 4 were not deleted, or the phone is on the other slot.
Enter fastbootd, run the delete commands again, and check `fastboot getvar current-slot` is `a`.

**The phone stays on the OnePlus logo or bootloops.**
Pull the journal from recovery and read it on the PC:

```sh
adb reboot recovery
adb shell mount /dev/block/bootdevice/by-name/userdata /data
adb pull /data/system-data/var/log/journal ./journal
journalctl -D ./journal --list-boots
journalctl -D ./journal -b -1 -p warning
```

On an encrypted install the journal is outside the encrypted home and is still readable this
way. For deeper log reading, see `docs/UBUNTU-TOUCH-24.04.md`, section 6.

**Going back to Android.**
Flash a full OxygenOS 10 package with the MSM tool or a fastboot ROM. The deleted logical
partitions are recreated by the stock `super` image.

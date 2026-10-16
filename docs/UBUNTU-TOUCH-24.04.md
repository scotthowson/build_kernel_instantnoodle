# Ubuntu Touch 24.04 on a Halium 10 device: what is different, and how this port handles it

Scope: OnePlus 8 (instantnoodle), rootfs channel `24.04-2.x`, Halium 10 (Android 10 vendor),
kernel 4.19.81 (Ubuntu_ElementalX_OnePlus8, branch Halium-10). Written for whoever works on the
kernel or the overlay next. Everything here was verified on the device unless marked otherwise.

## 1. What 24.04 changed compared to 20.04 ports

| Area | 20.04 (focal) | 24.04 (noble) | Consequence for this port |
|---|---|---|---|
| Init | systemd + upstart user session | systemd only | Every `overlay/system/etc/init/*.conf`/`*.override` and `usr/share/upstart/sessions/*` is inert. Kept for parity with reference ports only. Real units live in `usr/lib/systemd/system` (system) and `usr/lib/systemd/user` (session). |
| Android container | lxc with static `/dev/binder*` | lxc-android-config bind-mounts `/dev/binderfs` into the container | Kernel needs `CONFIG_ANDROID_BINDERFS=y` (backported into 4.19). The overlay's `android-binderfs.service` mounts binderfs early. Without it the container never starts: black screen, every binder client times out. |
| cgroups | hybrid (v1 controllers) | cgroup v2 | Do **not** add `systemd.unified_cgroup_hierarchy=0` to the cmdline. |
| Home encryption | fscrypt policy v1 | fscrypt policy v2 (`etc/fscrypt.conf`) | Kernel needs fscrypt v2 (`fs/crypto/keyring.c`, `FSCRYPT_POLICY_V2`). The userdata ext4 must carry the `encrypt` feature or the wizard skips the encryption page (see 4). |
| Firmware loading | same | same | Firmware is loaded through the container's `ueventd` (sysfs fallback), so drivers that request firmware must do so after the container is up. |
| Device files | overlay copied into rootfs | overlay copied into rootfs, or "overlay store" (bind-mounted at boot) | `deviceinfo_use_overlaystore` stays off: the store can only overlay paths that already exist in the rootfs and silently drops new files. |
| Node | Node 12 in Ubuntu 22.04 CI image | JavaScript actions need Node 20 | Forgejo CI installs Node 20 from NodeSource before `actions/checkout`. |

## 2. Boot chain on this device

1. ABL loads `boot.img` (header v2, kernel + halium initramfs + concatenated kona DTBs), picks the DTB and
   DTBO by msm-id/board-id (`androidboot.dtb_idx`, `androidboot.dtbo_idx` in `/proc/cmdline`).
2. halium initramfs finds `systempart=/dev/mapper/system_a` (dynamic partition) and switches root.
3. systemd: `mount-android-partitions` (vendor, odm, persist, modem, dsp, bt_firmware),
   `android-binderfs.service` (ours), `lxc-android-config` starts the container.
4. Container init runs stock `init.*.rc`; `sys.boot_completed=1` marks it ready.
5. `android-wlan-on.service` (ours) waits for that property, writes the WLAN MAC file, then
   `echo ON > /dev/wlan` so the in-kernel qcacld-3.0 probes and creates `wlan0`.
6. `bluebinder` (with our drop-in) waits for `init.svc.vendor.bluetooth-1-0-qti=running`, then
   bridges the HAL to `/dev/vhci` -> `hci0`.
7. lightdm -> Lomiri.

## 3. Files this port adds or changes in the overlay (all under `overlay/system`)

- `usr/lib/systemd/system/android-binderfs.service` + `etc/systemd/system/sysinit.target.wants/`
- `usr/lib/systemd/system/android-wlan-on.service` + `etc/systemd/system/multi-user.target.wants/`
- `usr/bin/instantnoodle-wlan-mac` (MAC from the Bluetooth address into the persist files that
  `/vendor/firmware/wlan/qca_cld/wlan_mac.bin` links to)
- `etc/systemd/system/bluebinder.service.d/override.conf` (HAL wait, StartLimit keys in `[Unit]`)
- `etc/udev/rules.d/80-net-setup-link.rules` (empty: keeps `wlan0` instead of `wlp1s0`)
- `etc/deviceinfo/devices/halium.yaml` (grid unit 21, torch/backlight paths, panel height 104,
  display cutouts for the punch hole; `udfpLocationX/Y`, `udfpSensorRadius` are the keys Lomiri
  reads once under-display fingerprint is wired up)
- `etc/fscrypt.conf` policy v2
- `usr/share/halium-overlay/vendor/etc/init/hw/init.qcom.usb.rc` (bind-mounted over the stock
  file; carries the Android properties the port sets, disables `time_daemon`, and creates
  `/data/media/0` for the fingerprint HAL on `post-fs-data`). New files cannot be added under
  `usr/share/halium-overlay`: `mount-halium-overlay` only bind-mounts over paths that already
  exist in `/android/system` or `/android/vendor`, so additions go into an existing file.
- `usr/share/halium-overlay/vendor/build.prop` (full replacement of the stock vendor build.prop)

## 4. Installing for a test

```sh
adb reboot bootloader
fastboot erase userdata                 # the recovery holds an existing fs, mke2fs would say "is mounted"
fastboot reboot recovery
adb wait-for-recovery
adb shell mke2fs -t ext4 -O encrypt,quota -F /dev/block/bootdevice/by-name/userdata   # encrypt flag!
adb shell tune2fs -l /dev/block/bootdevice/by-name/userdata | grep -i features        # must list encrypt
adb reboot bootloader
fastboot flash boot boot.img
fastboot flash dtbo dtbo.img
fastboot flash recovery recovery.img
fastboot flash vbmeta --disable-verity --disable-verification vbmeta.img
fastboot reboot fastboot
fastboot flash system ubuntu.img        # from ubuntu.img.zst in the release
fastboot reboot
```

`fastboot -w` must not be used for the wipe: it formats userdata without the `encrypt` feature and
the wizard will silently skip encryption.

## 5. Getting at the device

adb works out of the box on these images (`adb shell` lands in the `phablet` user; `sudo` with the
wizard password). SSH:

```sh
adb shell mkdir -p /home/phablet/.ssh
adb push ~/.ssh/id_ed25519.pub /home/phablet/.ssh/authorized_keys
adb shell chmod 700 /home/phablet/.ssh && adb shell chmod 600 /home/phablet/.ssh/authorized_keys
adb shell sudo systemctl enable --now ssh
adb forward tcp:2222 tcp:22 && ssh -p 2222 phablet@localhost      # over USB
ssh phablet@<wifi address>                                       # over WiFi
```

sshd is key-only; `android-gadget-service` does not exist on 24.04.

### Enabling sshd in every build (development images only)

Add the enable symlink to the overlay, the same way the other units are enabled:

```sh
mkdir -p overlay/system/etc/systemd/system/multi-user.target.wants
ln -s /usr/lib/systemd/system/ssh.service overlay/system/etc/systemd/system/multi-user.target.wants/ssh.service
```

Keys still have to be pushed once per install (home is on userdata, not in the image). Do not ship
this in an image handed to other people.

## 6. Reading logs

```sh
journalctl -b --no-pager | tail -200                      # system
journalctl --user -b --no-pager | tail -100               # Lomiri session (as phablet)
dmesg | tail -100
lxc-attach -n android -- getprop | grep init.svc           # container services
lxc-attach -n android -- logcat -d | tail -200             # Android side
cat /proc/cmdline; cat /proc/device-tree/model
```

If the UI never shows but adb works: check `lxc-info -n android` first (STATE must be RUNNING); the
usual culprit is the container, not the kernel.

If nothing is reachable: pull the journal from recovery
(`adb shell mount /dev/block/bootdevice/by-name/userdata /data && adb pull /data/system-data/var/log/journal`)
and read it on the PC with `journalctl -D ./journal --list-boots`. pstore is usually empty after a
hard power-off.

## 7. Kernel requirements that bit us (all fixed on Halium-10)

- `CONFIG_ANDROID_BINDERFS=y` (backport) - container start
- fscrypt v2 backport - home encryption
- `CONFIG_LOCALVERSION="-perf"` would only matter for vendor modules; the WLAN driver is now in-tree
  (`CONFIG_QCA_CLD_WLAN=y`), so vendor `.ko` files are not used at all
- WireGuard vendored in `net/wireguard` (the stock fetch script downloads it at build time and the
  host is unreliable); keep `CONFIG_WIREGUARD=y`, Ubuntu Touch's VPN uses it
- Device trees are built from source (`deviceinfo_dtb`, `deviceinfo_dtbo`); the old prebuilt
  `.dtb`/`dtbo.img` were of mixed origin and are gone

## 8. Open items

See `PORTING_NOTES.md`, "Things still to do", for the live list. In short:

- Encryption and fscrypt policy v2 to be confirmed on an install formatted with `-O encrypt,quota`.
- WLAN MAC persistence (`5c:17:cf:17:17:86` expected on `wlan0`).
- Thin black dashes in GPU-rendered content (GPU buffer tiles; `vendor.gralloc.disable_ubwc=1`
  under test). No Qt environment workarounds are to be added.
- Under-display fingerprint: not working. The kernel enabler and the two HAL prerequisites
  (`/data/media/0` in the container, stock file names on persist) are in place; the illumination
  service and the Lomiri sensor spot are userspace work still to do.
- Bluetooth audio HAL for pulseaudio.
- Punch-hole cutout width and the notifications indicator position in `halium.yaml`.

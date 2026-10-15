# OnePlus 8 (instantnoodle) Ubuntu Touch port — review and fix list

Reviewed on 2026-10-14 against:

- this repository (`android-10-testing`)
- the overlay repository `scotthowson/oneplus8_ubuntu_adaptation`, branch `a10-testing` (the branch `build.conf` pointed at)
- the kernel `scotthowson/Ubuntu_ElementalX_OnePlus8`, branch `Halium-10`, defconfig `halium-instantnoodle_ubuntu_defconfig`
- the UBports reference ports for OnePlus Nord N10 (`oneplus-billie`) and Nord N100 (`oneplus-billie2`) and the current `halium-generic-adaptation-build-tools`

## What was wrong, by severity

### Kernel (all of this is now committed on `Halium-10`; see `kernel/README.md`)

1. ~~Firmware loading was compiled out.~~ **Correction (2026-10-15):** expanding the old defconfig with
   kconfig gives `CONFIG_FW_LOADER=y` in both the old and the new version. `FW_LOADER` is selected by
   many drivers, so the `# CONFIG_FW_LOADER is not set` line was overridden and firmware loading always
   worked. The effective changes of that patch were `-perf`, `AUTOFS4_FS` and the AppArmor boot
   default. The defconfig has since been regenerated in `savedefconfig` form, which removes such
   misleading lines.
2. **The WLAN driver is not in the kernel tree.** `CONFIG_QCA_CLD_WLAN=y` is a dead option: there is no
   `qcacld-3.0` directory anywhere in the tree. WiFi therefore depends on the stock prebuilt
   `/vendor/lib/modules/qca_cld3_wlan.ko`, which only loads if the kernel vermagic matches
   (`4.19.81-perf`). The kernel used `CONFIG_LOCALVERSION="-howsondev"`. Both reference ports keep
   `-perf` for this reason. **Superseded (2026-10-15):** the driver (qcacld-3.0, qca-wifi-host-cmn,
   fw-api from LineageOS 18.1's OnePlus 8 kernel) is now built into the kernel
   (`CONFIG_QCA_CLD_WLAN=y`), so the vendor module and its vermagic/CRC match no longer matter.
3. **No fscrypt v2 support** (no `fs/crypto/keyring.c`, no `FSCRYPT_POLICY_V2`), but the overlay's
   `fscrypt.conf` asked for policy v2. First-boot encryption cannot succeed that way. Overlay now uses
   v1. **Update (2026-10-15):** the Nord N10 fscrypt v2 commit is cherry-picked onto `Halium-10`;
   switch `overlay/system/etc/fscrypt.conf` back to `"policy_version": "2"` once a build with it has
   encrypted a fresh install successfully.
4. `CONFIG_CMDLINE="systemd.unified_cgroup_hierarchy=0"` is ignored (bootloader cmdline wins), so the
   booting build has always run on cgroup v2, which is what Ubuntu Touch 24.04 expects. The parameter
   was briefly added to `deviceinfo_kernel_cmdline` and removed again after a non-booting test; leave
   it out.
5. `CONFIG_SECURITY_APPARMOR_BOOTPARAM_VALUE=0` → `1`; `CONFIG_AUTOFS4_FS=y` for systemd automounts.

### deviceinfo / build tooling (fixed here)

6. `deviceinfo_ubuntu_touch_release="noble"` is not a valid value; `prepare-fake-ota.sh` aborts with
   "Unsupported ubuntu touch release". Now `24.04-2.x`.
7. The old `build.sh` patched the build tools by line number. `sed '43 i HAS_DYNAMIC_PARTITIONS=true'`
   now lands inside a `case` block in `make-bootimage.sh` and breaks it; the tools already detect dynamic
   partitions from `systempart=/dev/mapper`. The line-57 `make -j` edit was coincidentally still right.
   Both hacks and the runtime edits to `deviceinfo` are gone; `build.sh` is now a thin wrapper.
8. Unknown deviceinfo keys removed (`deviceinfo_recovery_dtbo`). The recovery is unchanged: the prebuilt
   `ramdisk-recovery.img` plus `ramdisk-recovery-overlay/` is known to work on the device, so it stays.
   (The UBports unified recovery is noted in `deviceinfo` as the alternative current ports use; the
   `prop.default` in the overlay is a OnePlus 8 Pro LineageOS prop dump and could be trimmed later.)
9. `deviceinfo_use_overlaystore` stays off. It was enabled briefly; the build that boots uses the
   normal tarball layout, so the overlay store is a separate experiment for later.
10. `.gitignore` listed tracked files; cleaned up.

### Overlay (now in `./overlay`, no longer cloned from a second repository)

11. `etc/init/mount-android.conf` bind-mounted `vendor/etc/init/hw/init.oem.rc`, a file the `a10-testing`
    overlay deleted. Upstart runs scripts with `sh -e`, so the failing mount aborted the job before the
    cache bind-mount, `time_daemon` disable and `mounted-android` emit. Line removed.
12. `etc/modules-load.d/connectivity.conf` asked systemd to load `qca_cld3_wlan` and `mpq-adapter` from
    `/lib/modules`, where they do not exist (failed unit every boot). Removed; the Nord N100 port has no
    such file. The WLAN module is loaded by the stock `init.target.rc` (`modprobe -d /vendor/lib/modules`).
13. The `init.qcom.usb.rc` override also ran `insmod /system/vendor/lib/modules/qca_cld3_wlan.ko` at
    `on boot`, racing the stock modprobe. Removed.
14. `etc/fscrypt.conf`: policy v2 → v1 (see kernel item 3).
15. `usb-moded` config used Sony's USB vendor ID (`0FCE`); now OnePlus (`2A70`).
16. `repowerd/device-configs/config-OnePlus8.xml` renamed to `config-default.xml` so it is picked
    regardless of how the device name is detected (matches reference ports).
17. `audiosystem-passthrough-qti.service` also checks `/vendor/manifest.xml` for `IQcRilAudio`.
18. Removed stray `.halium-override-dir` / `.halium-overlay-dir` marker files that sat next to
    real files and had no effect there.

### Verified against the OnePlus 8 device tree (LineageOS sm8250-common / instantnoodle)

- `halium.yaml`: backlight `/sys/class/backlight/panel0-backlight` and torch `led:torch_0` /
  `led:switch_0` are the nodes OnePlus's `init.oem.rc` sets up. GridUnit 21 = stock
  `ro.sf.lcd_density` 420 / 20, the usual Ubuntu Touch formula.
- `deviceinfo` cmdline, page size, header v2, offsets, boot and recovery partition sizes
  (100663296) all match `BoardConfigCommon.mk`.
- udev rules: every node in the stock `ueventd.rc` is covered; the five that were missing
  (`mhi_*_pipe_4`, `spu_hal_ssr`, `iuicc*`, `reserve1`) were added, plus `/dev/vhci` for bluebinder.
- usb-moded: idVendor `2A70` (OnePlus), MTP `4EE1`, MTP+ADB `4EE2`, RNDIS `F00E`, RNDIS+ADB
  `9024`, taken from the stock `init.qcom.usb.rc` / AOSP configfs defaults.
- ofono: dual slot (`/ril_0`, `/ril_1`) with the qti binder plugin at radio interface 1.4 is what
  the Android 10 vendor exposes; same file as the Nord N10 port.
- pulse `touch.pa`: `module-droid-card-28` is the right droid module for Halium 9/10 vendors.
- `recovery.fstab`: matches the stock `fstab.qcom` for the partitions recovery needs (system,
  vendor, metadata, userdata, persist, misc, modem, dsp, bluetooth) plus boot/dtbo for flashing.
  Differences are intentional: userdata as ext4 (Ubuntu Touch formats ext4), no `op2`/`odm`
  (mounted by the Android container itself). The two `sdcard1` lines are harmless; the OnePlus 8
  has no SD slot.

Kept as-is: `vendor/build.prop`, `device-hacks`, `sound-script`, `check-audio-mic`.

## Diagnosis of the 2026-10-15 non-boot

The journal of the failed boot shows systemd and lightdm running for 22 minutes with a black screen.
The Android container never started: `lxc-start: Failed to mount "/dev/binderfs"`. The 24.04-2.x
rootfs requires binderfs and the kernel has none (`drivers/android/binderfs.c` is absent; the
`CONFIG_ANDROID_BINDERFS=n` line is a no-op). The overlay store mode also dropped most device files
("doesn't exist, cannot overlay") and has been reverted. Kernel work is in `kernel/HANDOFF.md`.

Resolution (2026-10-15): binderfs is backported on `Halium-10` (`CONFIG_ANDROID_BINDERFS=y`, static
binder devices kept for the Android 10 container), and the overlay gained
`usr/lib/systemd/system/android-binderfs.service`, which mounts binderfs on `/dev/binderfs` early so
the container's bind mount has a source whether or not the rootfs marks it `optional`.

## WiFi and Bluetooth on the in-tree driver kernel (2026-10-15)

With qcacld-3.0 built into the kernel, the device boots, the container runs, cnss2 completes cold-boot
calibration and loads amss20.bin / 12wlan.t0a / m3.bin via the container's ueventd. Two userspace
pieces were missing:

- `wlan0` never appeared: the built-in driver waits for `echo ON > /dev/wlan` (the Android WiFi HAL's
  job on stock). `android-wlan-on.service` does it after `sys.boot_completed`, retrying until wlan0
  exists. The old `etc/init/urfkill.override` (insmod of the vendor module) is removed. Verified on
  the device: `echo ON > /dev/wlan` creates wlan0 and p2p0 within a few seconds. systemd then renamed
  it to `wlp1s0` (PCIe naming); an empty `etc/udev/rules.d/80-net-setup-link.rules` masks the rename.
  `instantnoodle-wlan-mac` (ExecStartPre of the unit) derives a per-device MAC from the Bluetooth
  address and writes it to `persist/wlan_mac.bin` and `persist/qca6390/wlan_mac.bin`, which
  `/vendor/firmware/wlan/qca_cld/wlan_mac.bin` links to; without it the driver uses one default MAC
  on every device.
- bluebinder sat in "Waiting for bluetooth service": the HAL runs as `vendor.bluetooth-1-0-qti` and a
  second bluetooth-named service exists, so the stock wait script's `uniq` check never settles.
  `bluebinder.service.d/override.conf` waits for `init.svc.vendor.bluetooth-1-0-qti=running` instead.
  Verified on the device: with the wait skipped, bluebinder starts and `hci0` appears with the
  OnePlus address. `bluebinder_post.sh` logs "Failed to get bluetooth address" but the HAL has
  already set it; cosmetic.

## Status after the first full install on kernel e6490e833 (2026-10-15)

Confirmed on device: boot, UI, Android container over binderfs, install wizard, WiFi (in-tree
qcacld-3.0), Bluetooth (bluebinder). cpufreq governor is schedutil on all clusters,
`lpm_levels.sleep_disabled` reads N after boot (Android's post-boot script clears it, keep `=1` in
the cmdline like stock), I/O scheduler cfq like stock, persist is mounted at `/mnt/vendor/persist`
inside the container.

Kernel side since then (d3d220bd6): debug options dropped, DSI backlight log spam removed,
schedutil default, dtc overlay warnings silenced, device trees built with the in-tree dtc, overlay
list reduced to instantnoodle, and the fingerprint enabler (see below), inactive unless written.

`overlay/system/etc/fscrypt.conf` is on `"policy_version": "2"` (the kernel has fscrypt v2).
The first two installs came up unencrypted with no encryption step in the wizard: `fscrypt status`
showed "encryption not enabled on filesystem /userdata", i.e. the ext4 `encrypt` feature flag was
missing because userdata had been formatted with `fastboot -w` / plain `mkfs.ext4`. Format from
recovery with `mke2fs -t ext4 -O encrypt,quota` (see README) and the wizard offers encryption.
Policy v2 is to be confirmed on the first install made that way. The
`pam_fscrypt ... setting groups: operation not permitted` journal line is the lock screen's PAM
stack on an unencrypted home and is harmless.

### Graphics artifacts

Random thin black horizontal dashes in GPU-rendered content, present on the previous kernel too.
They are GPU buffer tiles: unaffected by GPU clock or Qt batching, so not a kernel or Qt issue.
Being tested live: `vendor.gralloc.disable_ubwc=1` (UBWC off). If it helps, flip that line in
`overlay/system/usr/share/halium-overlay/vendor/build.prop` from `=0` to `=1`; it is `=0` until
then. The SurfaceFlinger-only `debug.sf.hw`, `debug.egl.hw` and `debug.sf.latch_unsignaled` lines
were removed from that file (nothing reads them on Ubuntu Touch). Do not add `QSG_*` or
`QT_ENABLE_GLYPH_CACHE_WORKAROUND` lines to `ubuntu-touch-session.d/android.conf`; those
experiments are over and did not help.

## Device trees from source (kernel d5455f4eb)

`deviceinfo` no longer points at the prebuilt `oneplus-instantnoodle-instantnoodle.dtb` and
`oneplus-instantnoodle-dtbo.img` (both of mixed origin). The build tools now take
`vendor/qcom/kona.dtb`, `kona-v2.dtb` and `kona-v2.1.dtb` from the kernel build as the boot
image's DTB section, and build `dtbo.img` from `instantnoodle-overlay-t0/-evt1/-dvt.dtbo`. The
8 Pro (`instantnoodlep`) and Visible/T-Mobile (`instantnoodlev`) overlays are not included.
Verified on device: the bootloader picked `dtb_idx=2` (kona-v2.1) and `dtbo_idx=2` (DVT overlay),
`/proc/device-tree/model` reads "kona MTP dvt 19821 19855 14 15" (the retail revision) and the
panel is `qcom,mdss_dsi_samsung_ana6705_dsc_cmd`. The prebuilt files are deleted from the repo.

## Under-display fingerprint (goodix) - not working in this release

What works, verified by the kernel agent: biometryd to HAL, HAL to the trusted application, the
DSP algorithm service, the kernel driver and its netlink channel, the stored half of the
calibration (`mCaliDataState=0x2`) and the sensor cache directory.

Two prerequisites were missing and are now in place; without them no display work could ever
have produced a capture:

- **`/data/media/0` in the container.** The HAL writes its sensor cache to
  `/data/media/0/gf_secure_obj_1.so_0` and fails silently if the directory is absent (Android's
  vold creates it, nothing on Ubuntu Touch does). The vendor init override
  `overlay/system/usr/share/halium-overlay/vendor/etc/init/hw/init.qcom.usb.rc` now creates
  `/data/media` and `/data/media/0` (system:system, 0775) on `post-fs-data`. It lives in that file
  because `mount-halium-overlay` can only bind-mount over files that already exist in `/vendor`;
  a new rc file in `vendor/etc/init/` would never be seen.
- **Calibration files on persist keep their stock names.** The files in
  `/mnt/vendor/persist/data` (`gf_persist*.so`, `gf_algo_init*.so`, `gf_preprocess*.so`,
  `autoCalibrationParams.so_0`) must not be renamed. On the test unit they had been renamed with
  a `.off` suffix at some point and were restored by hand; a backup tarball of the directory is on
  the user's PC. Check with `ls /android/mnt/vendor/persist/data` before blaming anything else.

What is blocked: the last calibration step needs the sensor to see a lit screen. Kernel
d3d220bd6 adds the enabler that gives userspace the two signals the Android framework normally
supplies, the finger-down event (`touch_state` node) and the UI-ready signal with HBM
(`force_screenfp` fallback). Both are inactive unless written. The next concrete step is to flash
the CI build carrying d3d220bd6 and run the kernel agent's test script with a white area under
the sensor; if calibration completes, enrolment and unlock work in that test setup.

Making it a real feature is userspace work that belongs upstream with UBports: a small service
doing what the test script does, tied to biometryd sessions, and Lomiri drawing the illumination
spot at the sensor position. Sensor geometry for `halium.yaml` (`udfpLocationX/Y`,
`udfpSensorRadius`): centre 546 x 1909, radius 118, in the 1080 x 2400 frame. A working capture on
this phone is the evidence that gets those accepted. Until then fingerprint is "not working" for
release notes.

## Things still to do, in order

1. Confirm encryption (and fscrypt policy v2) on a fresh install whose userdata was formatted
   with `mke2fs -t ext4 -O encrypt,quota`; `sudo fscrypt status /home/phablet` after the wizard.
2. Confirm the WLAN MAC: `cat /sys/class/net/wlan0/address` should read `5c:17:cf:17:17:86`
   (derived from `vendor.oem.bt.addr` by `instantnoodle-wlan-mac`, written to
   `persist/wlan_mac.bin`). The MAC must survive a reboot.
3. Graphics artifacts: result of the `vendor.gralloc.disable_ubwc=1` test (above).
4. Fingerprint: flash d3d220bd6, run the calibration test (above).
5. Punch hole: `halium.yaml` sets `CollapsedPanelHeight: 104` and `DisplayCutouts*` of 76 px at
   x 61-137 (Android's overlay says 68 px at x 65-133; the ring drawn around the hole was slightly
   small with that, so it was widened). Trade-off, by Lomiri's PanelItemRow design: an indicator
   overlapping a cutout is pushed to the far side of it, and the strip left of the hole cannot fit
   a whole indicator, so the leftmost one (notifications) can sit partly off-screen when the row is
   full. Removing the `DisplayCutouts*` lines (keeping the panel height) brings it back if preferred.
6. Bluetooth audio: pulseaudio cannot load `android.hardware.bluetooth.audio@2.0.so`; revisit
   after pairing works.
7. Cosmetic: `70-oneplus8.rules` still uses `GROUP="bluetooth"` on a few nodes; the group exists
   on the host (bluez) but `wifi` did not and was already changed to root. The bluebinder
   `StartLimit*` keys are in `[Unit]` in the drop-in, as they should be.
8. All `etc/init/*.conf|override` and `usr/share/upstart/sessions/*` files are inert on 24.04
   (no upstart). They are kept for parity with the reference ports; MTP and tethering on 24.04 go
   through usb-moded, which this overlay configures.
9. Consider `deviceinfo_system_partition_size` once you know how much of `super` is free after
   deleting the product/system_ext partitions.

Done and verified, kept here so nobody re-opens them: WireGuard vendored on `Halium-10`
(`CONFIG_WIREGUARD=y` stays, Ubuntu Touch VPN); first boot on the binderfs / in-tree WLAN /
fscrypt v2 kernel confirmed; WiFi and Bluetooth confirmed; device trees from source confirmed.

## Building

Locally:

```bash
./build.sh                                   # images + device tarball in ./out
./build/prepare-fake-ota.sh out/device_instantnoodle.tar.xz ota
./build/system-image-from-ota.sh ota/ubuntu_command out   # out/rootfs.img
```

CI: `.github/workflows/build.yml` (GitHub) and `.forgejo/workflows/build.yml` (Forgejo) run the same
steps on a self-hosted runner inside an `ubuntu:22.04` container, the same package set as the UBports
GitLab CI. Every run builds boot/recovery/dtbo, the device tarball and `ubuntu.img.zst`, publishes a
pre-release `test-<run number>` and, best effort, uploads the small files as an artifact. Pushing a
tag `v*` publishes a full release. A manual run ("Run workflow") can untick *flashable* or
*release*, and can set *kernel_branch* to build e.g. `Halium-10-Test`. The runner only needs the
runner agent and Docker; see `RUNNER.md`.

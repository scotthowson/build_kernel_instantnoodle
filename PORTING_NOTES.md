# OnePlus 8 (instantnoodle) Ubuntu Touch port — review and fix list

Reviewed on 2026-10-14 against:

- this repository (`android-10-testing`)
- the overlay repository `scotthowson/oneplus8_ubuntu_adaptation`, branch `a10-testing` (the branch `build.conf` pointed at)
- the kernel `scotthowson/Ubuntu_ElementalX_OnePlus8`, branch `Halium-10`, defconfig `halium-instantnoodle_ubuntu_defconfig`
- the UBports reference ports for OnePlus Nord N10 (`oneplus-billie`) and Nord N100 (`oneplus-billie2`) and the current `halium-generic-adaptation-build-tools`

## What was wrong, by severity

### Kernel (patch in `kernel/0001-halium-instantnoodle-defconfig-fixes.patch`)

1. **Firmware loading was compiled out.** The defconfig has `CONFIG_EXPERT=y` and `# CONFIG_FW_LOADER is not set`.
   With EXPERT on, Kconfig honours that line, so `request_firmware()` is a stub. QCA6390 WLAN firmware
   (cnss2: amss.bin, m3.bin, bdwlan), Bluetooth firmware and touch firmware updates cannot load.
   This alone explains most "drivers are wonky". Fixed: `CONFIG_FW_LOADER=y`.
2. **The WLAN driver is not in the kernel tree.** `CONFIG_QCA_CLD_WLAN=y` is a dead option: there is no
   `qcacld-3.0` directory anywhere in the tree. WiFi therefore depends on the stock prebuilt
   `/vendor/lib/modules/qca_cld3_wlan.ko`, which only loads if the kernel vermagic matches
   (`4.19.81-perf`). The kernel used `CONFIG_LOCALVERSION="-howsondev"`. Both reference ports keep
   `-perf` for this reason. Fixed in the patch; verify the module's vermagic on the device with
   `strings /vendor/lib/modules/qca_cld3_wlan.ko | grep vermagic` and compare with `uname -r`.
3. **No fscrypt v2 support** (no `fs/crypto/keyring.c`, no `FSCRYPT_POLICY_V2`), but the overlay's
   `fscrypt.conf` asked for policy v2. First-boot encryption cannot succeed that way. Overlay now uses
   v1; the proper fix is to backport fscrypt v2 like the Nord N10 kernel did.
4. `CONFIG_CMDLINE="systemd.unified_cgroup_hierarchy=0"` is ignored (bootloader cmdline wins). Moved to
   `deviceinfo_kernel_cmdline`. Without it, 24.04's systemd uses cgroup v2 only and the Android 10
   container's cgroup v1 controllers are not available.
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
9. `deviceinfo_use_overlaystore="true"` (recommended for 20.04+ and what the `.halium-override-dir`
   markers in the old overlay were trying to use).
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

Kept as-is (deliberately): `halium.yaml` (grid unit 21, torch paths), udev rules, pulse `touch.pa`,
ofono binder config with two slots, `vendor/build.prop`, `device-hacks`, `sound-script`.

## Things still to do, in order

1. Apply the kernel patch to `Ubuntu_ElementalX_OnePlus8` (`Halium-10`) and rebuild. Check `dmesg` for
   `qca_cld3_wlan` load messages. "disagrees about version of symbol" means a CRC mismatch: then the
   fix is to import OnePlus's `qcacld-3.0`, `qca-wifi-host-cmn` and `fw-api` into
   `drivers/staging/` and build it in-tree as a module (the build tools install in-tree modules
   into the rootfs automatically).
2. Backport fscrypt v2 (Nord N10 kernel commit "treewide: Check out fscrypt v2 support from Android
   Common Kernel") and switch `overlay/system/etc/fscrypt.conf` back to `"policy_version": "2"`.
3. Add `DisplayCutouts*` to `halium.yaml` for the punch-hole camera once the panel geometry is
   measured, as the Nord N100 port does.
4. Note that all `etc/init/*.conf|override` and `usr/share/upstart/sessions/*` files are inert on
   24.04 (no upstart). They are kept for parity with the reference ports; MTP and tethering on 24.04
   go through usb-moded, which this overlay configures.
5. Consider `deviceinfo_system_partition_size` once you know how much of `super` is free after
   deleting the product/system_ext partitions.

## Building

Locally:

```bash
./build.sh                                   # images + device tarball in ./out
./build/prepare-fake-ota.sh out/device_instantnoodle.tar.xz ota
./build/system-image-from-ota.sh ota/ubuntu_command out   # out/rootfs.img
```

CI: `.github/workflows/build.yml` runs the same steps on a self-hosted runner inside an
`ubuntu:22.04` container (same package set as the UBports GitLab CI). Push to `android-10-testing`
builds boot/recovery/dtbo and the device tarball. A manual run ("Run workflow") with
*flashable* also produces `ubuntu.img.zst`, and with *release* publishes everything as a GitHub
pre-release named `test-<run number>`. Pushing a tag `v*` builds everything and publishes a
proper release. The runner only needs the GitHub Actions runner agent and Docker.

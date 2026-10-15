# Kernel handoff: OnePlus 8 (instantnoodle), Ubuntu_ElementalX_OnePlus8 branch Halium-10

## Root cause of the current non-boot (black screen)

The system boots fine; the Android container does not start. From the journal of the failed boot:

```
lxc-start: android: safe_mount: No such file or directory - Failed to mount "/dev/binderfs"
    onto "/usr/lib/aarch64-linux-gnu/lxc/rootfs/dev/binderfs"
```

Ubuntu Touch 24.04-2.x (lxc-android-config) bind-mounts `/dev/binderfs` into the container
unconditionally. This kernel cannot provide it: `drivers/android/` has no `binderfs.c`, no
`binder_internal.h` and no `ANDROID_BINDERFS` Kconfig entry. The line `CONFIG_ANDROID_BINDERFS=n`
in the defconfig is a no-op. Without the container there is no hwcomposer, so lightdm/Lomiri hang
(black screen) and every binder client (sensorfwd, bluebinder, ofono, nfcd, biometryd,
lomiri-location-service) times out, several of them unkillable inside binder calls.

The build that previously booted ran an older rootfs that did not mount binderfs, which is why
this only appeared now.

## Task 1 (blocking): backport binderfs

Backport the Android Common Kernel 4.19 binderfs implementation:

- `drivers/android/binderfs.c` (new)
- `drivers/android/binder_internal.h` (new)
- `drivers/android/binder.c`: binderfs hooks (binder device list handling, `binder_devices`
  init from `binder_internal.h`, `is_binderfs_device()`, `binderfs_remove_file` on release)
- `drivers/android/Kconfig`: add
  ```
  config ANDROID_BINDERFS
          bool "Android Binderfs filesystem"
          depends on ANDROID_BINDER_IPC
          default n
  ```
- `drivers/android/Makefile`: `obj-$(CONFIG_ANDROID_BINDERFS) += binderfs.o`
- `include/uapi/linux/android/binderfs.h` (new, `BINDER_CTL_ADD` ioctl, `struct binderfs_device`)
- `include/uapi/linux/magic.h`: `BINDERFS_SUPER_MAGIC 0x6c6f6f70`

Reference trees that already carry the backport on 4.19 (same era, same QCOM base):

- https://gitlab.com/ubports/porting/community-ports/android11/xiaomi-mi-10t-lite/kernel-xiaomi-sm7225.git
  branch `halium-11.0` — files `drivers/android/binderfs.c`, `drivers/android/binder_internal.h`,
  plus the matching `binder.c`, `Kconfig`, `Makefile`. Diff that `drivers/android/` against ours.
- Android Common Kernel `android-4.19-stable` (`drivers/android/binderfs.c` upstream from 5.0,
  backported by Google). `git log --oneline -- drivers/android/binderfs.c` there gives the series.

Note this tree has local binder.c modifications ("(halium) binder: ignore txn_security_ctx flag",
"Use gbinder workaround only for hwbinder context", and a 140-line "test" commit 4366c9f). Keep
them; rebase the binderfs hunks around them.

Then in `arch/arm64/configs/halium-instantnoodle_ubuntu_defconfig`:

```
CONFIG_ANDROID_BINDERFS=y
```

Keep `CONFIG_ANDROID_BINDER_DEVICES="binder,hwbinder,vndbinder,..."` as it is: the static devices
stay for the host side, binderfs provides the container's.

Acceptance: after flashing, `ls /dev/binderfs` on the device lists `binder-control`, the journal has
no `Failed to mount "/dev/binderfs"`, `lxc-info -n android` reports RUNNING, and the UI appears.

## Task 2: stop fetching WireGuard from the network at build time

`net/Kconfig` sources `net/wireguard/Kconfig`, and `scripts/fetch-latest-wireguard.sh` downloads
wireguard-linux-compat from git.zx2c4.com on every fresh checkout. That host fails often; CI
currently works around it by seeding `net/wireguard` from a cache. Proper fix: commit
wireguard-linux-compat 1.0.20220627 `src/` as `net/wireguard/` (with the `tristate`→`bool`,
`default m`→`default y` sed the script applies to its Kconfig) and make the fetch script exit 0.
Keep `CONFIG_WIREGUARD=y`; Ubuntu Touch uses it for VPN.

## Task 3: fscrypt v2

`fs/crypto/` has no `keyring.c` / `FSCRYPT_POLICY_V2` / `FS_IOC_ADD_ENCRYPTION_KEY`. Ubuntu Touch
24.04 prefers policy v2; the overlay is pinned to v1 until this lands. Reference: Nord N10 kernel
commit "treewide: Check out fscrypt v2 support from Android Common Kernel"
(https://gitlab.com/ubports/porting/community-ports/android10/oneplus-nord-n10/kernel-oneplus-sm6350.git,
branch halium-10.0). After it lands, switch `overlay/system/etc/fscrypt.conf` to `"policy_version": "2"`.

## Task 4: WLAN driver in-tree (only if WiFi stays broken after Task 1)

No qcacld-3.0 in the tree. WiFi relies on the stock `/vendor/lib/modules/qca_cld3_wlan.ko`, which
needs vermagic `4.19.81-perf` (now set via `CONFIG_LOCALVERSION="-perf"`) and matching symbol CRCs
(`CONFIG_MODVERSIONS=y`). If `dmesg` shows "disagrees about version of symbol" for qca_cld3_wlan,
import OnePlus's OOS 10 `qcacld-3.0`, `qca-wifi-host-cmn` and `fw-api` into `drivers/staging/`
and build `CONFIG_QCA_CLD_WLAN=m`; the build tools install in-tree modules into the rootfs.

## Already done on Halium-10 (commit d49b74f), keep

- `CONFIG_FW_LOADER=y` (was compiled out: no WLAN/BT/touch firmware could load)
- `CONFIG_LOCALVERSION="-perf"` (vendor module vermagic)
- `CONFIG_SECURITY_APPARMOR_BOOTPARAM_VALUE=1`
- `CONFIG_AUTOFS4_FS=y`
- dead `CONFIG_QCA_CLD_WLAN=y` line removed

# Kernel: Ubuntu_ElementalX_OnePlus8, branch Halium-10

The kernel is built from `deviceinfo_kernel_source` / `deviceinfo_kernel_source_branch`
(`scotthowson/Ubuntu_ElementalX_OnePlus8`, `Halium-10`) with the defconfig
`arch/arm64/configs/halium-instantnoodle_ubuntu_defconfig`. Everything the port needs is
committed on that branch; nothing is patched at build time any more (the old
`0001-halium-instantnoodle-defconfig-fixes.patch` is applied upstream and was removed here).

## What the Halium-10 branch carries on top of the ElementalX / Oxygen OS 10 (4.19.81) tree

| Area | Commit(s) | Why |
|---|---|---|
| Defconfig in `savedefconfig` form | `arm64: defconfig: regenerate ...` | The old file was a 6200-line `.config` dump with duplicated and contradictory lines and symbols that do not exist in 4.19. Regenerated as the UBports porting guide describes. Adds EXT4_FS_SECURITY (file capabilities on the ext4 rootfs), SECURITY_YAMA, SELinux boot parameter support (`selinux=0` on the cmdline is honoured), ENCRYPTED_KEYS/EVM, the netfilter matches Ubuntu's iptables expects, DEFAULT_MMAP_MIN_ADDR=32768; drops the unused BT_HCIUART and the no-op CONFIG_CMDLINE. Kept as stock OnePlus: RT_GROUP_SCHED, SCHED_TUNE, FW_LOADER_USER_HELPER(_FALLBACK), USB_CONFIGFS_F_GSI. |
| WireGuard vendored | `net: wireguard: vendor wireguard-linux-compat 1.0.20220627` | `scripts/fetch-latest-wireguard.sh` downloaded the sources from git.zx2c4.com on every fresh checkout. The sources are now in `net/wireguard` and the script is a no-op; CI no longer seeds anything. `CONFIG_WIREGUARD=y` stays (Ubuntu Touch VPN). |
| binderfs | `binder: backport binderfs and enable CONFIG_ANDROID_BINDERFS` | Ubuntu Touch 24.04-2.x bind-mounts `/dev/binderfs` into the Android container and Waydroid prefers binderfs. Backported from the Android Common Kernel 4.19 (via the UBports kernel-xiaomi-sm7225 tree). Unlike upstream, the static `/dev/binder`, `/dev/hwbinder`, ... misc devices are still registered: the Halium 10 (Android 10) container's init and ueventd know nothing about binderfs. See `overlay/system/usr/lib/systemd/system/android-binderfs.service` for the host-side mount. |
| WLAN driver in-tree | `cnss2, mhi: add the platform interfaces ...`, `staging: import qcacld-3.0 WLAN driver ...` | WiFi no longer depends on the stock `/vendor/lib/modules/qca_cld3_wlan.ko` and its vermagic/CRC match. qcacld-3.0, qca-wifi-host-cmn and fw-api come from LineageOS 18.1's OnePlus 8 kernel (OnePlus does not ship them with its kernel source); the driver is built in (`CONFIG_QCA_CLD_WLAN=y`) as LineageOS does. The few cnss2/MHI interfaces that newer driver expects were added to the platform code. |
| fscrypt v2 | `treewide: Check out fscrypt v2 support from Android Common Kernel` (cherry-picked from the Nord N10 Halium kernel) | `FSCRYPT_POLICY_V2`, `FS_IOC_ADD_ENCRYPTION_KEY`, fs-verity and the casefolding (unicode) infrastructure. `overlay/system/etc/fscrypt.conf` is still pinned to policy v1; switch it to `"policy_version": "2"` once a build with this kernel has been confirmed to encrypt on first boot. |

Earlier (commit `d49b74f`): `CONFIG_LOCALVERSION="-perf"`, `CONFIG_AUTOFS4_FS=y`,
`CONFIG_SECURITY_APPARMOR_BOOTPARAM_VALUE=1`, dead `CONFIG_QCA_CLD_WLAN=y` line removed.

## Corrections to earlier notes

- `CONFIG_FW_LOADER` was never compiled out. Expanding the old defconfig with kconfig gives
  `CONFIG_FW_LOADER=y` (it is selected by many drivers; the `# CONFIG_FW_LOADER is not set`
  line was simply overridden), so firmware loading always worked. The `-perf` LOCALVERSION,
  AUTOFS4 and the AppArmor boot default were the effective changes of that patch.
- `CONFIG_CMDLINE="systemd.unified_cgroup_hierarchy=0"` was a no-op (the bootloader cmdline
  wins); it is removed from the defconfig. The booting build runs cgroup v2.

## Verifying on the device

```bash
ls /dev/binderfs                      # binder-control plus the binder devices
journalctl -b | grep -i binderfs      # no "Failed to mount" from lxc-start
lxc-info -n android                   # RUNNING
dmesg | grep -i -E "cnss|wlan"        # in-tree driver probing, no vermagic/CRC complaints
uname -r                              # 4.19.81-perf...
```

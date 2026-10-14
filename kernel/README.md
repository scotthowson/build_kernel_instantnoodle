# Kernel changes (apply in Ubuntu_ElementalX_OnePlus8, branch Halium-10)

The kernel is built from `deviceinfo_kernel_source`; this repository cannot change it
directly, so the required defconfig changes are shipped here as a patch:

```bash
cd /path/to/Ubuntu_ElementalX_OnePlus8   # branch Halium-10
git apply /path/to/build_kernel_instantnoodle/kernel/0001-halium-instantnoodle-defconfig-fixes.patch
```

What the patch does and why:

| Option | Before | After | Reason |
|---|---|---|---|
| `CONFIG_FW_LOADER` | not set | `y` | With `CONFIG_EXPERT=y` the "not set" line is honoured, so `request_firmware()` was compiled out. cnss2 (QCA6390 WLAN firmware), Bluetooth, touch firmware updates and the display stack all need it. The `FW_LOADER_USER_HELPER*` lines below it were silently dropped by Kconfig because their dependency was off. |
| `CONFIG_LOCALVERSION` | `-howsondev` | `-perf` | The WLAN driver (`qca_cld3_wlan.ko`) is not in this kernel tree; it is the prebuilt module in `/vendor/lib/modules`, loaded by stock `init.target.rc`. Modules only load when the kernel's vermagic matches theirs. The stock kernel is `4.19.81-perf`, and the Nord N10/N100 reference ports keep `-perf` for exactly this reason. Verify on the device: `strings /vendor/lib/modules/qca_cld3_wlan.ko \| grep vermagic`. |
| `CONFIG_SECURITY_APPARMOR_BOOTPARAM_VALUE` | `0` | `1` | AppArmor enabled by default instead of relying solely on `apparmor=1` in the cmdline. |
| `CONFIG_AUTOFS4_FS` | not set | `y` | systemd's `proc-sys-fs-binfmt_misc.automount` and other automount units need autofs. |
| `CONFIG_QCA_CLD_WLAN=y` | set | removed | Dead option: there is no qcacld-3.0 source in the tree, so it has no effect and is misleading. |

Not changed, but worth knowing:

- `CONFIG_CMDLINE="systemd.unified_cgroup_hierarchy=0"` has no effect on this kernel: the
  bootloader-provided cmdline replaces it (there is no `CMDLINE_EXTEND`). The parameter has
  been moved to `deviceinfo_kernel_cmdline` in this repository.
- There is no fscrypt v2 support (`fs/crypto/keyring.c` and `FSCRYPT_POLICY_V2` are absent).
  The Nord N10 Halium kernel backported it from the Android Common Kernel ("treewide: Check
  out fscrypt v2 support from Android Common Kernel"). Until that is done here, the overlay
  uses fscrypt policy v1.
- `CONFIG_MODVERSIONS=y` plus `CONFIG_MODULE_SIG=y` (not FORCE) match the stock config, which
  is what lets the vendor WLAN module load once the vermagic matches. Changing options that
  alter exported struct layouts can still break the symbol CRC check; if `dmesg` shows
  "disagrees about version of symbol", the long-term fix is to add the OnePlus
  qcacld-3.0 / qca-wifi-host-cmn / fw-api sources to the tree and build the module there.

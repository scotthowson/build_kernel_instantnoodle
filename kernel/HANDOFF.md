# Kernel handoff status: OnePlus 8 (instantnoodle), Ubuntu_ElementalX_OnePlus8 branch Halium-10

Status of the tasks from the 2026-10-15 handoff. Details of each change are in `kernel/README.md`
and in the commit messages on the kernel branch.

| Task | Status | Commit on Halium-10 |
|---|---|---|
| 1. binderfs backport (blocking, 24.04-2.x rootfs) | done, compile-checked | `binder: backport binderfs and enable CONFIG_ANDROID_BINDERFS` |
| 2. stop fetching WireGuard at build time | done | `net: wireguard: vendor wireguard-linux-compat 1.0.20220627` |
| 3. fscrypt v2 | done, compile-checked; overlay still on policy v1 until tested on the device | `treewide: Check out fscrypt v2 support from Android Common Kernel` |
| 4. WLAN driver in-tree | done, compile-checked; built in (`CONFIG_QCA_CLD_WLAN=y`) | `cnss2, mhi: add the platform interfaces ...`, `staging: import qcacld-3.0 ...` |

Design decision on task 1: the static binder misc devices stay registered next to binderfs.
Android 10 (the Halium 10 container) has no binderfs support in init/ueventd, and
lxc-android-config only mounts binderfs itself when `/dev/binder` is missing. The overlay's
`android-binderfs.service` mounts `/dev/binderfs` on the host so the container's bind mount
works whether or not the rootfs marks it `optional`.

Acceptance on the device: `ls /dev/binderfs` lists `binder-control`, the journal has no
`Failed to mount "/dev/binderfs"`, `lxc-info -n android` reports RUNNING, the UI appears,
`dmesg` shows the in-tree WLAN driver probing.

Note: the `safe_mount: ... Failed to mount "/dev/binderfs"` line is logged by LXC even when the
mount entry is `optional`, so on its own it does not prove the container aborted there. If the
container still fails to start with this kernel, check `lxc-start -n android -F` output.

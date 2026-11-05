# Containerization kernel configuration

This directory holds a kernel configuration for container use.

The current tree is Linux 7.3-rc3. It sets `CONFIG_BTRFS_FS=y` and `CONFIG_BTRFS_EXPERIMENTAL=y`. That set includes async data checksums, huge data folios, raid-stripe-tree, and extent tree v2.

- `config-arm64` and `config-x86_64` hold the per-arch `CONFIG_` options. See `LICENSE.kernel-configs`.
- `Makefile` sets the kernel version (`KVERSION`) and the source package URL.
- `build.sh` builds the kernel and enables the btrfs options after `olddefconfig`.
- `image/` holds the Ubuntu 26.04 image used for the build.

## Build

1. Install the `container` tool. See https://github.com/apple/container/releases.
2. Run `make`. This builds the image, then runs a container to build the kernel.

### Target architecture

Set `TARGET_ARCH` to `arm64` or `x86_64`. When unset, `make` uses the host architecture. It maps `aarch64` to `arm64` and `amd64` to `x86_64`.

- `make` builds for the host architecture.
- `make TARGET_ARCH=arm64` writes `vmlinux-arm64` (uncompressed `Image`).
- `make TARGET_ARCH=x86_64` writes `vmlinuz-x86_64` (compressed `bzImage`).
- `make x86_64` is the short form of `make TARGET_ARCH=x86_64`.

The `z` in the x86 name follows the Linux name for a compressed kernel image. The build writes the kernel to `kernel/out/`.

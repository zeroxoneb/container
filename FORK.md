# Fork notes

This repository is a fork of [apple/container](https://github.com/apple/container). It is not an Apple release.

The Swift code and the kernel build scripts use Apache-2.0. The files `config-arm64` and `config-x86_64` use GPL-2.0-only. Read `kernel/LICENSE.kernel-configs`.

## Build the CLI

See `BUILDING.md`. On macOS 26 with Apple silicon, run `make` in this repository.

## Build the kernel

The kernel configs and build scripts are in `kernel/`. They do not include a built kernel.

```bash
make -C kernel
```

The build writes the kernel to `kernel/out/`. Pass that file to `machine create --kernel`, or set it as the default with `container system kernel set`.

## Attach a disk to a machine

Create a raw disk image and put a filesystem on it:

```bash
dd if=/dev/zero of=disk.raw bs=1m count=1024
container run --rm -v "$PWD/disk.raw:/disk.raw" alpine:latest \
  sh -c 'apk add --no-cache e2fsprogs >/dev/null && mkfs.ext4 -q /disk.raw'
```

Attach it at create time:

```bash
container machine create \
  --kernel kernel/out/vmlinux-arm64 \
  --disk source=$PWD/disk.raw,dest=/mnt/data,format=ext4 \
  --name data \
  alpine:latest
```

The spec form is `source=PATH,dest=PATH,format=FS`. Add `,ro` for a read-only mount. Add mount options such as `subvolid=5` after the format field. The image must already hold the filesystem. This tool does not format the disk.

Change the disk list on a machine with `machine set --disk`. Clear it with `machine set --disk-clear`. Stop and start the machine before the new list takes effect.

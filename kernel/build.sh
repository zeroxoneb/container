#!/bin/bash
# Copyright © 2025-2026 Apple Inc. and the Containerization project authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific information governing permissions and
# limitations under the License.

set -euo pipefail

TARGET_ARCH="${TARGET_ARCH:-$(uname -m)}"

case "${TARGET_ARCH}" in
  aarch64|arm64)
    CONFIG=config-arm64
    KARCH=arm64
    CROSS_COMPILE=aarch64-linux-gnu-
    IMAGE_PATH=arch/arm64/boot/Image
    OUTPUT_NAME=vmlinux-arm64
    ;;
  x86_64|amd64)
    CONFIG=config-x86_64
    KARCH=x86_64
    CROSS_COMPILE=x86_64-linux-gnu-
    IMAGE_PATH=arch/x86/boot/bzImage
    OUTPUT_NAME=vmlinuz-x86_64
    ;;
  *)
    echo "Unsupported target architecture: ${TARGET_ARCH}" >&2
    exit 1
    ;;
esac

SOURCE_TAR=""
for candidate in /kernel/source.tar.gz /kernel/source.tar.xz /kernel/source.tar; do
  if [ -f "${candidate}" ]; then
    SOURCE_TAR="${candidate}"
    break
  fi
done
if [ -z "${SOURCE_TAR}" ]; then
  echo "missing kernel source tarball under /kernel/source.tar*" >&2
  exit 1
fi

mkdir -p /kbuild
tar -xf "${SOURCE_TAR}" -C /kbuild --strip-components=1
cp "/kernel/${CONFIG}" /kbuild/.config

JOBS=$(($(nproc) - 1))
if [ "${JOBS}" -lt 1 ]; then
  JOBS=1
fi

(
  cd /kbuild
  make ARCH="${KARCH}" CROSS_COMPILE="${CROSS_COMPILE}" olddefconfig

  # Keep btrfs built-in and turn on the 7.3 experimental feature set
  # (async data checksums, huge data folios, raid-stripe-tree, extent tree v2, ...).
  ./scripts/config --file .config \
    --enable BTRFS_FS \
    --enable BTRFS_FS_POSIX_ACL \
    --enable BTRFS_EXPERIMENTAL \
    --enable IKCONFIG \
    --enable IKCONFIG_PROC \
    --enable VIRTIO_BLK \
    --enable VIRTIO_FS \
    --enable VIRTIO_VSOCKETS \
    --enable EXT4_FS \
    --enable BLK_DEV_LOOP \
    --enable TUN \
    --enable DUMMY \
    --enable VETH \
    --enable BRIDGE \
    --enable MACVLAN
  make ARCH="${KARCH}" CROSS_COMPILE="${CROSS_COMPILE}" olddefconfig

  make ARCH="${KARCH}" CROSS_COMPILE="${CROSS_COMPILE}" -j"${JOBS}" LOCALVERSION="${LOCALVERSION:-}"
  mkdir -p /kernel/out
  cp "${IMAGE_PATH}" "/kernel/out/${OUTPUT_NAME}"
  cp .config "/kernel/out/${CONFIG}.built"

  echo "Built $(make -s kernelrelease ARCH="${KARCH}" CROSS_COMPILE="${CROSS_COMPILE}" LOCALVERSION="${LOCALVERSION:-}") -> /kernel/out/${OUTPUT_NAME}"
)

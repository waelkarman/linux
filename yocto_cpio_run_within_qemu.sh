#!/bin/bash
set -e

JOBS=$(nproc)
YOCTO_CPIO="../build/tmp/deploy/images/bunch-linux-machine/bunch-linux-demo-bunch-linux-machine.rootfs.cpio.gz"

# ============================================================
# CLEANUP
# ============================================================
echo "--- Cleanup kernel ---"
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- mrproper

# ============================================================
# COMPILAZIONE KERNEL
# ============================================================
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig

./scripts/config --enable DEVTMPFS \
                 --enable DEVTMPFS_MOUNT \
                 --enable BLK_DEV_INITRD \
                 --enable SERIAL_AMBA_PL011 \
                 --enable SERIAL_AMBA_PL011_CONSOLE \
                 --enable PASSIVE_BUZZER \
                 --enable ACTIVE_BUZZER

make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j${JOBS} Image modules

if [ ! -f arch/arm64/boot/Image ]; then
    echo "Build kernel fallita"
    exit 1
fi

echo "--- Kernel compilato ---"
file arch/arm64/boot/Image

# ============================================================
# AVVIO QEMU
# ============================================================
echo "--- Avvio QEMU con rootfs Yocto ---"

qemu-system-aarch64 \
  -M virt \
  -cpu cortex-a72 \
  -m 4G \
  -kernel arch/arm64/boot/Image \
  -initrd ${YOCTO_CPIO} \
  -append "console=ttyAMA0 root=/dev/ram0 rw" \
  -nographic
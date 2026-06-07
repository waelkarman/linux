#!/bin/bash
set -e

JOBS=$(nproc)
YOCTO_DIR="../build/tmp/deploy/images/bunch-linux-machine"
YOCTO_CPIO="${YOCTO_DIR}/bunch-linux-demo-bunch-linux-machine.rootfs.cpio.gz"
YOCTO_CONFIG="${YOCTO_DIR}/kernel.config"

# ============================================================
# SANITY CHECK
# ============================================================
echo "--- Verifica artefatti Yocto ---"

if [ ! -f "${YOCTO_CPIO}" ]; then
    echo "ERRORE: cpio non trovato: ${YOCTO_CPIO}"
    exit 1
fi

if [ ! -f "${YOCTO_CONFIG}" ]; then
    echo "ERRORE: kernel.config non trovato: ${YOCTO_CONFIG}"
    exit 1
fi

echo "cpio   : $(ls -lh ${YOCTO_CPIO})"
echo "config : $(ls -lh ${YOCTO_CONFIG})"

# ============================================================
# CLEANUP
# ============================================================
echo "--- Cleanup kernel ---"
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- mrproper

# ============================================================
# CONFIG DA YOCTO
# ============================================================
echo "--- Copia .config da Yocto ---"
cp "${YOCTO_CONFIG}" .config

./scripts/config --enable DEVTMPFS \
                 --enable DEVTMPFS_MOUNT \
                 --enable BLK_DEV_INITRD \
                 --enable SERIAL_AMBA_PL011 \
                 --enable SERIAL_AMBA_PL011_CONSOLE

make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig

# Verifica buzzer dopo olddefconfig
echo "--- Verifica config buzzer ---"
grep -E "PASSIVE_BUZZER|ACTIVE_BUZZER|ARM64_PLATFORM" .config || echo "buzzer non trovato nel .config"

# ============================================================
# COMPILAZIONE KERNEL
# ============================================================
echo "--- Compilazione kernel ---"
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
  -initrd "${YOCTO_CPIO}" \
  -append "console=ttyAMA0 rw" \
  -nographic
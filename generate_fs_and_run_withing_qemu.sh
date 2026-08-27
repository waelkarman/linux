#!/bin/bash
set -e

# ============================================================
# OPZIONI
# ============================================================
CLEAN=0
for arg in "$@"; do
    case "$arg" in
        --clean|-c) CLEAN=1 ;;
        --help|-h)
            echo "Uso: $0 [--clean]"
            echo "  --clean   mrproper + build completa da zero (ccache resta attivo)"
            exit 0
            ;;
        *) echo "Opzione sconosciuta: $arg"; exit 1 ;;
    esac
done

JOBS=$(nproc)
CROSS=aarch64-linux-gnu-
YOCTO_DIR="../build/tmp/deploy/images/bunch-linux-machine"
YOCTO_CPIO="${YOCTO_DIR}/bunch-linux-demo-bunch-linux-machine.rootfs.cpio.gz"
YOCTO_CONFIG="${YOCTO_DIR}/kernel.config"

# ============================================================
# CCACHE
# ============================================================
export CCACHE_DIR="${CCACHE_DIR:-$HOME/.ccache}"
export CCACHE_MAXSIZE="${CCACHE_MAXSIZE:-25G}"
export CCACHE_SLOPPINESS=time_macros,file_macro,locale,include_file_mtime,include_file_ctime
export CCACHE_NOHASHDIR=1

# Timestamp/host/user fissi: evitano che compile.h cambi a ogni build
export KBUILD_BUILD_TIMESTAMP='2026-01-01'
export KBUILD_BUILD_USER=build
export KBUILD_BUILD_HOST=build

if ! command -v ccache >/dev/null 2>&1; then
    echo "ERRORE: ccache non installato (apt install ccache)"
    exit 1
fi

# NOTA: ccache non va messo in CROSS_COMPILE, altrimenti finisce anche
# davanti a ld/ar/objcopy. Si sovrascrivono solo CC e HOSTCC.
CC_CCACHE="ccache ${CROSS}gcc"
HOSTCC_CCACHE="ccache gcc"

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
# CLEANUP (solo con --clean)
# ============================================================
if [ "${CLEAN}" -eq 1 ]; then
    echo "--- Cleanup kernel (mrproper) ---"
    make ARCH=arm64 CROSS_COMPILE=${CROSS} mrproper
else
    echo "--- Build incrementale (usa --clean per partire da zero) ---"
fi

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

make ARCH=arm64 CROSS_COMPILE=${CROSS} olddefconfig

# Verifica buzzer dopo olddefconfig
echo "--- Verifica config buzzer ---"
grep -E "PASSIVE_BUZZER|ACTIVE_BUZZER|ARM64_PLATFORM" .config || echo "buzzer non trovato nel .config"

# ============================================================
# COMPILAZIONE KERNEL
# ============================================================
echo "--- Compilazione kernel (ccache, -j${JOBS}) ---"
ccache -z >/dev/null

START=$(date +%s)
make ARCH=arm64 CROSS_COMPILE=${CROSS} \
     CC="${CC_CCACHE}" \
     HOSTCC="${HOSTCC_CCACHE}" \
     -j${JOBS} Image modules
END=$(date +%s)

echo "--- Statistiche ccache ---"
ccache -s

if [ ! -f arch/arm64/boot/Image ]; then
    echo "Build kernel fallita"
    exit 1
fi

echo "--- Kernel compilato in $((END - START))s ---"
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
  -append "console=ttyAMA0 dwc_otg.lpm_enable=0 net.ifnames=0 audit=0 console=ttyS1,115200 console=tty1 loglevel=8 drm.debug=0 rw" \
  -nographic
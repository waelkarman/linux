# Numero di job paralleli
JOBS=$(nproc)

# ============================================================
# CLEANUP COMPLETO
# ============================================================

echo "--- Cleanup kernel (mrproper) ---"
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- mrproper

echo "--- Cleanup initramfs ---"
# Preserva SOLO il tarball busybox (evita di riscaricarlo)
rm -rf initramfs initramfs.cpio.gz busybox-1.36.1

# ============================================================
# COMPILAZIONE KERNEL ARM64
# ============================================================

# Config: per QEMU virt va bene defconfig generico arm64.
# Per RPi 4 reale useresti bcm2711_defconfig invece.
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig

# Assicura le opzioni necessarie per l'initramfs e la console QEMU
./scripts/config --enable DEVTMPFS \
                 --enable DEVTMPFS_MOUNT \
                 --enable BLK_DEV_INITRD \
                 --enable SERIAL_AMBA_PL011 \
                 --enable SERIAL_AMBA_PL011_CONSOLE

make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig

# Poi compila insieme
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j${JOBS} Image modules

# Installa nell'initramfs
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
     INSTALL_MOD_PATH=$(pwd)/initramfs \
     modules_install

# Blocca se la build fallisce
if [ ! -f arch/arm64/boot/Image ]; then
    echo "--- ERRORI BUILD KERNEL ---"
    grep -E "^.*error:" /tmp/kernel_build.log | head -20
    echo "Build kernel fallita — uscita"
    exit 1
fi

echo "--- Kernel compilato ---"
file arch/arm64/boot/Image

# ============================================================
# INITRAMFS + BUSYBOX
# ============================================================

# Ricrea struttura initramfs
mkdir -p initramfs/{bin,dev,proc,sys}

# Scarica busybox SOLO se il tarball non esiste già
if [ ! -f busybox-1.36.1.tar.bz2 ]; then
    echo "--- Scarico busybox ---"
    wget https://busybox.net/downloads/busybox-1.36.1.tar.bz2
else
    echo "--- Tarball già presente, riuso ---"
fi

# Verifica integrità tarball prima di estrarre (se corrotto, riscarica)
if ! tar tf busybox-1.36.1.tar.bz2 >/dev/null 2>&1; then
    echo "--- Tarball corrotto, riscarico ---"
    rm -f busybox-1.36.1.tar.bz2
    wget https://busybox.net/downloads/busybox-1.36.1.tar.bz2
fi

tar xf busybox-1.36.1.tar.bz2
cd busybox-1.36.1

# Configura per ARM64 statico
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig

# Forza linking statico
sed -i 's/# CONFIG_STATIC is not set/CONFIG_STATIC=y/' .config

# Disabilita tc (incompatibile con kernel headers recenti)
sed -i 's/CONFIG_TC=y/# CONFIG_TC is not set/' .config

# Abilita setsid (per controlling terminal pulito)
sed -i 's/# CONFIG_SETSID is not set/CONFIG_SETSID=y/' .config

# Compila e blocca su errori reali (non warning)
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j${JOBS} 2>&1 | tee /tmp/busybox_build.log

if [ ! -f busybox ]; then
    echo "--- ERRORI BUILD BUSYBOX ---"
    grep -E "^.*error:" /tmp/busybox_build.log | head -20
    echo "Build fallita — uscita"
    cd ..
    exit 1
fi

# Verifica architettura
file busybox

# Copia nell'initramfs
cp busybox ../initramfs/bin/busybox

# Torna alla root
cd ..

# Verifica architettura
file initramfs/bin/busybox

# Symlink e permessi
chmod +x initramfs/bin/busybox
ln -sf busybox initramfs/bin/sh

# Crea /init
cat > initramfs/init << 'EOF'
#!/bin/sh
/bin/busybox mount -t devtmpfs none /dev
/bin/busybox mount -t proc none /proc
/bin/busybox mount -t sysfs none /sys
/bin/busybox --install -s /bin
echo "Boot OK"
exec setsid -c /bin/sh </dev/console >/dev/console 2>&1
EOF
chmod +x initramfs/init

# Impacchetta
cd initramfs
find . | cpio -o -H newc | gzip > ../initramfs.cpio.gz
cd ..

# Verifica finale
echo "--- Architettura busybox ---"
file initramfs/bin/busybox
echo "--- Contenuto cpio ---"
zcat initramfs.cpio.gz | cpio -t

# ============================================================
# AVVIO QEMU
# ============================================================
# With initrd:
#  -initrd initramfs.cpio.gz \
#  -append "console=ttyAMA0" \
# With yocto disk:

qemu-system-aarch64 \
  -M virt \
  -cpu cortex-a72 \
  -m 4G \
  -kernel arch/arm64/boot/Image \
  -initrd ${YOCTO_CPIO} \
  -append "console=ttyAMA0 root=/dev/ram0 rw" \
  -nographic
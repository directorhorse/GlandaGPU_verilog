#!/usr/bin/env bash
# Build a single-hart S-mode Spike kernel. Supply the uncompressed newc archive
# separately via the device tree's /chosen/linux,initrd-{start,end} properties.
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd -P)
out=$here/../build/linux
obj=$out/kernel
src=${KERNEL_SRC:-$HOME/src/glanda-drm/kernel-work/linux-6.1.160}
cross=${CROSS_COMPILE:-riscv64-linux-gnu-}
mkdir -p "$obj"
obj=$(realpath "$obj")
# Do not clean or configure the input tree. Kbuild rejects dirty sources with O=.
if [[ ! -f $src/Makefile || -e $src/.config || -d $src/include/config || -d $src/arch/riscv/include/generated ]]; then
    tarball=${KERNEL_TARBALL:-$HOME/src/glanda-drm/kernel-work/linux-6.1.160.tar.xz}
    src=$obj/clean-src
    if [[ ! -f $src/.unpacked ]]; then
        mkdir -p "$src"
        tar -xf "$tarball" --strip-components=1 -C "$src"
        touch "$src/.unpacked"
    fi
fi
export KBUILD_BUILD_TIMESTAMP='1970-01-01 00:00:00 UTC' KBUILD_BUILD_USER=spike KBUILD_BUILD_HOST=linux KBUILD_BUILD_VERSION=1
kmake=(make --no-print-directory -C "$src" O="$obj" ARCH=riscv CROSS_COMPILE="$cross")
required=(ARCH_RV64I 64BIT MMU RISCV_SBI RISCV_SBI_V01 SOC_VIRT RISCV_INTC RISCV_TIMER SIFIVE_PLIC PRINTK TTY SERIAL_8250 SERIAL_8250_CONSOLE SERIAL_OF_PLATFORM SERIAL_EARLYCON_RISCV_SBI HVC_RISCV_SBI OF OF_EARLY_FLATTREE BLK_DEV_INITRD BINFMT_ELF BINFMT_SCRIPT DEVTMPFS DEVTMPFS_MOUNT PROC_FS SYSFS SHMEM TMPFS FPU)
# allnoconfig avoids storage/network drivers. EXPERT makes optional interfaces
# explicit.
fragment=$obj/spike-min.config
{
    for symbol in EXPERT EMBEDDED MULTIUSER BASE_FULL FUTEX POSIX_TIMERS SYSCTL ADVISE_SYSCALLS ELF_CORE RISCV_ISA_C "${required[@]}"; do printf 'CONFIG_%s=y\n' "$symbol"; done
    printf 'CONFIG_INITRAMFS_SOURCE=""\nCONFIG_SERIAL_8250_NR_UARTS=1\nCONFIG_SERIAL_8250_RUNTIME_UARTS=1\n'
} >"$fragment"
KCONFIG_ALLCONFIG="$fragment" "${kmake[@]}" allnoconfig
for symbol in "${required[@]}"; do
    grep -qx "CONFIG_$symbol=y" "$obj/.config" || { echo "Missing required CONFIG_$symbol" >&2; exit 1; }
done
"${kmake[@]}" -j"${JOBS:-$(nproc)}" Image
install -m 0644 "$obj/arch/riscv/boot/Image" "$out/Image"
sha256sum "$out/Image"

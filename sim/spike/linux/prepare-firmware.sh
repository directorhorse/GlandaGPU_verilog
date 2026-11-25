#!/usr/bin/env bash
# Build an unstripped RV64 OpenSBI: Spike needs tohost/fromhost ELF symbols
# for the HTIF shutdown handshake. Ubuntu noble's binary package strips them.
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")/.." && pwd)
out="$here/build/linux"
work="$out/firmware"
mkdir -p "$work"
cd "$work"
tarball=opensbi_1.7.orig.tar.gz
sha256=2cf856a4e5e2e052948ddb54ba48232b1f698b7f52e0374fc7d17d51e8c8f7ce
if [[ ! -f $tarball ]]; then
    curl -fL --retry 3 "https://archive.ubuntu.com/ubuntu/pool/main/o/opensbi/$tarball" -o "$tarball.part"
    mv -- "$tarball.part" "$tarball"
fi
printf '%s  %s\n' "$sha256" "$tarball" | sha256sum -c -
tar -xzf "$tarball"
# Spike maps a zero-linked PIE at DRAM_BASE. Copy Spike's live ROM DTB
# into writable RAM at 0x88000000; use at least 256 MiB in the simulator.
make -C opensbi-1.7 -j"${JOBS:-8}" O="$work/obj" \
    CROSS_COMPILE="${CROSS_COMPILE:-riscv64-linux-gnu-}" PLATFORM=generic \
    PLATFORM_RISCV_XLEN=64 FW_TEXT_START=0 FW_JUMP=y FW_JUMP_OFFSET=0x200000 \
    FW_JUMP_FDT_OFFSET=0x8000000 FW_PAYLOAD= FW_DYNAMIC=
elf="$work/obj/platform/generic/firmware/fw_jump.elf"
for symbol in fromhost tohost; do
    readelf -sW "$elf" | awk -v name="$symbol" '$8 == name {found=1} END {exit !found}'
done
install -m 755 "$elf" "$out/fw_jump.elf"
printf 'Firmware ready: %s/fw_jump.elf\n' "$out"

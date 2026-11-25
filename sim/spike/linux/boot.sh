#!/usr/bin/env bash
# Boot already-built RV64 Linux artifacts. No Python or Pillow at run time.
set -euo pipefail
usage() {
    printf '%s\n' 'Usage: boot.sh [--drm] [--shell]' \
        '  --drm    Load the KMS module; in automatic mode verify every VGA pixel.' \
        '  --shell  Attach the terminal to the guest instead of running the automatic check.' \
        '  Env: SPIKE, DTC, GLANDA_BUILD (sim/spike/build by default), BOOT_TIMEOUT (seconds).'
}
die() { printf 'boot.sh: %s\n' "$*" >&2; exit 1; }
drm=0; shell=0
for arg in "$@"; do
    case "$arg" in
        --drm) drm=1;; --shell) shell=1;; -h|--help) usage; exit 0;;
        *) usage >&2; die "unknown argument: $arg";;
    esac
done
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
build=${GLANDA_BUILD:-$here/../build}
out=$build/linux; firmware=$out/fw_jump.elf; plugin=$build/model/libglandagpu.so
if ((drm)); then out+=/drm; fi
spike=${SPIKE:-spike}; dtc=${DTC:-dtc}; limit=${BOOT_TIMEOUT:-120}
[[ $limit =~ ^[1-9][0-9]*$ ]] || die 'BOOT_TIMEOUT must be a positive whole number'
for tool in "$spike" "$dtc"; do command -v "$tool" >/dev/null || die "cannot find $tool"; done
for file in "$plugin" "$firmware" "$out/Image" "$out/initramfs.cpio"; do
    [[ -f $file && -r $file ]] || die "missing/unreadable: $file (see linux/README.md)"
done
bootargs='console=ttyS0,115200 earlycon rdinit=/init panic=-1'
if ((drm && !shell)); then
    bootargs+=' glanda.kmstest=1'
    for tool in sha256sum pnmtopng; do command -v "$tool" >/dev/null || die "DRM verification needs $tool (coreutils/netpbm)"; done
fi
common=("$spike" -p1 -m256 --priv=msu "--extlib=$plugin" --device=glandagpu
        "--kernel=$out/Image" "--initrd=$out/initramfs.cpio" "--bootargs=$bootargs")
"${common[@]}" --dump-dts "$firmware" > "$out/spike-base.dts"
cp -- "$out/spike-base.dts" "$out/spike-linux.dts"
if ! grep -Fq 'gpu@40000000' "$out/spike-base.dts"; then
    cat >> "$out/spike-linux.dts" <<'DTS'

&{/soc} {
    gpu@40000000 { compatible = "glanda,gpu"; reg = <0 0x40000000 0 0x201000>; };
};
DTS
fi
"$dtc" -I dts -O dtb -o "$out/spike-linux.dtb" "$out/spike-linux.dts"
cmd=("${common[@]}" "--dtb=$out/spike-linux.dtb" "$firmware")
if ((shell)); then exec "${cmd[@]}"; fi

work=$(mktemp -d -- "$out/verify-XXXXXXXX"); pid=''; relay=''
cleanup() {
    if [[ -n $pid ]]; then
        kill "$pid" 2>/dev/null || :
        for _ in {1..20}; do kill -0 "$pid" 2>/dev/null || break; sleep .1; done
        kill -KILL "$pid" 2>/dev/null || :; wait "$pid" 2>/dev/null || :
    fi
    if [[ -n $relay ]]; then kill "$relay" 2>/dev/null || :; wait "$relay" 2>/dev/null || :; fi
    rm -rf -- "$work"   # unique directory created above, never a caller-supplied output path
}
trap cleanup EXIT; trap 'exit 130' INT; trap 'exit 143' TERM
log=$out/boot.log; : > "$log"; mkfifo "$work/serial"
tee "$log" < "$work/serial" & relay=$!
if ((drm)); then export GLANDA_VGA_PPM=$work/live.ppm; fi
"${cmd[@]}" </dev/null > "$work/serial" 2>&1 & pid=$!
# SHA256 of P6 header + RGB888 bytes derived independently from the kms-test
# pixel formula, not from a previously observed capture (see drm_frame.py).
expected=7f0f28a8aaada485279fb1e54211afe8d4abf2cb9624ef5ccb8982463065cec0
deadline=$((SECONDS+limit)); marker=GLANDA-DT-PASS
if ((drm)); then marker=GLANDA-KMS-READY; fi
while ((SECONDS < deadline)); do
    if grep -Eq 'GLANDA-DT-FAIL|Kernel panic' "$log"; then die "guest failed; see $log"; fi
    if grep -Eq "^${marker}"$'\r?$' "$log"; then
        if ((!drm)); then exit 0; fi
        # Capture publishes by rename: pin one complete frame for both hash and PNG.
        if [[ -f $work/live.ppm ]]; then
            cp -- "$work/live.ppm" "$work/sample.ppm"
            digest=$(sha256sum < "$work/sample.ppm")
            if [[ ${digest%% *} == "$expected" ]]; then
                pnmtopng "$work/sample.ppm" > "$work/kms.png"
                mv -- "$work/kms.png" "$out/kms.png"
                printf 'PASS: KMS scanout, all 307200 pixels match: %s/kms.png\n' "$out"; exit 0
            fi
        fi
    fi
    kill -0 "$pid" 2>/dev/null || die "Spike exited before verification; see $log"
    sleep .1
done
die "timed out after ${limit}s; see $log"

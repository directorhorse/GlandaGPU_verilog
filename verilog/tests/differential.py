#!/usr/bin/env python3
"""Compare original VHDL vs Verilog at the public top_gpu pins, then check an independent frame."""
import argparse
import os
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory

TESTS = Path(__file__).resolve().parent
ROOT = TESTS.parents[1]
MODULES = ('vram', 'gpu_regs', 'gpu_engine', 'vga_controller', 'top_gpu')
REG = 1 << 19  # word address
BG, RECT, LINE, CPU = 0x123, 0xe4a, 0x5c2, 0x83f


def stimulus(folder):
    vectors, checks = [], {}
    cycle = 0

    def drive(n=1, reset=0, wr=0, rd=0, addr=0, data=0, **expected):
        nonlocal cycle
        vectors.append(f'{n} {reset} {wr} {rd} {addr} {data:08x}\n')
        if expected:
            checks[cycle + n - 1] = expected
        cycle += n

    def write(a, d, **kw):
        drive(addr=a, data=d, wr=1, **kw)

    def read(a, q, **kw):
        drive(addr=a, rd=1, q=q, wait=0, **kw)

    def draw(cmd, xy, wh, color):
        write(REG+2, xy); write(REG+3, wh); write(REG+4, color)
        read(REG+2, xy); read(REG+3, wh); read(REG+4, color)
        write(REG+1, 16+cmd)
        read(REG, 3)  # start bridges to busy; vsync idle high

    drive(4, reset=1)
    write(REG+6, 3); drive(); read(REG+6, 3)
    draw(1, 0, 0, BG)
    drive(307200, rd=1, addr=0, wait=1)  # hold request across clear / arbitration
    drive(8, rd=1, addr=0, wait=0, q=BG, irq=1)
    read(307199, BG); read(REG+5, 1, irq=1)
    write(REG+5, 1, irq=0); drive(); read(REG+5, 0)
    draw(2, (4 << 16)+20, (3 << 16)+7, RECT)
    drive(32); read(4*640+20, RECT); read(6*640+26, RECT); read(6*640+27, BG)
    # A descending diagonal through the rectangle; both endpoints inclusive.
    draw(3, (8 << 16)+28, (2 << 16)+22, LINE)
    drive(20); read(8*640+28, LINE); read(2*640+22, LINE)
    write(307200, 0xfffff000+CPU); read(0, CPU)  # out-of-range maps to pixel zero
    drive(4, reset=1, irq=0)  # rewind timing, retain VRAM
    release = cycle
    write(REG+6, 2); drive(800*525)  # one complete, pipeline-aligned frame
    read(REG+5, 2, irq=1); write(REG+5, 2, irq=0); drive(); read(REG+5, 0)
    (folder/'vectors.txt').write_text(''.join(vectors))
    return cycle, release+1, checks


def events(path, cycles):
    out = {}
    for line in path.read_text().lower().splitlines():
        cycle, val = line.split(); cycle = int(cycle)
        if cycle in out or (out and cycle <= prev):
            raise ValueError(f'{path}: invalid cycle {cycle}')
        if val != 'end' and (len(val) != 49 or set(val)-set('01x')):
            raise ValueError(f'{path}: bad sample {val!r}')
        out[cycle] = val
        prev = cycle
    if 0 not in out or out.get(cycles) != 'end' or len(out) < 2 or prev != cycles:
        raise ValueError(f'{path}: incomplete trace, expected {cycles} cycles')
    return out


def verify(folder, cycles, frame, checks):
    a, b = (events(folder/name, cycles) for name in ('vhdl.trace','verilog.trace'))
    va = vb = None
    for c in sorted(set(a) | set(b)):
        va, vb = a.get(c, va), b.get(c, vb)
        if va != vb:
            raise ValueError(f'cycle {c}: GHDL {va} vs Icarus {vb} (wait irq hs vs active rgb[11:0] q[31:0])')
    colors = {}
    for c in range(cycles):
        if c in a:
            val = a[c]
            pins = dict(wait=val[0], irq=val[1], q=val[17:])
            raster = val[2:17]
        for pin, expected in checks.get(c, {}).items():
            if pins[pin] != format(expected, f'0{len(pins[pin])}b'):
                raise ValueError(f'cycle {c}: {pin}={pins[pin]}, expected {expected:#x}')
        if frame <= c < frame + 800*525:
            y,x = divmod(c-frame, 800)
            active = x<640 and y<480
            rgb = BG if active else 0
            if x==0 and y==0: rgb = CPU
            if 20<=x<27 and 4<=y<7: rgb = RECT
            if 2<=y<=8 and x==20+y: rgb = LINE
            expected = f'{int(not 656<=x<752)}{int(not 490<=y<492)}{int(active)}{rgb:012b}'
            if raster != expected:
                raise ValueError(f'cycle {c} frame ({x},{y}): hs/vs/active/rgb {raster}, expected {expected}')
            if active: colors[rgb] = colors.get(rgb,0)+1
    print(f'PASS: {cycles} cycles pin-equivalent; {len(checks)} MMIO/IRQ checks; '
          '420000 raster samples checked, active colors ' + ', '.join(f'{k:03x}:{v}' for k,v in colors.items()))


def run(folder, args):
    cycles, frame, checks = stimulus(folder)
    def invoke(cmd):
        subprocess.run(cmd, cwd=folder, check=True)
    invoke([args.ghdl, '-a','--std=08', *[ROOT/'src'/f'{m}.vhd' for m in MODULES], TESTS/'diff_tb.vhd'])
    invoke([args.ghdl, '-e','--std=08','diff_tb'])
    invoke([args.ghdl, '-r','--std=08','diff_tb','--assert-level=error'])
    invoke([args.iverilog, '-g2012','-s','diff_tb','-o','diff.vvp',
            *[ROOT/'verilog'/f'{m}.v' for m in MODULES], TESTS/'diff_tb.v'])
    invoke([args.vvp,'diff.vvp'])
    verify(folder, cycles, frame, checks)


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    for tool in ('ghdl', 'iverilog', 'vvp'):
        p.add_argument('--'+tool, default=os.environ.get(tool.upper(),tool))
    p.add_argument('--work-dir', type=Path, help='retain traces and vectors in this directory')
    args = p.parse_args()
    if args.work_dir:
        args.work_dir.mkdir(parents=True, exist_ok=True)
        run(args.work_dir.resolve(), args)
    else:
        with TemporaryDirectory(prefix='glandagpu-diff-') as tmp:
            run(Path(tmp), args)

#!/usr/bin/env python3
"""Check the guest test card on captured VGA pins, then losslessly export PNG.

Uses only Python's standard library. Never generates or repairs pixel data.
"""
import argparse
from pathlib import Path
import re
import struct
import zlib

W, H = 640, 480


def read_frame(path):
    data = path.read_bytes()
    # Comments/whitespace may separate header tokens. Consume only the final
    # delimiter (or CRLF), since whitespace is valid binary raster data.
    sep = rb'(?:\s|\#[^\r\n]*(?:\r\n|[\r\n]))+'
    header = re.match(sep.join([b'P6', rb'(\d+)', rb'(\d+)', rb'(\d+)'])
                      + rb'(?:\r\n|\s)', data)
    if not header or tuple(map(int, header.groups())) != (W, H, 255):
        raise ValueError('expected P6, 640x480, maxval 255')
    raster = data[header.end():]
    if len(raster) != W * H * 3:
        raise ValueError(f'expected one RGB frame ({W*H*3} bytes), got {len(raster)}')
    if any(v % 17 for v in set(raster)):
        raise ValueError('RGB channels must duplicate the RTL nibble (e.g. 0xa -> 0xaa)')
    return raster


def check(raster):
    def pixel(x, y, rgb444):
        off = 3 * (y * W + x)
        actual = raster[off:off+3]
        expected = bytes(((rgb444 >> s) & 15) * 17 for s in (8, 4, 0))
        if actual != expected:
            raise ValueError(f'pixel ({x},{y}): expected #{expected.hex()}, got #{actual.hex()}')

    # Every edge pixel: detects row/column phase errors, bad stride and flips.
    for x in range(W):
        pixel(x, 0, 0x8bd)
        pixel(x, H-1, 0x357)
    for y in range(1, H-1):
        pixel(0, y, 0x59a)
        pixel(W-1, y, 0xd85)

    # Full-width cross sections at chip and ramp boundaries, not just centers.
    chips = [0xfed, 0xfd3, 0x4ee, 0x5d6, 0xe6c, 0xf54, 0x56e]
    for x in range(1, W-1):
        chip, local = divmod(x-28, 84)
        c = chips[chip] if 0 <= chip < 7 and local < 80 else 0x123
        gray = ((x-32)//36)*0x111 if 32 <= x < 608 else 0x123
        for y in (32, 73, 119):
            pixel(x, y, c)
        for y in (360, 399, 439):
            pixel(x, y, gray)
        for y in (31, 120, 359, 440):
            pixel(x, y, 0x123)

    # Independent landmarks for layered shapes: panel/surround, letter strokes
    # and holes, graticule, trace endpoints, and overwritten grid crossings.
    landmarks = {
        0x123: [(27, 144), (612, 335), (320, 336)],
        0x124: [(28, 144), (611, 335), (72, 224), (112, 228), (160, 230), (401, 168)],
        0xefc: [(50, 210), (81, 239), (100, 261), (130, 225), (151, 250), (169, 261)],
        0xe6c: [(48, 278), (181, 281)],
        0x246: [(212, 160), (596, 320), (372, 200), (311, 288)],
        0xfb4: [(212, 248), (244, 248), (296, 224), (400, 168), (412, 240),
                (424, 312), (512, 216), (596, 248)],
    }
    for color, points in landmarks.items():
        for x, y in points:
            pixel(x, y, color)


def write_png(path, raster):
    def chunk(kind, payload):
        return (struct.pack('>I', len(payload)) + kind + payload
                + struct.pack('>I', zlib.crc32(kind + payload)))

    stride = 3 * W
    rows = b''.join(b'\0' + raster[i:i+stride] for i in range(0, len(raster), stride))
    ihdr = struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0)  # RGB8, no interlace
    path.write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr)
                     + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ppm', nargs='?', type=Path, default=Path('build/vga.ppm'))
    parser.add_argument('png', nargs='?', type=Path, default=Path('build/vga.png'))
    args = parser.parse_args()
    try:
        raster = read_frame(args.ppm)
        check(raster)
        write_png(args.png, raster)
    except (ValueError, OSError) as exc:
        parser.exit(1, f'FAIL: {exc}\n')
    print(f'PASS: VGA edges, chroma, luma, monogram, grid and waveform; wrote {args.png}')


if __name__ == '__main__':
    main()

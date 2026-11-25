/* GLANDA test card: an RGB strip, GPU monogram, scope trace and luma wedge.
 * RV64I, no stack. All pixel writes come from the RTL drawing engine. */
    .equ REGS,   0x40200000
    .equ STATUS, 0
    .equ CTRL,   4
    .equ COORD0, 8
    .equ COORD1, 12
    .equ COLOR,  16

    .macro primitive cmd, x, y, u, v, rgb
    li a0, (\y << 16) | \x
    li a1, (\v << 16) | \u
    li a2, \rgb
    li a3, \cmd
    call draw
    .endm
    .macro rect x, y, w, h, color
    primitive 0x12, \x, \y, \w, \h, \color
    .endm
    .macro line x, y, u, v, color
    primitive 0x13, \x, \y, \u, \v, \color
    .endm

    .section .text.init,"ax",@progbits
    .globl _start
_start:
    li s0, REGS
    primitive 0x11, 0, 0, 0, 0, 0x123

    /* Overscan rulers reach both active-video edges. */
    line 0, 0, 639, 0, 0x8bd
    line 0, 479, 639, 479, 0x357
    line 0, 1, 0, 478, 0x59a
    line 639, 1, 639, 478, 0xd85

    /* Seven 80-pixel-wide chroma chips, separated by narrow gutters. */
    rect 28, 32, 80, 88, 0xfed
    rect 112, 32, 80, 88, 0xfd3
    rect 196, 32, 80, 88, 0x4ee
    rect 280, 32, 80, 88, 0x5d6
    rect 364, 32, 80, 88, 0xe6c
    rect 448, 32, 80, 88, 0xf54
    rect 532, 32, 80, 88, 0x56e

    /* Letterforms made of solid engine rectangles. */
    rect 28, 144, 584, 192, 0x124
    rect 48, 208, 38, 8, 0xefc
    rect 48, 216, 8, 48, 0xefc
    rect 56, 256, 30, 8, 0xefc
    rect 78, 236, 8, 20, 0xefc
    rect 68, 236, 10, 8, 0xefc
    rect 96, 208, 8, 56, 0xefc
    rect 104, 208, 30, 8, 0xefc
    rect 126, 216, 8, 20, 0xefc
    rect 104, 236, 30, 8, 0xefc
    rect 144, 208, 8, 48, 0xefc
    rect 174, 208, 8, 48, 0xefc
    rect 144, 256, 38, 8, 0xefc
    rect 48, 278, 134, 4, 0xe6c

    /* Scope graticule under an ECG-style amber waveform. */
    .irp x,212,244,276,308,340,372,404,436,468,500,532,564,596
    line \x, 160, \x, 320, 0x246
    .endr
    .irp y,160,192,224,256,288,320
    line 212, \y, 596, \y, 0x246
    .endr
    line 212, 248, 272, 248, 0xfb4
    line 272, 248, 296, 224, 0xfb4
    line 296, 224, 320, 248, 0xfb4
    line 320, 248, 368, 248, 0xfb4
    line 368, 248, 384, 264, 0xfb4
    line 384, 264, 400, 168, 0xfb4
    line 400, 168, 424, 312, 0xfb4
    line 424, 312, 440, 248, 0xfb4
    line 440, 248, 480, 248, 0xfb4
    line 480, 248, 512, 216, 0xfb4
    line 512, 216, 544, 248, 0xfb4
    line 544, 248, 596, 248, 0xfb4

    /* Full RGB444 neutral ramp: 16 adjacent steps at 36 pixels per step. */
    li s1, (360 << 16) | 32
    li s2, 0
    li s3, 16
1:  mv a0, s1
    li a1, (80 << 16) | 36
    mv a2, s2
    li a3, 0x12
    call draw
    addi s1, s1, 36
    addi s2, s2, 0x111
    addi s3, s3, -1
    bnez s3, 1b

    /* First falling vsync aligns to a boundary; the next two complete two
     * whole frame periods after draw() confirmed idle. Host timeout bounds
     * all polling, including this loop if the scan generator stops. */
    li s1, 3
wait_high:
    lw t0, STATUS(s0)
    andi t0, t0, 2
    beqz t0, wait_high
wait_low:
    lw t0, STATUS(s0)
    andi t0, t0, 2
    bnez t0, wait_low
    addi s1, s1, -1
    bnez s1, wait_high
    .option push
    .option norelax
    lla t0, tohost
    .option pop
    li t1, 1
    sd t1, 0(t0)
2:  j 2b

draw:
    sw a0, COORD0(s0)
    sw a1, COORD1(s0)
    sw a2, COLOR(s0)
    sw a3, CTRL(s0)
3:  lw t0, STATUS(s0)
    andi t0, t0, 1
    bnez t0, 3b
    ret

    .section .tohost,"aw",@progbits
    .balign 64
    .globl tohost
tohost: .dword 0
    .balign 64
    .globl fromhost
fromhost: .dword 0

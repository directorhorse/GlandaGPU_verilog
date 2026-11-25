/* RV64I / LP64; Spike starts at _start in M-mode. No stack or runtime. */
    .equ VRAM,    0x40000000
    .equ REGS,    VRAM + 0x200000
    .equ STATUS,  0x00
    .equ CTRL,    0x04
    .equ COORD0,  0x08
    .equ COORD1,  0x0c
    .equ COLOR,   0x10
    .equ IP,      0x14
    .equ IE,      0x18

    /* A failed comparison leaves its unique Spike exit status in a0. */
    .macro expect reg, value, code
    li a0, \code
    li t2, \value
    bne \reg, t2, finish
    .endm

    .macro setreg offset, value
    li t0, \value
    sw t0, \offset(s1)
    .endm

    .macro pixel x, y, value, code
    li t1, VRAM + 4 * (640 * \y + \x)
    lwu t0, 0(t1)
    expect t0, \value, \code
    .endm

    .section .text.init,"ax",@progbits
    .globl _start
_start:
    li s0, VRAM
    li s1, REGS

    /* Adjacent words must retain independent colors and zero-extend RGB444. */
    li t0, 0xfedcba98
    sw t0, 0(s0)
    li t0, 0xabcdef01
    sw t0, 4(s0)
    pixel 0, 0, 0xa98, 1
    pixel 1, 0, 0xf01, 2

    /* Clear: attempt to read the final pixel without polling for completion.
       The VRAM transaction must wait for the engine's last write. */
    li s2, VRAM + 4 * (640 * 480 - 1)
    sw zero, 0(s2)
    setreg IE, 1
    lwu t0, IE(s1)
    expect t0, 1, 3
    setreg COLOR, 0x246
    setreg CTRL, 0x11
    lwu t0, STATUS(s1)
    andi t0, t0, 1
    expect t0, 1, 4
    lwu t0, 0(s2)
    expect t0, 0x246, 5
    pixel 0, 0, 0x246, 6

    lwu t0, IP(s1)
    andi t0, t0, 1
    expect t0, 1, 7
    setreg IP, 1
    lwu t0, IP(s1)
    andi t0, t0, 1
    expect t0, 0, 8

    /* Rectangle at (1,1), extent 32x2. No MMIO during this CPU loop:
       callbacks for load/store alone cannot advance 64 pixels to idle. */
    setreg COORD0, 0x00010001
    setreg COORD1, 0x00020020
    setreg COLOR, 0x357
    setreg CTRL, 0x12
    li t0, 1000000
1:  addi t0, t0, -1
    bnez t0, 1b
    lwu t0, STATUS(s1)
    andi t0, t0, 1
    expect t0, 0, 9
    pixel 0, 1, 0x246, 10
    pixel 1, 1, 0x357, 11
    pixel 32, 2, 0x357, 12
    pixel 33, 2, 0x246, 13
    pixel 1, 3, 0x246, 14
    lwu t0, IP(s1)
    andi t0, t0, 1
    expect t0, 1, 15

    /* Descending diagonal crosses both rectangle rows. Check both endpoints,
       its middle, and one unchanged neighbor on either side. */
    setreg COORD0, 0x00030003
    setreg COORD1, 0x00010001
    setreg COLOR, 0xe80
    setreg CTRL, 0x13
    lwu t0, STATUS(s1)
    pixel 3, 3, 0xe80, 16
    pixel 2, 2, 0xe80, 17
    pixel 1, 1, 0xe80, 18
    pixel 1, 2, 0x357, 19
    pixel 4, 3, 0x246, 20

    li a0, 0
finish:
    /* HTIF exit word = (status << 1) | 1; success writes exactly 1. */
    slli a0, a0, 1
    ori a0, a0, 1
    .option push
    .option norelax
    lla t0, tohost
    .option pop
    sd a0, 0(t0)
2:  j 2b

    .section .tohost,"aw",@progbits
    .balign 64
    .globl tohost
tohost:   .dword 0
    .balign 64
    .globl fromhost
fromhost: .dword 0

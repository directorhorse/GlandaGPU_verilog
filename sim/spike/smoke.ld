OUTPUT_ARCH(riscv)
ENTRY(_start)

PHDRS
{
    text PT_LOAD FLAGS(5); /* RX */
    data PT_LOAD FLAGS(6); /* RW */
}

SECTIONS
{
    . = 0x80000000; /* Spike's default DRAM base */
    .text : { KEEP(*(.text.init)) *(.text .text.*) } :text
    .rodata : { *(.rodata .rodata.*) } :text

    . = ALIGN(0x1000);
    .tohost : { KEEP(*(.tohost)) } :data
    .data : { *(.data .data.* .sdata .sdata.*) } :data
    .bss (NOLOAD) : { *(.bss .bss.* .sbss .sbss.*) *(COMMON) } :data
    /DISCARD/ : { *(.note.GNU-stack .note.gnu.build-id) }
}

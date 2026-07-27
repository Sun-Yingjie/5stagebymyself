OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    CODE (rx)  : ORIGIN = 0x80000000, LENGTH = 0x1000
    DATA (rwx) : ORIGIN = 0x80001000, LENGTH = 0x1000
}

SECTIONS
{
    .text :
    {
        KEEP(*(.text.init))
        *(.text .text.*)
        *(.rodata .rodata.*)
    } > CODE

    .data :
    {
        *(.data .data.*)
    } > DATA

    .bss (NOLOAD) :
    {
        *(.bss .bss.*)
        *(COMMON)
    } > DATA

    .tohost 0x80001ff0 :
    {
        KEEP(*(.tohost))
    } > DATA

    __stack_top = 0x80001fe0;
}

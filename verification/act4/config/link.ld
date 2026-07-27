/* SPDX-License-Identifier: Apache-2.0 */

TEST_BASE = 0x80000000;
TEST_LIMIT = 0x80040000;
TOHOST = 0x8003fff0;
NUM_HARTS = 1;
STACK_SIZE = 0x400;

OUTPUT_ARCH("riscv")
ENTRY(rvtest_entry_point)

PROVIDE(__stack_size = STACK_SIZE);
PROVIDE(__num_harts = NUM_HARTS);
PROVIDE(tohost = TOHOST);
PROVIDE(fromhost = TOHOST + 8);

SECTIONS
{
  . = TEST_BASE;

  .text.init   : { *(.text.init) }
  .text.rvtest : { *(.text.rvtest) *(.text.rvtest.*) }

  . = ALIGN(16);
  .rodata : { *(.rodata) *(.rodata.*) *(.srodata) *(.srodata.*) }
  .data   : { *(.data) *(.data.*) *(.sdata) *(.sdata.*) }

  . = ALIGN(16);
  .bss : {
    __bss_start = .;
    *(.sbss) *(.sbss.*) *(.bss) *(.bss.*) *(COMMON)
    . = ALIGN(16);
    __bss_end = .;
  }

  . = ALIGN(16);
  __stack_bottom = .;
  . += __stack_size * __num_harts;
  __stack_top = .;

  . = ALIGN(16);
  .text.rvmodel : {
    *(.text.rvmodel) *(.text.rvmodel.*) *(.text) *(.text.*)
  }

  . = ALIGN(16);
  _end = .;
  ASSERT(_end <= TOHOST, "ACT4 image overlaps the tohost mailbox")

  . = TOHOST;
  .tohost : { KEEP(*(.tohost)) }
  ASSERT(. <= TEST_LIMIT, "ACT4 image exceeds the 256 KiB program memory")
}

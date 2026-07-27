    .option norvc
    .section .text.init, "ax", @progbits
    .globl _start
_start:
    addi x1,  x0, 7
    addi x2,  x0, 9
    mul  x3,  x1, x2

    la   x4, data_word
    sw   x3,  0(x4)
    lw   x5,  0(x4)
    beq  x5,  x3, 1f
    jal  x0,  fail

1:
    csrrw x6, mscratch, x5
    csrrs x7, mscratch, x0
    bne   x7, x5, fail

    la   x8, result_word
    sw   x7, 0(x8)

    addi x10, x0, 1
    la   x11, tohost
    sw   x10, 0(x11)

hang:
    jal  x0, hang

fail:
    addi x10, x0, 3
    la   x11, tohost
    sw   x10, 0(x11)
    jal  x0, hang

    .section .data, "aw", @progbits
    .balign 4
data_word:
    .word 0x11223344
result_word:
    .word 0

    .section .tohost, "aw", @progbits
    .balign 8
    .globl tohost
tohost:
    .dword 0
    .globl fromhost
fromhost:
    .dword 0

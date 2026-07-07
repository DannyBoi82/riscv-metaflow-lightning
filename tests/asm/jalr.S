    .text
    .global main
main:
    li x8, 0x40001c
    li x9, 0x400000
    li x2, 0x400024

    jalr x20, x8
    jalr x21, x9
    jalr x22, x2
    jalr x23, x9

    addi x10, x0, 10
    ecall

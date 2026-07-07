    .text
    .global main
main:
    li x8, 0xfffffff0
    li x9, 0x00ff
    li x11, 0xff00

    slti x3, x0, 0x7ff
    slti x4, x0, 0x000
    slti x5, x0, -0x800
    slti x6, x8, -1
    slti x20, x8, 0x4
    slti x21, x11, -0x4
    slti x22, x11, -1

    slti x0, x0, 0x7ff
    addi x10, x0, 10
    ecall

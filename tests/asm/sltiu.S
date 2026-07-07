    .text
    .global main
main:
    li x8, 0xfffffff0
    li x9, 0x00ff
    li x11, 0xff00

    sltiu x3, x0, 0x7ff
    sltiu x4, x0, 0x000
    sltiu x5, x0, -0x800
    sltiu x6, x8, -1
    sltiu x20, x8, 0x4
    sltiu x21, x11, -0x4
    sltiu x22, x11, -1

    sltiu x0, x0, 0x7ff
    addi x10, x0, 10
    ecall

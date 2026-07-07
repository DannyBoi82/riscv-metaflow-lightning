    .text
    .global main
main:
    li x8, 0xff00
    li x9, 0x00ff
    li x11, 0xff000000
    li x12, 0x00ff0000
    li x14, 0x00001234
    li x15, 0x12340000
    li x17, 0x12341234
    li x18, 0x12341234

    or x2, x8, x9
    or x13, x11, x12
    or x16, x14, x15
    or x19, x17, x18

    addi x10, x0, 10
    ecall

    .text
    .global main
main:
    li x8, 0xff00
    li x9, 0x00ff
    li x11, 0xff00
    li x12, 0xff00
    li x14, 0xff000000
    li x15, 0x00ff0000
    li x17, 0xffff0000
    li x18, 0xffff0000
    li x20, 0x12340000
    li x21, 0x00001234
    li x23, 0x12341234
    li x24, 0x12341234

    xor x2, x8, x9
    xor x13, x11, x12
    xor x16, x14, x15
    xor x19, x17, x18
    xor x22, x20, x21
    xor x25, x23, x24

    xor x0, x8, x9
    addi x10, x0, 10
    ecall

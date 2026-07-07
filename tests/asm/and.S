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
    li x20, 0x12341234
    li x21, 0x12341234

    and x2, x8, x9
    and x13, x11, x12
    and x16, x14, x15
    and x19, x17, x18
    and x22, x20, x21
    and x25, x23, x24

    addi x10, x0, 10
    and x0, x10, x10
    ecall

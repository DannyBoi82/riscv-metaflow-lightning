    .text
    .global main
main:
    auipc x3,  0x7ffff
    auipc x4,  0x00000
    auipc x5,  0x80000
    auipc x6,  0xfffff
    auipc x20,  0x4
    auipc x21,  0x4
    auipc x22,  0xfff

    auipc x0, 0xfffff
    addi x10, x0, 10
    ecall

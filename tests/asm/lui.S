    .text
    .global main
main:
    lui x3,  0x7ffff
    lui x4,  0x00000
    lui x5,  0x80000
    lui x6,  0xfffff
    lui x20,  0x4
    lui x21,  0x4
    lui x22,  0xfff

    lui x0, 0xfffff
    addi x10, x0, 10
    ecall

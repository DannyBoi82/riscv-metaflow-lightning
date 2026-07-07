    .text
    .global main
main:
    li x8, 0x400018
    li x9, 0x400000

    jr x8
    jr x9
    addi x1, x0, -1

    addi x10, x0, 10
    ecall

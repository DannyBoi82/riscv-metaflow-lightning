    .text
    .global main
main:
    ori x2, x0, 0x0001
    ori x3, x0, 0x0005
    ori x8, x0, -0x0002
    ori x9, x2, -0x0002
    ori x11, x9, -0x0009

    ori x0, x0, 0x0001
    addi x10, x0, 10
    ecall

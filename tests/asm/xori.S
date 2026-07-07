    .text
    .global main
main:
    xori x2, x0, 0x0001
    xori x3, x0, 0x0005
    xori x8, x0, -0x0002
    xori x9, x2, -0x0002
    xori x11, x9, -0x0009

    xori x0, x0, 0x0001
    addi x10, x0, 10
    ecall

    .text
    .global main
main:
    addi x1, x0, -1
    andi x2, x1, 5
    andi x9, x2, -2
    andi x8, x9, -9

    addi x10, x0, 10
    andi x0, x10, -1
    ecall

    .text
    .global main
main:
    addi x2, x0, 1
    addi x2, x0, 5
    addi x9, x2, -2
    addi x8, x9, -9

    addi x10, x0, 10
    addi x0, x10, 0
    ecall

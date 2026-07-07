    .text
    .global main
main:
    addi x8, x0, 500
    addi x9, x0, -200

    add x2, x8, x8
    add x11, x8, x9
    add x12, x9, x8
    add x13, x9, x9

    addi x10, x0, 10
    add x0, x10, x10
    ecall

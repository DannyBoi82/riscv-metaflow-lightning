    .text
    .global main
main:
    li x8, 500
    li x9, -200

    sub x2, x8, x8
    sub x11, x8, x9
    sub x12, x9, x8
    sub x13, x9, x9

    sub x0, x8, x9
    addi x10, x0, 10
    ecall

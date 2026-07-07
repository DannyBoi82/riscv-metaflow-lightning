    .text
    .global main
main:
    li x8, 10
    li x9, 20
    li x2, -10
    li x11, -20

    slt x12, x8, x9
    slt x13, x9, x8
    slt x14, x8, x2
    slt x15, x2, x8
    slt x16, x2, x11
    slt x17, x11, x2

    slt x0, x8, x9
    addi x10, x0, 10
    ecall

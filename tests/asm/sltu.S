    .text
    .global main
main:
    li x8, 10
    li x9, 20
    li x2, -10
    li x11, -20

    sltu x12, x8, x9
    sltu x13, x9, x8
    sltu x14, x8, x2
    sltu x15, x2, x8
    sltu x16, x2, x11
    sltu x17, x11, x2

    sltu x0, x8, x9
    addi x10, x0, 10
    ecall

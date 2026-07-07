    .text
    .global main
main:
    li x8, 0xffffffff
    li x9, 0x00ff
    li x11, 0xff00

    bgeu x9, x0, taken1
    addi x1, x0, 11
    addi x10, x0, 10
    ecall

taken1:
    bgeu x0, x0, taken2
    addi x1, x0, 31
    addi x10, x0, 10
    ecall

taken2:
    bgeu x8, x0, taken3
    addi x1, x0, 41
    addi x10, x0, 10
    ecall

taken3:
    addi x1, x0, 51
    addi x10, x0, 10
    ecall

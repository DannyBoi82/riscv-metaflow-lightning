    .text
    .global main
main:
    li x8, 0xcccccccc
    li x9, 1
    li x11, 0x55555555
    li x12, 10
    li x14, 0xcccccccc
    li x15, 32
    li x17, 0xcccccccc
    li x18, 40

    sra x2, x8, x9
    sra x13, x11, x12
    sra x16, x14, x15
    sra x19, x17, x18

    sra x0, x8, x9
    addi x10, x0, 10
    ecall

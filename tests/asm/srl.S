    .text
    .global main
main:
    li x8, 0xcccccccc
    li x9, 1
    li x11, 10
    li x13, 0xcccccccc
    li x14, 32
    li x16, 0xcccccccc
    li x17, 40

    srl x2, x8, x9
    srl x12, x8, x11
    srl x15, x13, x14
    srl x18, x16, x17

    srl x0, x8, x9
    addi x10, x0, 10
    ecall

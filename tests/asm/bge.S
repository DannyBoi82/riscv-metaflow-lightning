    .text
    .global main
main:
    li x8, 0xffffffff
    li x9, 0x00ff
    li x11, 0xff00

    bge x8, x0, nottaken
    bge x9, x0, taken1
    addi x1, x0, 10
    addi x10, x0, 10
    ecall

nottaken:
    addi x1, x0, 20
    addi x10, x0, 10
    ecall

taken1:
    bge x0, x0, taken2
    addi x1, x0, 30
    addi x10, x0, 10
    ecall

taken2:
    addi x1, x0, 40
    addi x10, x0, 10
    ecall

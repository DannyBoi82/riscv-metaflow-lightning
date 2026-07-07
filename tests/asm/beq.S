    .text
    .global main
main:
    li x8, 0xff00
    li x9, 0x00ff
    li x11, 0xff00

    beq x8, x9, nottaken
    beq x0, x0, taken1
    addi x1, x0, 1
    addi x10, x0, 10
    ecall

nottaken:
    addi x1, x0, 2
    addi x10, x0, 10
    ecall

taken1:
    beq x8, x11, taken2
    addi x1, x0, 3
    addi x10, x0, 10
    ecall

taken2:
    addi x1, x0, 4
    addi x10, x0, 10
    ecall

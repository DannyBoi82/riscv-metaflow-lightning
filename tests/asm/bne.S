    .text
    .global main
main:
    li x8, 0xff00
    li x9, 0x00ff
    li x11, 0xff00

    bne x8, x11, nottaken
    bne x0, x0, nottaken
    bne x9, x11, taken
    addi x1, x0, -1
    addi x10, x0, 10
    ecall

nottaken:
    addi x1, x0, -2
    addi x10, x0, 10
    ecall

taken:
    addi x1, x0, -3
    addi x10, x0, 10
    ecall

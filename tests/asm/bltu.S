    .text
    .global main
main:
    li x8, 0xffffffff
    li x9, 0x00ff
    li x11, 0xff00

    bltu x9, x0, nottaken
    bltu x0, x0, nottaken
    bltu x8, x0, nottaken
    addi x1, x0, -11
    addi x10, x0, 10
    ecall

nottaken:
    addi x1, x0, -21
    addi x10, x0, 10
    ecall

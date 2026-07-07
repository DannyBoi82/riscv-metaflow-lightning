    .text
    .global main
main:
    li x2, 0x12345678

        # Zero shift
        sll x11, x2, 0

        # Shift away
        sll x12, x2, 16
        sll x13, x12, 16

        # Random shift
        sll x14, x2, 7

        sll x0, x2, 0
    addi x10, x0, 10
    ecall

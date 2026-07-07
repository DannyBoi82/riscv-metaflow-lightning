    .text
    .global main
main:
    li x2, 0x12345678
    li x12, 0x80000000

        srai x11, x2, 0

        # Shift away
        srai x13, x2, 16
        srai x14, x13, 16

        # Random shift
        srai x15, x2, 7

        # Don't sign extend shift
        srai x16, x12, 16

        srai x0, x2, 0
    addi x10, x0, 10
    ecall

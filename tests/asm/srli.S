    .text
    .global main
main:
    li x2, 0x12345678
    li x12, 0x80000000

        srl x11, x2, 0

        # Shift away
        srl x13, x2, 16
        srl x14, x13, 16

        # Random shift
        srl x15, x2, 7

        # Don't sign extend shift
        srl x16, x12, 16

        srl x0, x2, 0
    addi x10, x0, 10
    ecall

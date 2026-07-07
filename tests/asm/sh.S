    .data
data:
    .space 20
data_end:

    .text
    .global main
main:
    li x2, 0x10000000
    li x11, 0x10000005
    li x12, 0x1234
    li x13, 0x5678
    li x14, 0x4321
    li x15, 0x0123

    # Store word aligned
        sh x12, 0(x2)

        # Store word also aligned
        sh x13, 2(x2)

        # Store word also aligned
        sh x14, -1(x11)

        # Store halfword also aligned
        sh x15, 1(x11)

        # Verify memory ordering
        lw x16, 0(x2)
        lw x17, -1(x11)

    addi x10, x0, 10
    ecall

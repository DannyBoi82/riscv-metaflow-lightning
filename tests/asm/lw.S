    .data
data:
    .space 20
data_end:

    .text
    .global main
main:
    li x2, 0x10000000
    li x11, 0x10000001
    li x3, 0x12345687
    li x4, 0x78654321

    # Store word aligned
        sw x3, 0(x2)

        # Store word also aligned
        sw x4, 3(x11)

        # Load word aligned
        lw x13, 0(x2)
        lw x14, 4(x2)

        # Load word also aligned
        lw x15, 3(x11)

        lw x0, 3(x11)
    addi x10, x0, 10
    ecall

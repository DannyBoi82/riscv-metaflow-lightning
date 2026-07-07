    .data
data:
    .space 20
data_end:

    .text
    .global main
main:
    la x2, data
    li x11, 0x123456ff

        # Store word aligned
        sw x11, 0(x2)

        # Load byte
        lbu x12, 0(x2)

        # Load byte
        lbu x13, 1(x2)

        # Load byte
        lbu x14, 2(x2)

        # Load byte
        lbu x15, 3(x2)

        lbu x0, 3(x2)
    addi x10, x0, 10
    ecall

    .data
data:
    .space 20
data_end:

    .text
    .global main
main:
    li x2, 0x10000000
    li x11, 0x10000005
    li x3, 0x1234ffff
    li x4, 0xaaaa4321

        # Store word aligned
        sw x3, 0(x2)
        sw x4, 4(x2)

        # Load word aligned
        lhu x13, 0(x2)

        # Load word also aligned
        lhu x14, 2(x2)

        # Load word also aligned
        lhu x15, 1(x11)

        # Load word also aligned
        lhu x16, -1(x11)

        lhu x0, -1(x11)
    addi x10, x0, 10
    ecall

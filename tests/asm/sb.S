    .data
data:
    .space 20
data_end:

    .text
    .global main
main:
    li x2, 0x10000000
    li x11, 0x00AA
    li x12, 0x00BB
    li x13, 0x00CC
    li x14, 0x00DD

        # Store byte
        sb x11, 0(x2)

        # Store byte
        sb x12, 1(x2)

        # Store byte
        sb x13, 2(x2)

        # Store byte
        sb x14, 3(x2)

        # Verify memory ordering
        lw x15, 0(x2)

    addi x10, x0, 10
    ecall

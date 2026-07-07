    .data
data:
    .space 20
data_end:

    .text
    .global main
main:
    li x2, 0x10000000
    li x11, 0x10000001
    li x12, 0x78654312
    li x13, 0x12345687

    sw x12, 0(x2)

        # Store word also aligned
        sw x13, 3(x11)

    lw x14, 0(x2)
    lw x15, 3(x11)
    lb x16, 3(x11)

    addi x10, x0, 10
    ecall

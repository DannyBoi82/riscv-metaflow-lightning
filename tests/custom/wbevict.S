# wbevict.S
#
# Directed test for the writeback cache controller:
#   1. Dirty a full block (A) with sw.
#   2. Fill two more blocks (B, C) that map to the same set (2-way cache,
#      set stride = 32 sets * 16 B = 0x200) so C's fill evicts dirty A
#      and forces a multi-beat writeback, with loads immediately behind it.
#   3. Reload A — it must come back from memory with the written values.

#define DATA_SEG_SIZE 2048

    .data
data:
    .space  DATA_SEG_SIZE

    .text
    .global main
main:
    add     x1,  zero, gp       # x1 = base of .data

    addi    x5,  zero, 0x111
    addi    x6,  zero, 0x222
    addi    x7,  zero, 0x333
    addi    x8,  zero, 0x444

    sw      x5,  0(x1)          # dirty block A (all four words)
    sw      x6,  4(x1)
    sw      x7,  8(x1)
    sw      x8,  12(x1)

    lw      x10, 0x200(x1)      # block B -> same set, fills other way
    lw      x11, 0x400(x1)      # block C -> evicts dirty A, writeback
    lw      x12, 0(x1)          # immediately reload A (miss, refill)
    lw      x13, 4(x1)
    lw      x14, 8(x1)
    lw      x15, 12(x1)

    sb      x5,  17(x1)         # partial stores into block at +16
    sh      x6,  22(x1)
    lw      x16, 16(x1)
    lw      x17, 20(x1)

    lw      x20, 0x200(x1)      # B should still hit or refill cleanly
    lw      x21, 0x400(x1)      # C too

    addi    a0,  zero, 0xa
    ecall

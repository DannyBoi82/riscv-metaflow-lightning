# wbevict2.S
#
# Directed test: store-miss write-allocate that evicts a DIRTY line
# (WRITE_WAIT_MEM_RSP -> WRITE_CACHE_DATA -> WRITE_EVICT_WRITEBACK),
# with memory ops immediately behind the eviction, plus store->load
# turnarounds on the written-back block.

#define DATA_SEG_SIZE 4096

    .data
data:
    .space  DATA_SEG_SIZE

    .text
    .global main
main:
    add     x1,  zero, gp

    addi    x5,  zero, 0x5a5
    addi    x6,  zero, 0x6b6
    addi    x7,  zero, 0x7c7

    sw      x5,  0(x1)          # dirty block A (one word only)
    lw      x10, 0x200(x1)      # block B fills the other way (clean)
    sw      x6,  0x400(x1)      # block C: store MISS -> write-allocate fill
                                #   -> evicts dirty A -> writeback
    lw      x11, 0x404(x1)      # load right behind the eviction (same block C)
    sw      x7,  0x600(x1)      # block D: store miss -> evicts B (clean)
    lw      x12, 0(x1)          # reload A: must return 0x5a5 from memory
    lw      x13, 0x400(x1)      # C hits (or refills): 0x6b6
    lw      x14, 0x600(x1)      # D: 0x7c7
    lw      x15, 0x200(x1)      # B refill (was clean-evicted): 0

    sw      x5,  0x204(x1)      # dirty B's block again
    sw      x6,  0x604(x1)      # dirty D more
    lw      x16, 0x204(x1)
    lw      x17, 0x604(x1)

    addi    a0,  zero, 0xa
    ecall

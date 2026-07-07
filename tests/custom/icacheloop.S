# icache_loop.S
#
# I-cache back-to-back hit stress test
#
# A tight counted loop of 5 instructions that fits entirely within one
# cache block (4 words = 16 bytes). Every iteration after the first cold
# miss should be pure I-cache hits, giving a clean run of sequential
# back-to-back hits to observe in DVE.
#
# Loop body (5 instructions, 20 bytes — spans 2 cache blocks intentionally
# so you also see a block-crossing fetch):
#   addi  x5, x5, 1     — increment counter
#   addi  x6, x6, 2     — increment by 2 (something to forward)
#   add   x7, x5, x6    — use both, forces forwarding path
#   addi  x8, x8, -1    — decrement loop counter
#   bne   x8, zero, loop — branch back (predicted taken by BTB after 1st iter)
#
# Expected waveform pattern after warmup:
#   - First iteration: 2 I-cache misses (2 block fetches)
#   - Every subsequent iteration: 5 consecutive hits, no misses
#   - On final iteration: bne falls through (mispredicted if BTB predicted taken)
#
# Register usage:
#   x5  — running counter (incremented by 1 each iter)
#   x6  — running counter (incremented by 2 each iter)
#   x7  — x5 + x6 (last computed value)
#   x8  — loop countdown (starts at ITERS, counts to 0)
#   a0  — ecall argument
 
    .text
    .global _start
_start:
    # Set loop count. Keep small enough that simulation is fast,
    # but large enough to see many back-to-back hit sequences.
    # 20 iterations = 100 I-cache accesses after the 2 cold misses.
    addi    x8,  zero, 20       # x8 = iteration count
 
    addi    x5,  zero, 0        # x5 = 0
    addi    x6,  zero, 0        # x6 = 0
 
loop:
    addi    x5,  x5,   1        # x5 += 1
    addi    x6,  x6,   2        # x6 += 2
    add     x7,  x5,   x6       # x7 = x5 + x6
    addi    x8,  x8,   -1       # x8 -= 1
    bne     x8,  zero, loop     # if x8 != 0, branch back
 
    # x5 should be 20, x6 should be 40, x7 should be 60
    addi    a0,  zero, 0xa      # ecall halt argument
    ecall
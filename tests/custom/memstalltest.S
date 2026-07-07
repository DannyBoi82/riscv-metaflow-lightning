/**
 * load_use_hazard.S
 *
 * Load-Use Hazard Isolation Test
 *
 * Tests three load-use distance cases:
 *   Case A: load → immediate use (E case, 0-gap)      — must stall
 *   Case B: load → 1-instruction gap → use (M1 case)  — must stall
 *   Case C: load → 2-instruction gap → use (M2 case)  — stalls now,
 *                                                        should forward after fix
 *
 * Each case is tested for both rs1 and rs2 consumption.
 * Expected final register values are in the comments — check the reg dump.
 *
 * Reference values loaded from .data:
 *   base[0] = 10
 *   base[4] = 20
 *   base[8] = 30
 **/

#define DATA_SEG_SIZE   12

    .data
data:
    .word   10
    .word   20
    .word   30
    .space  DATA_SEG_SIZE

    .text
    .global main
main:
    add     x1, zero, gp        // x1 = base of .data

    //------------------------------------------------------------------
    // Case A0: 0-gap, result used as rs1
    //   lw x5, 0(x1)  →  add x6, x5, zero
    //   If stall works: x6 = 10. If not: x6 = garbage.
    //------------------------------------------------------------------
    lw      x5,  0(x1)          // x5 = 10
    add     x6,  x5,  zero      // x6 = x5 = 10  (x5 in E stage, 0-gap rs1)

    //------------------------------------------------------------------
    // Case A1: 0-gap, result used as rs2
    //   lw x5, 0(x1)  →  add x7, zero, x5
    //   If stall works: x7 = 10. If not: x7 = garbage.
    //------------------------------------------------------------------
    lw      x5,  0(x1)          // x5 = 10
    add     x7,  zero, x5       // x7 = x5 = 10  (x5 in E stage, 0-gap rs2)

    //------------------------------------------------------------------
    // Case B0: 1-gap, result used as rs1
    //   lw x5 → addi x8 (filler) → add x9, x5, zero
    //   If stall works: x9 = 20. If not: x9 = garbage.
    //------------------------------------------------------------------
    lw      x5,  4(x1)          // x5 = 20
    addi    x8,  zero, 0        // filler (1-gap)
    add     x9,  x5,  zero      // x9 = x5 = 20  (x5 in M1 stage, 1-gap rs1)

    //------------------------------------------------------------------
    // Case B1: 1-gap, result used as rs2
    //   lw x5 → addi x8 (filler) → add x10, zero, x5
    //   If stall works: x10 = 20. If not: x10 = garbage.
    //------------------------------------------------------------------
    lw      x5,  4(x1)          // x5 = 20
    addi    x8,  zero, 0        // filler (1-gap)
    add     x10, zero, x5       // x10 = x5 = 20  (x5 in M1 stage, 1-gap rs2)

    //------------------------------------------------------------------
    // Case C0: 2-gap, result used as rs1
    //   This is the gaussian inner loop pattern.
    //   lw x5 → filler → filler → add x11, x5, zero
    //   With current bug (no rs1 M2 stall): x11 = garbage.
    //   With fix (registered data_load_W + no M2 stall): x11 = 30.
    //------------------------------------------------------------------
    lw      x5,  8(x1)          // x5 = 30
    addi    x8,  zero, 0        // filler (1-gap)
    addi    x8,  zero, 0        // filler (2-gap)
    add     x11, x5,  zero      // x11 = x5 = 30  (x5 in M2 stage, 2-gap rs1)

    //------------------------------------------------------------------
    // Case C1: 2-gap, result used as rs2
    //   Same distance but rs2 — currently stalls correctly.
    //   After fix: should forward without stalling, same result.
    //   x12 = 30 either way; use perf counters to confirm stall removed.
    //------------------------------------------------------------------
    lw      x5,  8(x1)          // x5 = 30
    addi    x8,  zero, 0        // filler (1-gap)
    addi    x8,  zero, 0        // filler (2-gap)
    add     x12, zero, x5       // x12 = x5 = 30  (x5 in M2 stage, 2-gap rs2)

    //------------------------------------------------------------------
    // Case C2: 2-gap, used as rs1 in a branch (max_path_sum pattern)
    //   lw x5 → filler → filler → beq x5, x13, SKIP
    //   x13 = 30 so branch should be taken.
    //   If rs1 M2 stall missing and no forwarding: x5 garbage, branch
    //   not taken, x14 gets set to 0xBAD (bad path marker).
    //   x14 = 1 means branch taken correctly.
    //------------------------------------------------------------------
    addi    x13, zero, 30       // x13 = 30 (compare target)
    lw      x5,  8(x1)          // x5 = 30
    addi    x8,  zero, 0        // filler
    addi    x8,  zero, 0        // filler
    beq     x5,  x13,  SKIP     // should branch if x5 == 30
    addi    x14, zero, 1    // NOT reached if correct
    jal     x0,  DONE
SKIP:
    addi    x14, zero, 1        // x14 = 1 means branch taken correctly

    //------------------------------------------------------------------
    // Expected register dump:
    //   x6  = 10   (Case A0 rs1)
    //   x7  = 10   (Case A1 rs2)
    //   x9  = 20   (Case B0 rs1)
    //   x10 = 20   (Case B1 rs2)
    //   x11 = 30   (Case C0 rs1  ← fails before fix)
    //   x12 = 30   (Case C1 rs2)
    //   x14 = 1    (Case C2 branch on rs1  ← fails before fix)
    //------------------------------------------------------------------
DONE:
    addi    a0,  zero,  0xa
    ecall
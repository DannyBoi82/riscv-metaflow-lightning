/**
 * load_branch_hazard.S
 *
 * Load-to-Branch Hazard Test (distance 0)
 *
 * Tests the case where a branch immediately follows a load and uses
 * the loaded value as a branch operand (rs1 or rs2). This is the
 * classic load-use hazard at distance 0 for control flow instructions.
 *
 * The stall controller must catch this because:
 *   - lw is in E when beq reaches D  →  stall needed
 *   - without stall: branch evaluates garbage, wrong path taken
 *
 * Expected results (if stalls work correctly):
 *   x10 = 1   (Case A passed — branch on rs1 taken correctly)
 *   x11 = 1   (Case B passed — branch on rs2 taken correctly)
 *   x12 = 1   (Case C passed — branch NOT taken correctly)
 *
 * If any register = 0x69, that case failed.
 **/

#define DATA_SEG_SIZE   8

    .data
data:
    .word   42          // data[0] = 42
    .word   99          // data[4] = 99
    .space  DATA_SEG_SIZE

    .text
    .global main
main:
    add     x1, zero, gp        // x1 = base of .data

    //------------------------------------------------------------------
    // Case A: lw → beq, loaded value used as rs1
    //   lw x5, 0(x1)           x5 = 42
    //   beq x5, x6, HIT_A      branch if x5 == 42
    //
    // x5 is in E when beq is in D — stall controller must catch this.
    // Without stall: x5 is garbage, branch likely not taken → x10 = 0x69
    //------------------------------------------------------------------
    addi    x6,  zero, 42       // x6 = 42 (compare target)
    lw      x5,  0(x1)          // x5 = 42
    beq     x5,  x6,  HIT_A    // rs1 hazard: should branch
    addi    x10, zero, 0x69
    jal     x0,  CASE_B
HIT_A:
    addi    x10, zero, 1        // x10 = 1 means Case A passed

    //------------------------------------------------------------------
    // Case B: lw → beq, loaded value used as rs2
    //   lw x5, 0(x1)           x5 = 42
    //   beq x6, x5, HIT_B      branch if 42 == x5
    //
    // x5 is rs2 here — same distance, different port.
    //------------------------------------------------------------------
CASE_B:
    addi    x6,  zero, 42       // x6 = 42
    lw      x5,  0(x1)          // x5 = 42
    beq     x6,  x5,  HIT_B    // rs2 hazard: should branch
    addi    x11, zero, 0x69
    jal     x0,  CASE_C
HIT_B:
    addi    x11, zero, 1        // x11 = 1 means Case B passed

    //------------------------------------------------------------------
    // Case C: lw → bne, branch should NOT be taken
    //   lw x5, 0(x1)           x5 = 42
    //   bne x5, x6, MISS_C     branch if x5 != 99 — should NOT branch
    //                          since x5 == 42 != 99
    //
    // Without stall: x5 is garbage, branch may be taken → x12 = 0x69
    // This catches the inverse: stall incorrectly suppressed on not-taken.
    //------------------------------------------------------------------
CASE_C:
    addi    x6,  zero, 99       // x6 = 99
    lw      x5,  0(x1)          // x5 = 42
    beq     x5,  x6,  MISS_C   // should NOT branch (42 != 99)
    addi    x12, zero, 1        // x12 = 1 means Case C passed (fall-through correct)
    jal     x0,  DONE
MISS_C:
    addi    x12, zero, 0x69    // should NOT be reached

DONE:
    addi    a0,  zero, 0xa
    ecall


/**
 * riscv_commit.vh
 *
 * Lightning — commit packet definition (the verify-trace seam).
 *
 * This is the design-independent contract between a core and the simulation
 * harness: every cycle, a core reports the instructions it *retired* that
 * cycle as an array of commit packets, oldest first in slot order. The
 * testbench-side commit_verifier consumes the packets to reconstruct
 * architectural register state per committed instruction (see README,
 * "verify-trace").
 *
 * Field names follow the RVFI (RISC-V Formal Interface) conventions so a
 * future riscv-formal / Spike co-sim hookup is a rename away. As in RVFI,
 * rd_addr == 0 means "no architectural register write" — writes to x0 are
 * architectural no-ops and must be reported with rd_addr = 0, rd_wdata = 0.
 *
 * A design does not have to use tb/register_file.sv to produce packets
 * (e.g. a physical-register-file design has no architectural regfile
 * module at all); it only has to drive an array of these packets at its
 * retirement point. Wrong-path/flushed instructions must never appear.
 **/

`ifndef RISCV_COMMIT_VH_
`define RISCV_COMMIT_VH_

`include "riscv_isa.vh"

package RISCV_Commit;

    import RISCV_ISA::XLEN;

    /* Maximum retire slots the harness supports per cycle. Interfaces expose
     * a fixed [COMMIT_WAYS_MAX-1:0] packet array so the testbench does not
     * depend on any per-core retire width; slots a core does not use stay
     * invalid ('0). Bump this if a core ever retires wider. */
    parameter int COMMIT_WAYS_MAX = 8;

    typedef struct packed {
        logic            valid;      // one retired instruction in this slot
        logic [XLEN-1:0] pc_rdata;   // PC of the retired instruction
        logic [XLEN-1:0] insn;       // instruction word (debug/reporting only)
        logic [4:0]      rd_addr;    // destination register; 0 = no write
        logic [XLEN-1:0] rd_wdata;   // value written; 0 when rd_addr == 0
    } commit_pkt_t;

endpackage: RISCV_Commit

`endif /* RISCV_COMMIT_VH_ */

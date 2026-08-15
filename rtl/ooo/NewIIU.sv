// import DRIS_defs::*;
// import RISCV_ISA::*;
// import RISCV_UArch::*;  // Import microarchitecture parameters and definitions
// import internal_defines_pkg::*;     // Control signals struct, ALU ops

// `include "parameters.vh"
// `include "memory_segments.vh"
// `include "riscv_abi.vh"

// `default_nettype none

// typedef struct packed {
//     logic [XLEN-1:0] pc;
//     logic [XLEN-1:0] predicted_pc;
//     logic [1:0] btb_hist;               // 2-bit counter read at predict time
//     dris_id_t id;                       // DRIS ID for register renaming
//     ctrl_signals_t ctrl_signals;        // control signals for the instruction
//     logic valid;
// } shelf_intake_pkt_t;

// // Shelf -> BTB training port: one resolved branch/JALR per cycle.
// typedef struct packed {
//     logic            valid;
//     logic [XLEN-1:0] pc;                // resolving branch's own PC (write key)
//     logic [XLEN-1:0] next_pc;           // computed next PC (stored as the target)
//     logic            taken;
//     logic            correct;           // prediction matched
//     logic [1:0]      hist;              // counter bits captured at predict time
//     ctrl_signals_t   ctrl_signals;
// } btb_train_pkt_t;

// module InstructionIssueUnit #(
//     parameter int FETCH_WORDS       = DRIS_defs::FETCH_WAYS,
//     parameter int ADDRESS_SIZE      = 30,
//     parameter int BLOCK_OFFSET_BITS = INSTR_CACHE_BLOCK_OFFSET_BITS,
//     parameter int BLOCK_SIZE        = INSTR_CACHE_BLOCK_SIZE,
//     parameter int NUM_UPDATE_PORTS  = DRIS_defs::EXECUTE_WAYS
// )(
//     input  logic clock, reset_n,

//     /* ============================================================
//      * DRIS interface
//      * ============================================================
//      */
//     input  dris_entry_t               dris_entries [DRIS_NUM_ENTRIES-1:0],
//     output dris_intake_pkt_t          dris_intake_pkts [FETCH_WORDS-1:0],
//     output logic [DRIS_ID_WIDTH:0]    fetch_ptr,      // extra MSB = color bit

//     // Snooped by the branch shelf to capture computed next PCs (next_pc_W)
//     input  dris_writeback_pkt_t       update_bus [NUM_UPDATE_PORTS-1:0],

//     /* ============================================================
//      * Sane State Controller interface
//      * ============================================================ */
//     input  logic [DRIS_ID_WIDTH:0]    retire_ptr,
//     output dris_id_t                  oldest_branch_id,
//     output logic                      branch_fence_valid,
//     output logic [DRIS_NUM_ENTRIES-1:0] flush_mask,
//     input  logic                      trap_valid,
//     input  logic [XLEN-1:0]           trap_pc,

//     /* ============================================================
//      * I-side cache controller (core_req_* / core_rsp_* seam)
//      * ============================================================ */
//     output logic                      core_req_re,
//     output logic [ADDRESS_SIZE-1:0]   core_req_addr,
//     output logic                      core_req_cancel,
//     output logic                      core_req_stall_mem,
//     input  logic [FETCH_WORDS-1:0][XLEN-1:0] core_rsp_data,
//     input  logic [ADDRESS_SIZE-1:0]   core_rsp_addr,
//     input  logic                      core_rsp_data_valid,
//     input  logic                      core_rsp_ready,
//     input  logic                      core_rsp_excpt,

//     /* ============================================================
//      * Performance-counter observation ports.
//      *
//      * Always present (the PERF block that consumes them lives in
//      * LightningCore and is the only `ifdef'd part), and observation
//      * only — none of these feed back into the IIU. The alternative,
//      * cross-module hierarchical references from the core's counter
//      * block, is not portable across VCS and Verilator, which this
//      * repo has to keep both of.
//      * ============================================================ */
//     // Branch shelf occupancy this cycle, and its capacity, so the core
//     // can normalize without importing BRANCH_SHELF_ENTRIES itself.
//     output logic [$clog2(DRIS_defs::BRANCH_SHELF_ENTRIES+1)-1:0]
//                                       perf_shelf_occupancy,
//     // Shelf resolution events (see BranchShelf below) and the mispredict
//     // pulse they produce one cycle later.
//     output logic                      perf_branch_resolved,
//     output logic                      perf_branch_mispredicted,
//     output logic                      perf_branch_mispredict_squashed,
//     output logic                      perf_mispredict_valid,
//     // Front-end blocking: intake stalled, and why. The two reasons are
//     // reported raw (they can both be true in the same cycle).
//     output logic                      perf_intake_stall,
//     output logic                      perf_stall_dris_full,
//     output logic                      perf_stall_shelf_full,
//     // A fetch group was accepted into the DRIS this cycle.
//     output logic                      perf_issue_fire
// );

//     logic [XLEN-1:2] block, block_F1, block_F2, next_block;
//     logic [XLEN-1:2] btb_predicted_block;

//     always_ff @(posedge clock, negedge reset_n) begin: pc_block_reg
//         if (~reset_n) block <= MemorySegments::USER_TEXT_START;
//         else block <= next_block;
//     end

//     //this is now only being used to predict the next block to fetch, not
//     //the actual pc itself
//     BTBPredictor btb (
//         .clk                       (clock),
//         .rst_l                     (reset_n),
//         .pc_F1                     ({block, 2'b00}),
//         .npc_plus4_F1              ({block_F1 + '1, 2'b00}),
//         .predicted_next_pc         (btb_predicted_block[XLEN-1:2]),
//         .read_btb_hist             (btb_read_hist),
//         .taken_branch              (),
//         .btb_hit                   (),
//         .bcond_write               (btb_train.taken),
//         .ctrl_signals_write        (btb_write_ctrl),
//         .correct_branch_prediction (btb_train.correct),
//         .pc_write                  (btb_train.pc),
//         .npc_offset_write          (btb_train.next_pc),
//         .write_btb_hist            (btb_train.hist)
//     );

//     /* =================================================================
//      * Branch shelf intake: one packet per valid CT slot. intake_stall
//      * guarantees enough free shelf entries for all of them.
//      * ================================================================= */
//     always_comb begin : shelf_intake
//         shelf_in_pkt = '0;
//         for (int w = 0; w < FETCH_WORDS; w++) begin
//             if (issue_fire && slot_valid[w] && slot_is_ct[w]) begin
//                 shelf_in_pkt[w].valid        = 1'b1;
//                 shelf_in_pkt[w].pc           = slot_pc[w];
//                 shelf_in_pkt[w].predicted_pc = slot_pred_pc[w];
//                 shelf_in_pkt[w].id           = slot_id(fetch_ptr, w);
//                 shelf_in_pkt[w].ctrl_signals = slot_ctrl[w];
//                 // Only the BTB-read slot has meaningful counter bits;
//                 // everything else trains from a cold counter.
//                 shelf_in_pkt[w].btb_hist =
//                     (primary_ct_found && w == primary_ct_slot &&
//                      slot_ctrl[w].pc_source != PC_uncond) ? btb_read_hist
//                                                           : 2'b00;
//             end
//         end
//     end : shelf_intake

//     BranchShelf #(
//         .NUM_SHELF_ENTRIES(DRIS_defs::BRANCH_SHELF_ENTRIES),
//         .NUM_UPDATE_PORTS (NUM_UPDATE_PORTS),
//         .FETCH_WAYS       (FETCH_WORDS)
//     ) branch_shelf (
//         .clock              (clock),
//         .reset_n            (reset_n),
//         .dris_entries       (dris_entries),
//         .shelf_in_pkt       (shelf_in_pkt),
//         .shelf_alloc_valid  (shelf_alloc_valid),
//         .shelf_free_count   (shelf_free_count),
//         .btb_train          (btb_train),
//         .update_bus         (update_bus),
//         .global_flush       (trap_valid),
//         .mispredict_valid   (mispredict_valid),
//         .mispredict_pc      (mispredict_pc),
//         .mispredict_branch_id(mispredict_branch_id),
//         .oldest_branch_id   (oldest_branch_id),
//         .branch_fence_valid (branch_fence_valid),
//         .flush_mask         (flush_mask),
//         .perf_resolve_valid (perf_branch_resolved),
//         .perf_resolve_wrong (perf_branch_mispredicted),
//         .perf_resolve_wrong_squashed (perf_branch_mispredict_squashed)
//     );

//     /* =================================================================
//      * Perf observation drive. shelf_free_count is the shelf's own
//      * output, so occupancy is just its complement; the stall reasons
//      * reuse the exact terms the intake stall is built from above, so a
//      * change to the stall condition can't leave the counters behind.
//      * ================================================================= */
//     assign perf_shelf_occupancy = $clog2(DRIS_defs::BRANCH_SHELF_ENTRIES+1)'(
//                                       DRIS_defs::BRANCH_SHELF_ENTRIES) -
//                                   shelf_free_count;
//     assign perf_mispredict_valid = mispredict_valid;
//     assign perf_intake_stall     = intake_stall;
//     assign perf_stall_dris_full  = core_rsp_data_valid && !dris_room;
//     assign perf_stall_shelf_full = core_rsp_data_valid && !shelf_room;
//     assign perf_issue_fire       = issue_fire;

//     // TODO: core_rsp_excpt -> instruction-fetch fault (trap plumbing).

// endmodule : InstructionIssueUnit
//now the iiu looks a lot like the fetch side of my in order core
//stages:
//pc, F1, F2 === F1, F2, F3 in the in order core
//DS is a mixture of the decode stage and the new slot prep thing that has to happen
//because superscalar

import DRIS_defs::*;
import RISCV_ISA::*;
import RISCV_UArch::*;  // Import microarchitecture parameters and definitions
import internal_defines_pkg::*;     // Control signals struct, ALU ops

`include "parameters.vh"
`include "memory_segments.vh"
`include "riscv_abi.vh"

`default_nettype none

typedef struct packed {
    ctrl_signals_t ctrl_signals;
    logic [REG_NUM_WIDTH-1:0] rd;
    logic [REG_NUM_WIDTH-1:0] rs1;
    logic [REG_NUM_WIDTH-1:0] rs2;
    logic [XLEN-1:0] imm;
} decoded_instr_t;

typedef struct packed {
    logic [XLEN-1:0] pc;
    logic [XLEN-1:0] predicted_pc;
    logic [1:0] btb_hist;               // 2-bit counter read at predict time
    dris_id_t id;                       // DRIS ID for register renaming
    ctrl_signals_t ctrl_signals;        // control signals for the instruction
    logic valid;
} shelf_intake_pkt_t;

// Shelf -> BTB training port: one resolved branch/JALR per cycle.
typedef struct packed {
    logic            valid;
    logic [XLEN-1:0] pc;                // resolving branch's own PC (write key)
    logic [XLEN-1:0] next_pc;           // computed next PC (stored as the target)
    logic            taken;
    logic            correct;           // prediction matched
    logic [1:0]      hist;              // counter bits captured at predict time
    ctrl_signals_t   ctrl_signals;
} btb_train_pkt_t;

module InstructionIssueUnit #(
    parameter int FETCH_WORDS       = DRIS_defs::FETCH_WAYS,
    parameter int ADDRESS_SIZE      = 30,
    parameter int BLOCK_OFFSET_BITS = INSTR_CACHE_BLOCK_OFFSET_BITS,
    parameter int BLOCK_SIZE        = INSTR_CACHE_BLOCK_SIZE,
    parameter int NUM_UPDATE_PORTS  = DRIS_defs::EXECUTE_WAYS
)(
    input  logic clock, reset_n,

    /* ============================================================
     * DRIS interface
     * ============================================================
     */
    input  dris_entry_t               dris_entries [DRIS_NUM_ENTRIES-1:0],
    output dris_intake_pkt_t          dris_intake_pkts [FETCH_WORDS-1:0],
    output logic [DRIS_ID_WIDTH:0]    fetch_ptr,      // extra MSB = color bit

    // Snooped by the branch shelf to capture computed next PCs (next_pc_W)
    input  dris_writeback_pkt_t       update_bus [NUM_UPDATE_PORTS-1:0],

    /* ============================================================
     * Sane State Controller interface
     * ============================================================ */
    input  logic [DRIS_ID_WIDTH:0]    retire_ptr,
    output dris_id_t                  oldest_branch_id,
    output logic                      branch_fence_valid,
    output logic [DRIS_NUM_ENTRIES-1:0] flush_mask,
    input  logic                      trap_valid,
    input  logic [XLEN-1:0]           trap_pc,

    /* ============================================================
     * I-side cache controller (core_req_* / core_rsp_* seam)
     * ============================================================ */
    output logic                      core_req_re,
    output logic [ADDRESS_SIZE-1:0]   core_req_addr,
    output logic                      core_req_cancel,
    output logic                      core_req_stall_mem,
    input  logic [FETCH_WORDS-1:0][XLEN-1:0] core_rsp_data,
    input  logic [ADDRESS_SIZE-1:0]   core_rsp_addr,
    input  logic                      core_rsp_data_valid,
    input  logic                      core_rsp_ready,
    input  logic                      core_rsp_excpt,

    /* ============================================================
     * Performance-counter observation ports.
     *
     * Always present (the PERF block that consumes them lives in
     * LightningCore and is the only `ifdef'd part), and observation
     * only — none of these feed back into the IIU. The alternative,
     * cross-module hierarchical references from the core's counter
     * block, is not portable across VCS and Verilator, which this
     * repo has to keep both of.
     * ============================================================ */
    // Branch shelf occupancy this cycle, and its capacity, so the core
    // can normalize without importing BRANCH_SHELF_ENTRIES itself.
    output logic [$clog2(DRIS_defs::BRANCH_SHELF_ENTRIES+1)-1:0]
                                      perf_shelf_occupancy,
    // Shelf resolution events (see BranchShelf below) and the mispredict
    // pulse they produce one cycle later.
    output logic                      perf_branch_resolved,
    output logic                      perf_branch_mispredicted,
    output logic                      perf_branch_mispredict_squashed,
    output logic                      perf_mispredict_valid,
    // Front-end blocking: intake stalled, and why. The two reasons are
    // reported raw (they can both be true in the same cycle).
    output logic                      perf_stall_pc,
    output logic                      perf_stall_dris_full,
    output logic                      perf_stall_shelf_full,
    // A fetch group was accepted into the DRIS this cycle.
    output logic                      perf_issue_fire
);


    logic [XLEN-1:0] pc, next_pc;

    always_ff @(posedge clock, negedge reset_n) begin: pc_block_reg
        if (~reset_n) pc <= MemorySegments::USER_TEXT_START;
        else if (~stall_pc | flush) pc <= next_pc;
    end

    assign core_req_addr = pc[ADDRESS_SIZE-1:2];
    assign core_req_re   = ~dris_full & ~shelf_full;

    // +0, +4, +8, +12
    logic [XLEN-1:0] block_pc [3:0], block_pc_F1[3:0], block_pc_F2[3:0], block_pc_D[3:0];
    logic [XLEN-1:0] btb_predicted_pc_block_F1 [3:0], btb_predicted_pc_block_F2 [3:0], btb_predicted_pc_block_D [3:0];
    logic [XLEN-1:0] btb_best_prediction_F1, btb_best_prediction_F2, btb_best_prediction_D;
    logic [1:0] btb_read_hist_F1 [3:0], btb_read_hist_F2 [3:0], btb_read_hist_D [3:0];

    assign block_pc[0] = pc[XLEN-1:0];
    assign block_pc[1] = pc[XLEN-1:0] + 'd4;
    assign block_pc[2] = pc[XLEN-1:0] + 'd8;
    assign block_pc[3] = pc[XLEN-1:0] + 'd12;

    always_ff @(posedge clock, negedge reset_n) begin: PCtoF1
        if (~reset_n) begin
            block_pc_F1[0] <= MemorySegments::USER_TEXT_START;
            block_pc_F1[1] <= MemorySegments::USER_TEXT_START + 'd4;
            block_pc_F1[2] <= MemorySegments::USER_TEXT_START + 'd8;
            block_pc_F1[3] <= MemorySegments::USER_TEXT_START + 'd12;
        end else if (flush)begin
            block_pc_F1[0] <= {28'd0, pc_mispredict_flush};
            block_pc_F1[1] <= {28'd0, pc_mispredict_flush};
            block_pc_F1[2] <= {28'd0, pc_mispredict_flush};
            block_pc_F1[3] <= {28'd0, pc_mispredict_flush};
        end else if (~stall_F1) begin
            block_pc_F1 <= block_pc;
        end
    end

    //this is now only being used to predict the next block to fetch, not
    //the actual pc itself
    BTBPredictor4 btb (
        .clk                       (clock),
        .rst_l                     (reset_n),
        .block_pc                  (block_pc), //needs to do rotation internally
        //.npc_plus4_F1              ({block_F1 + '1, 2'b00}), //also do pc+4 internally
        .predicted_pc_block        (btb_predicted_pc_block_F1),
        .best_prediction              (btb_best_prediction_F1), //needs to output the pc most likely to be fetched next 
        //to give to the pc (the i cache)
        .read_btb_hist             (btb_read_hist_F1), //this is also a vector now
        .taken_branch              (),
        .btb_hit                   (),

        // only one write port because the branch shelf
        //resolves one branch per cycle
        .bcond_write               (btb_train.taken),
        .ctrl_signals_write        (btb_write_ctrl),
        .correct_branch_prediction (btb_train.correct),
        .pc_write                  (btb_train.pc),
        .npc_offset_write          (btb_train.next_pc),
        .write_btb_hist            (btb_train.hist)
    );

    assign next_pc = mispredict_valid ? mispredict_pc : btb_best_prediction_F1;

    always_ff @(posedge clock, negedge reset_n) begin: F1_to_F2
        if (~reset_n) begin
            block_pc_F2[0] <= MemorySegments::USER_TEXT_START;
            block_pc_F2[1] <= MemorySegments::USER_TEXT_START + 'd4;
            block_pc_F2[2] <= MemorySegments::USER_TEXT_START + 'd8;
            block_pc_F2[3] <= MemorySegments::USER_TEXT_START + 'd12;
            btb_read_hist_F2 <= '0;
            btb_best_prediction_F2 <= MemorySegments::USER_TEXT_START + 'd4;
        end else if (flush)begin
            block_pc_F2[0] <= {28'd0, pc_mispredict_flush};
            block_pc_F2[1] <= {28'd0, pc_mispredict_flush};
            block_pc_F2[2] <= {28'd0, pc_mispredict_flush};
            block_pc_F2[3] <= {28'd0, pc_mispredict_flush};
            btb_read_hist_F2 <= '0;
            btb_best_prediction_F2 <= {28'd0, pc_mispredict_flush};
        end else if (~stall_F2) begin
            block_pc_F2 <= block_pc_F1;
            btb_read_hist_F2 <= btb_read_hist_F1;
            btb_best_prediction_F2 <= btb_best_prediction_F1;
        end
    end

    //instuctions show up at end of f2
    logic [XLEN-1:0] fetched_instructions_F2 [FETCH_WORDS-1:0], 
    fetched_instructions_D [FETCH_WORDS-1:0];
    logic [FETCH_WORDS-1:0] fetched_instructions_valid_F2,
    fetched_instructions_valid_D;
    assign fetched_instructions_F2 = core_rsp_data;

    int valid_instrs_idx;
    always_comb begin: valid_instrs_logic
        fetched_instructions_valid_F2 = '0;
        for (int w = 0; w < FETCH_WORDS; w++) begin

            //first instruction fetched is instruction of the pc, so
            //that one should always be valid.
            if (w == '0) fetched_instructions_valid_F2[w] = 1'b1;
            else begin
                //the rest of the instructions are valid
                // if the pc of the instruction matches the predicted pc of the previous instruction
                fetched_instructions_valid_F2[w] = block_pc_F2[w] == btb_predicted_pc_block_F2[w-1];
            end
        end
    end : valid_instrs_logic

    always_ff @(posedge clock, negedge reset_n) begin: F2_to_DS
        if (~reset_n) begin
            block_pc_D[0] <= MemorySegments::USER_TEXT_START;
            block_pc_D[1] <= MemorySegments::USER_TEXT_START + 'd4;
            block_pc_D[2] <= MemorySegments::USER_TEXT_START + 'd8;
            block_pc_D[3] <= MemorySegments::USER_TEXT_START + 'd12;
            btb_read_hist_D <= '0;
            btb_best_prediction_D <= '0;
            fetched_instructions_D <= '0;
            fetched_instructions_valid_D <= '0;
        end else if (flush)begin
            block_pc_D[0] <= {28'd0, pc_mispredict_flush};
            block_pc_D[1] <= {28'd0, pc_mispredict_flush};
            block_pc_D[2] <= {28'd0, pc_mispredict_flush};
            block_pc_D[3] <= {28'd0, pc_mispredict_flush};
            btb_read_hist_D <= '0;
            btb_best_prediction_D <= {28'd0, pc_mispredict_flush};
            fetched_instructions_D <= '0;
            fetched_instructions_valid_D <= '0;
        end else if (~stall_D) begin
            block_pc_D <= block_pc_F2;
            btb_read_hist_D <= btb_read_hist_F2;
            btb_best_prediction_D <= btb_best_prediction_F2;
            fetched_instructions_D <= fetched_instructions_F2;
            fetched_instructions_valid_D <= fetched_instructions_valid_F2;
        end
    end

    /* =================================================================
     * Per-slot decode
     * ================================================================= */
    decoded_instr_t decoded_instrs_D [FETCH_WORDS-1:0];

    generate
        for (genvar w = 0; w < FETCH_WORDS; w++) begin : slot_decode
            riscv_decode dec (
                .rst_l        (reset_n),
                .instr        (fetched_instructions_D[w]),
                .ctrl_signals (decoded_instrs_D[w].ctrl_signals),
                .rd           (decoded_instrs_D[w].rd),
                .rs1          (decoded_instrs_D[w].rs1),
                .rs2          (decoded_instrs_D[w].rs2)
            );
            ImmediateGenerator ig (
                .instr     (fetched_instructions_D[w]),
                .imm_mode  (decoded_instrs_D[w].imm_mode),
                .immediate (decoded_instrs_D[w].imm)
            );
        end : slot_decode
    endgenerate

    //this might be backwards
    logic [3:0] slot_valid;
    always_comb begin : slot_valid_logic
        case (block_pc_D[0][3:2])
            2'b00: slot_valid = 4'b1111;
            2'b01: slot_valid = 4'b1110;
            2'b10: slot_valid = 4'b1100;
            2'b11: slot_valid = 4'b1000;
        endcase
        slot_valid = slot_valid & {4{~flush}} & {4{core_rsp_data_valid}};
    end : slot_valid_logic

    // block_pc_D
    // btb_read_hist_D
    // fetched_instructions_D 


    /* =================================================================
     * Branch shelf intake: one packet per valid CT slot. stall_pc
     * guarantees enough free shelf entries for all of them.
     * ================================================================= */
    shelf_intake_pkt_t shelf_in_pkt [FETCH_WORDS-1:0];
    always_comb begin : shelf_intake
        shelf_in_pkt = '0;
        for (int w = 0; w < FETCH_WORDS; w++) begin
            if (issue_fire && slot_valid[w] && slot_is_ct[w]) begin
                shelf_in_pkt[w].valid        = 1'b1;
                shelf_in_pkt[w].pc           = slot_pc[w];
                shelf_in_pkt[w].predicted_pc = slot_pred_pc[w];
                shelf_in_pkt[w].id           = slot_id(fetch_ptr, w);
                shelf_in_pkt[w].ctrl_signals = slot_ctrl[w];
                // Only the BTB-read slot has meaningful counter bits;
                // everything else trains from a cold counter.
                shelf_in_pkt[w].btb_hist =
                    (primary_ct_found && w == primary_ct_slot &&
                     slot_ctrl[w].pc_source != PC_uncond) ? btb_read_hist
                                                          : 2'b00;
            end
        end
    end : shelf_intake

    BranchShelf #(
        .NUM_SHELF_ENTRIES(DRIS_defs::BRANCH_SHELF_ENTRIES),
        .NUM_UPDATE_PORTS (NUM_UPDATE_PORTS),
        .FETCH_WAYS       (FETCH_WORDS)
    ) branch_shelf (
        .clock              (clock),
        .reset_n            (reset_n),
        .dris_entries       (dris_entries),
        .shelf_in_pkt       (shelf_in_pkt),
        .shelf_alloc_valid  (shelf_alloc_valid),
        .shelf_free_count   (shelf_free_count),
        .btb_train          (btb_train),
        .update_bus         (update_bus),
        .global_flush       (trap_valid),
        .mispredict_valid   (mispredict_valid),
        .mispredict_pc      (mispredict_pc),
        .mispredict_branch_id(mispredict_branch_id),
        .oldest_branch_id   (oldest_branch_id),
        .branch_fence_valid (branch_fence_valid),
        .flush_mask         (flush_mask),
        .perf_resolve_valid (perf_branch_resolved),
        .perf_resolve_wrong (perf_branch_mispredicted),
        .perf_resolve_wrong_squashed (perf_branch_mispredict_squashed)
    );

    assign flush = trap_valid || mispredict_valid;

    always_comb begin : stall_logic
        {stall_pc, stall_F1, stall_F2, stall_D} = '0;
        if (dris_full | shelf_full) begin
            //if out of space, stall everything
            {stall_pc, stall_F1, stall_F2, stall_D} = 4'b1111;
        end else if (~instr_valid & ~i_cache_ready) begin
            //if the cache pipeline is full and the data isnt back yet
            //stall everything
            {stall_pc, stall_F1, stall_F2, stall_D} = 4'b1111;
        end else if (instr_valid & ~i_cache_ready) begin
            {stall_pc, stall_F1, stall_F2, stall_D} = 4'b1100;
        end

        //this still doesnt make sense to me but it works in the inorder core
        // Remaining cases (~instr_valid &  i_cache_ready) and
        //                  (instr_valid &  i_cache_ready) need no stall.
    end : stall_logic



    /* =================================================================
     * Perf observation drive. shelf_free_count is the shelf's own
     * output, so occupancy is just its complement; the stall reasons
     * reuse the exact terms the intake stall is built from above, so a
     * change to the stall condition can't leave the counters behind.
     * ================================================================= */
    assign perf_shelf_occupancy = $clog2(DRIS_defs::BRANCH_SHELF_ENTRIES+1)'(
                                      DRIS_defs::BRANCH_SHELF_ENTRIES) -
                                  shelf_free_count;
    assign perf_mispredict_valid = mispredict_valid;
    assign perf_stall_pc     = stall_pc;
    assign perf_stall_dris_full  = core_rsp_data_valid && !dris_room;
    assign perf_stall_shelf_full = core_rsp_data_valid && !shelf_room;
    assign perf_issue_fire       = issue_fire;

    // TODO: core_rsp_excpt -> instruction-fetch fault (trap plumbing).

endmodule : InstructionIssueUnit

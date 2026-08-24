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

// shelf_intake_pkt_t and btb_train_pkt_t live in DRIS_defs (rtl/ooo/1DRIS_defs.sv),
// not here: BranchShelf.sv sorts ahead of this file and needs them in its port list.

typedef struct packed {
    ctrl_signals_t ctrl_signals;
    logic [REG_NUM_WIDTH-1:0] rd;
    logic [REG_NUM_WIDTH-1:0] rs1;
    logic [REG_NUM_WIDTH-1:0] rs2;
    logic [XLEN-1:0] imm;
} decoded_instr_t;

/**
 * InstructionIssueUnit (IIU) — fetch/decode/issue front end + branch shelf.
 *
 * Structurally this is the in-order core's fetch side (riscv_core.sv,
 * F1->F2->F3->D) widened to FETCH_WORDS. Stages are pc -> F1 -> F2 -> D, and
 * groups in flight are tracked *positionally*: F2 is the response stage, so a
 * request accepted at cycle N sits in block_pc_F2 at N+2, which is exactly the
 * cycle its response reaches the controller's FIFO head. Nothing counts
 * outstanding requests; the stall table below is what keeps position honest,
 * and the assertion at the bottom is what catches it if it ever isn't.
 *
 * Wrong-path groups are killed with the in-order core's PC-tag trick: a flush
 * stamps WPC_FLUSH into every stage, a stall bubble stamps WPC_BUBBLE into F2,
 * and the D stage drops any group whose PC is is_invalid_pc before it reaches the
 * DRIS. Reset stamps a bubble too, which is what covers startup.
 *
 * Prediction: BTBPredictor4 gives every slot of the group its own lookup, so
 * group shape falls out of the predictions alone — slot w is valid iff its PC
 * is what slot w-1 predicted. There are no decode-stage cuts. A JAL or JALR
 * whose BTB entry is cold mispredicts once, the shelf resolves it and trains
 * the exact target, and it predicts correctly from then on. The only redirect
 * sources are trap_valid and the shelf's mispredict_valid.
 *
 * Talks to the I-side cache_controller2 (FETCH_WORDS-widened) over the
 * core_req / core_rsp seam, whose protocol is "same seam and timing as
 * cache_controller_ref" (cache_controller2.sv:4) — which is what lets the
 * in-order core's stall recipe carry over unchanged:
 *   - a request presented while core_rsp_ready=1 is accepted that cycle;
 *   - core_req_stall_mem (the FIFO's peek_only) holds the response head while
 *     the front end is stalled;
 *   - core_req_cancel drops in-flight probes and queued responses, and is
 *     raised only on a mispredict repair.
 *
 * Issue groups are prefix-contiguous, so slot w always gets DRIS ID
 * fetch_ptr + w. Short groups are holes, never noops.
 */
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

    // A group can present at most FETCH_WORDS control transfers, and the
    // intake stall reserves that many shelf entries up front (see stall_logic).
    // If the shelf is smaller than a group the stall can never be satisfied and
    // the front end wedges — the failure mode commit d434d13 hit.
    initial begin
        if (DRIS_defs::BRANCH_SHELF_ENTRIES < FETCH_WORDS)
            $fatal(1, "%m: BRANCH_SHELF_ENTRIES (%0d) < FETCH_WORDS (%0d)",
                   DRIS_defs::BRANCH_SHELF_ENTRIES, FETCH_WORDS);
    end

    /* =================================================================
     * Forward declarations
     * ================================================================= */
    logic                       stall_pc, stall_F1, stall_F2, stall_D;
    logic                       instr_stall, flush;
    logic                       dris_full, shelf_full;
    logic                       issue_fire;
    logic [$clog2(FETCH_WORDS+1)-1:0] group_count;

    logic                       mispredict_valid;
    logic [XLEN-1:0]            mispredict_pc;
    dris_id_t                   mispredict_branch_id;
    logic [$clog2(DRIS_defs::BRANCH_SHELF_ENTRIES+1)-1:0] shelf_free_count;
    logic [FETCH_WORDS-1:0]     shelf_alloc_valid;
    shelf_intake_pkt_t [FETCH_WORDS-1:0] shelf_in_pkt;
    btb_train_pkt_t             btb_train;
    ctrl_signals_t              btb_write_ctrl;

    /* =================================================================
     * Wrong-path / bubble PC tags.
     *
     * Same trick as the in-order core (pc_mispredict_flush / pc_stall_bubble
     * in internal_defines_pkg), but the block_pc pipeline carries *word*
     * addresses and pc_mispredict_flush is odd, so it cannot survive a
     * byte->word narrowing. These are the word-address equivalents: byte
     * 0x2C and 0x34, far below USER_TEXT_START (0x0040_0000), so neither can
     * ever collide with a real fetch address.
     * ================================================================= */
    localparam logic [XLEN-1:2] WPC_FLUSH  = (XLEN-2)'(pc_mispredict_flush);
    localparam logic [XLEN-1:2] WPC_BUBBLE = (XLEN-2)'(pc_stall_bubble);

    function automatic logic is_invalid_pc(input logic [XLEN-1:2] wpc);
        return (wpc == WPC_FLUSH) || (wpc == WPC_BUBBLE);
    endfunction

    logic [XLEN-1:0] pc, next_pc;

    always_ff @(posedge clock, negedge reset_n) begin: pc_block_reg
        if (~reset_n) pc <= MemorySegments::USER_TEXT_START;
        else if (~stall_pc | flush) pc <= next_pc;
    end

    assign core_req_addr = pc[ADDRESS_SIZE+1:2];
    assign core_req_re   = ~dris_full & ~shelf_full & core_rsp_ready & ~flush;

    /* Cancel on a mispredict only.
     *
     * This used to be every redirect, which included the per-group control
     * transfer cut — one on every JAL and every predicted-taken branch, i.e. on
     * *correctly* predicted control flow. Because the controller chains a new
     * probe out of every response cycle, that cancel landed exactly on the cycle
     * the next probe's miss resolved and cleared mem_bus_request in the same
     * block a read_miss sets it (cache_controller2.sv:363-370), so the fill was
     * never requested: fibi took 858 I$ misses for 19 fill requests. See
     * docs/perf-counters.md §4.1a and commit b3855c5.
     *
     * There is no control-transfer cut left in this design at all, so this is
     * now the only cancel source. Everything else redirects the PC and lets the
     * wrong-path responses arrive, where the tag check at D drops them. */
    assign core_req_cancel = mispredict_valid;

    // +0, +4, +8, +12 as WORD addresses — BTBPredictor4's read port is
    // [XLEN-1:2], and so is the predicted_pc_block it returns.
    logic [XLEN-1:2] block_pc [FETCH_WORDS-1:0];
    logic [XLEN-1:2] block_pc_F1 [FETCH_WORDS-1:0],
                     block_pc_F2 [FETCH_WORDS-1:0],
                     block_pc_D  [FETCH_WORDS-1:0];

    // The BTB read is combinational off the PC stage; these are its PC-stage
    // outputs, and the _F1/_F2/_D copies below ride the same three registers
    // block_pc does, so a slot's prediction stays with its own PC. (Riding one
    // register fewer would pair every group with the next group's predictions.)
    logic [XLEN-1:2] btb_pred_pc_block [FETCH_WORDS-1:0];
    logic [1:0]      btb_read_hist [FETCH_WORDS-1:0];
    logic [XLEN-1:0] btb_best_prediction;

    logic [XLEN-1:2] btb_pred_pc_block_F1 [FETCH_WORDS-1:0],
                     btb_pred_pc_block_F2 [FETCH_WORDS-1:0],
                     btb_pred_pc_block_D  [FETCH_WORDS-1:0];
    logic [1:0]      btb_read_hist_F1 [FETCH_WORDS-1:0],
                     btb_read_hist_F2 [FETCH_WORDS-1:0],
                     btb_read_hist_D  [FETCH_WORDS-1:0];

    always_comb begin : block_pc_gen
        for (int w = 0; w < FETCH_WORDS; w++)
            block_pc[w] = pc[XLEN-1:2] + (XLEN-2)'(w);
    end : block_pc_gen

    always_ff @(posedge clock, negedge reset_n) begin: PCtoF1
        if (~reset_n | flush) begin
            for (int w = 0; w < FETCH_WORDS; w++) begin
                block_pc_F1[w]          <= ~reset_n ? WPC_BUBBLE : WPC_FLUSH;
                btb_pred_pc_block_F1[w] <= '0;
                btb_read_hist_F1[w]     <= '0;
            end
        end else if (~stall_F1) begin
            block_pc_F1          <= block_pc;
            btb_pred_pc_block_F1 <= btb_pred_pc_block;
            btb_read_hist_F1     <= btb_read_hist;
        end
    end

    //this is now only being used to predict the next block to fetch, not
    //the actual pc itself
    BTBPredictor4 btb (
        .clk                       (clock),
        .rst_l                     (reset_n),
        .block_pc                  (block_pc), //needs to do rotation internally
        .predicted_pc_block        (btb_pred_pc_block),
        .best_prediction           (btb_best_prediction), //the pc most likely to
        //be fetched next, straight to the pc (the i cache)
        .read_btb_hist             (btb_read_hist), //this is also a vector now
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

    // CTRL_SIGNALS_NOOP's PC_plus4 holds BTBPredictor4's internal write enable
    // off between training packets.
    assign btb_write_ctrl = btb_train.valid ? btb_train.ctrl_signals
                                            : CTRL_SIGNALS_NOOP;

    assign next_pc = trap_valid       ? trap_pc
                   : mispredict_valid ? mispredict_pc
                                      : btb_best_prediction;

    always_ff @(posedge clock, negedge reset_n) begin: F1_to_F2
        if (~reset_n | flush) begin
            for (int w = 0; w < FETCH_WORDS; w++) begin
                block_pc_F2[w]          <= ~reset_n ? WPC_BUBBLE : WPC_FLUSH;
                btb_pred_pc_block_F2[w] <= '0;
                btb_read_hist_F2[w]     <= '0;
            end
        end else if (~stall_F2 & stall_F1) begin
            // F2 is draining but F1 is frozen. Insert a bubble so the same
            // fetch group is not re-latched out of the held F1 register — it
            // would be written to the DRIS twice. The controller is holding
            // its response head for exactly this cycle (peek_only =
            // instr_stall), so the bubble is also what keeps the number of
            // FIFO pops equal to the number of real groups latched at D.
            for (int w = 0; w < FETCH_WORDS; w++) begin
                block_pc_F2[w]          <= WPC_BUBBLE;
                btb_pred_pc_block_F2[w] <= '0;
                btb_read_hist_F2[w]     <= '0;
            end
        end else if (~stall_F2) begin
            block_pc_F2          <= block_pc_F1;
            btb_pred_pc_block_F2 <= btb_pred_pc_block_F1;
            btb_read_hist_F2     <= btb_read_hist_F1;
        end
    end

    //instuctions show up at end of f2
    logic [XLEN-1:0] fetched_instructions_D [FETCH_WORDS-1:0];
    logic [FETCH_WORDS-1:0] fetched_instructions_valid_F2,
    fetched_instructions_valid_D;

    always_comb begin: valid_instrs_logic
        fetched_instructions_valid_F2 = '0;
        for (int w = 0; w < FETCH_WORDS; w++) begin

            //first instruction fetched is instruction of the pc, so
            //that one is valid whenever a response is actually here.
            if (w == '0) fetched_instructions_valid_F2[w] = core_rsp_data_valid;
            else begin
                //the rest of the instructions are valid
                // if the pc of the instruction matches the predicted pc of the previous instruction
                fetched_instructions_valid_F2[w] =
                    // validity has to be a PREFIX: slot w's DRIS ID is
                    // fetch_ptr + w, so a hole would shift every younger
                    // slot's ID off its own instruction.
                    fetched_instructions_valid_F2[w-1] &&
                    (block_pc_F2[w] == btb_pred_pc_block_F2[w-1]) &&
                    // ...and slot w has to still be inside slot 0's cache
                    // block. The chain cannot see the block boundary by
                    // itself: an out-of-block slot is forced to miss in the
                    // BTB (in_group), so it predicts fall-through, and
                    // block_pc[w+1] == block_pc[w]+1 always holds. Meanwhile
                    // cache3.sv:486 fills read_data[word] only while
                    // block_offset + word < BLOCK_SIZE, so the slots past the
                    // boundary are zero words. A group is at most BLOCK_SIZE
                    // words, so a block offset of 0 at any w > 0 is the wrap.
                    (block_pc_F2[w][BLOCK_OFFSET_BITS+1:2] != '0);
            end
        end
    end : valid_instrs_logic

    always_ff @(posedge clock, negedge reset_n) begin: F2_to_DS
        if (~reset_n | flush) begin
            for (int w = 0; w < FETCH_WORDS; w++) begin
                block_pc_D[w]           <= ~reset_n ? WPC_BUBBLE : WPC_FLUSH;
                btb_pred_pc_block_D[w]  <= '0;
                btb_read_hist_D[w]      <= '0;
                fetched_instructions_D[w] <= '0;
            end
            fetched_instructions_valid_D <= '0;
        end else if (~stall_D) begin
            block_pc_D          <= block_pc_F2;
            btb_pred_pc_block_D <= btb_pred_pc_block_F2;
            btb_read_hist_D     <= btb_read_hist_F2;
            for (int w = 0; w < FETCH_WORDS; w++)
                fetched_instructions_D[w] <= core_rsp_data[w];
            fetched_instructions_valid_D  <= fetched_instructions_valid_F2;
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
                .imm_mode  (decoded_instrs_D[w].ctrl_signals.imm_mode),
                .immediate (decoded_instrs_D[w].imm)
            );
        end : slot_decode
    endgenerate

    /* =================================================================
     * Group formation at D.
     *
     * Group *shape* was already decided by the prediction chain at F2 and
     * rode the register down here. All that is left is to drop the group
     * outright if its PC is a wrong-path or bubble tag — flush, stall bubble,
     * or reset. All FETCH_WORDS entries carry the same tag, so testing slot 0
     * covers the group.
     * ================================================================= */
    logic [FETCH_WORDS-1:0] slot_valid, slot_is_ct;
    logic                   group_is_invalid_pc;

    assign group_is_invalid_pc = is_invalid_pc(block_pc_D[0]);
    assign slot_valid   = fetched_instructions_valid_D &
                          {FETCH_WORDS{~group_is_invalid_pc}};

    always_comb begin : slot_ct_logic
        for (int w = 0; w < FETCH_WORDS; w++)
            slot_is_ct[w] = decoded_instrs_D[w].ctrl_signals.pc_source != PC_plus4;
    end : slot_ct_logic

    always_comb begin : group_count_logic
        group_count = '0;
        for (int w = 0; w < FETCH_WORDS; w++)
            group_count += slot_valid[w] ? 1'b1 : 1'b0;
    end : group_count_logic

    assign issue_fire = (|slot_valid) & ~stall_D & ~flush;

    /* =================================================================
     * DRIS intake
     *
     * rd is masked to x0 for non-writing instructions: the decoder's raw
     * rd field is immediate bits for stores/branches, and a garbage rd
     * would create false lockers in the dependency search.
     * ================================================================= */
    always_comb begin : dris_intake
        for (int w = 0; w < FETCH_WORDS; w++) begin
            dris_intake_pkts[w]                = '0;
            dris_intake_pkts[w].valid_R        = issue_fire && slot_valid[w];
            dris_intake_pkts[w].pc_R           = {block_pc_D[w], 2'b00};
            dris_intake_pkts[w].rd_R           = decoded_instrs_D[w].ctrl_signals.rfWrite
                                               ? decoded_instrs_D[w].rd  : '0;
            dris_intake_pkts[w].rs1_R          = decoded_instrs_D[w].ctrl_signals.uses_rs1
                                               ? decoded_instrs_D[w].rs1 : '0;
            dris_intake_pkts[w].rs2_R          = decoded_instrs_D[w].ctrl_signals.uses_rs2
                                               ? decoded_instrs_D[w].rs2 : '0;
            dris_intake_pkts[w].ctrl_signals_R = decoded_instrs_D[w].ctrl_signals;
            dris_intake_pkts[w].imm_R          = decoded_instrs_D[w].imm;
            `ifdef DEBUG
                dris_intake_pkts[w].debug_instr_R = fetched_instructions_D[w];
            `endif
        end
    end : dris_intake

    /* =================================================================
     * fetch_ptr: owned here (allocation happens in the DRIS, but the
     * pointer — and its rollback on repair — is the IIU's).
     * Priority: trap flushes everything (back to retire_ptr); mispredict
     * rolls back to the offending branch's ID + 1 (spec: that ID becomes
     * the next allocation point); otherwise advance by the issued count.
     * ================================================================= */
    always_ff @(posedge clock, negedge reset_n) begin : fetch_ptr_reg
        if (!reset_n)
            fetch_ptr <= '0;
        else if (trap_valid)
            fetch_ptr <= retire_ptr;
        else if (mispredict_valid)
            fetch_ptr <= {mispredict_branch_id.id_color,
                          mispredict_branch_id.id_index} + 1'b1;
        else if (issue_fire)
            fetch_ptr <= fetch_ptr + (DRIS_ID_WIDTH+1)'(group_count);
    end : fetch_ptr_reg

    /* =================================================================
     * Branch shelf intake: one packet per valid CT slot. The intake stall
     * guarantees enough free shelf entries for all of them.
     *
     * Unlike the single-ported predictor this replaced, every slot carries
     * real counter bits — BTBPredictor4 looked all four up — so there is no
     * "primary CT owns the read port" slot to special-case and no cold
     * counter for the younger ones to train from.
     * ================================================================= */
    always_comb begin : shelf_intake
        shelf_in_pkt = '0;
        for (int w = 0; w < FETCH_WORDS; w++) begin
            if (issue_fire && slot_valid[w] && slot_is_ct[w]) begin
                shelf_in_pkt[w].valid        = 1'b1;
                shelf_in_pkt[w].pc           = {block_pc_D[w], 2'b00};
                shelf_in_pkt[w].predicted_pc = {btb_pred_pc_block_D[w], 2'b00};
                shelf_in_pkt[w].id           = slot_id(fetch_ptr, w);
                shelf_in_pkt[w].ctrl_signals = decoded_instrs_D[w].ctrl_signals;
                shelf_in_pkt[w].btb_hist     = btb_read_hist_D[w];
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

    /* =================================================================
     * Intake room.
     *
     * Both reserve a whole group rather than the exact count, because the PC
     * stage decides three cycles before D knows how many slots the group
     * actually has. Reserving FETCH_WORDS shelf entries is also what makes a
     * per-group control-transfer cap unnecessary — a group cannot present
     * more CTs than it has slots.
     * ================================================================= */
    logic [DRIS_ID_WIDTH:0] occupancy;
    assign occupancy  = fetch_ptr - retire_ptr;  // color-bit MSB makes this mod-2N
    assign dris_full  = (DRIS_NUM_ENTRIES - int'(occupancy)) < FETCH_WORDS;
    assign shelf_full = int'(shelf_free_count) < FETCH_WORDS;

    always_comb begin : stall_logic
        {instr_stall, stall_pc, stall_F1, stall_F2, stall_D} = '0;
        if (dris_full | shelf_full) begin
            //if out of space, stall everything
            {instr_stall, stall_pc, stall_F1, stall_F2, stall_D} = 5'b11111;
        end else if (~core_rsp_data_valid & ~core_rsp_ready) begin
            //if the cache pipeline is full and the data isnt back yet
            //stall everything
            {instr_stall, stall_pc, stall_F1, stall_F2, stall_D} = 5'b11111;
        end else if (core_rsp_data_valid & ~core_rsp_ready) begin
            //data is back but the cache cant take a new request: drain F2/D
            //and freeze the front. F1_to_F2 inserts a bubble for this case.
            {instr_stall, stall_pc, stall_F1, stall_F2, stall_D} = 5'b11100;
        end

        //this still doesnt make sense to me but it works in the inorder core
        // Remaining cases (~core_rsp_data_valid &  core_rsp_ready) and
        //                  (core_rsp_data_valid &  core_rsp_ready) need no stall.
    end : stall_logic

    // peek_only: hold the controller's response head. Paired with the F2
    // bubble above, this keeps FIFO pops equal to real groups latched at D.
    assign core_req_stall_mem = instr_stall;

    /* =================================================================
     * Positional-tracking check.
     *
     * F2 is the response stage: a request accepted at cycle N reaches
     * block_pc_F2 at N+2, which is the cycle its response reaches the FIFO
     * head. Nothing counts outstanding requests, so if the stall table ever
     * lets those two drift apart, instructions are silently paired with the
     * wrong PCs. Fatal, not $error — a desync must crash the run, not turn up
     * as a register mismatch dozens of instructions later.
     *
     * The `$time > 0` guard is not decoration: the testbench's clk starts at
     * 1, so its initialization counts as a posedge at time 0 in a 4-state
     * simulator, and reset_n is still high there. Everything below is X on
     * that edge, and $fatal would not survive it.
     * ================================================================= */
    // synopsys translate_off
    always_ff @(posedge clock) begin : fetch_position_assertion
        if ((reset_n === 1'b1) && ($time > 0) &&
            core_rsp_data_valid && !is_invalid_pc(block_pc_F2[0])) begin
            assert (core_rsp_addr == block_pc_F2[0])
            else $fatal(1, "%0t %m: fetch position desync - rsp=%h F2=%h",
                        $time, {core_rsp_addr, 2'b00}, {block_pc_F2[0], 2'b00});
        end
    end : fetch_position_assertion
    // synopsys translate_on

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
    assign perf_stall_pc         = stall_pc;
    assign perf_stall_dris_full  = dris_full;
    assign perf_stall_shelf_full = shelf_full;
    assign perf_issue_fire       = issue_fire;

    // TODO: core_rsp_excpt -> instruction-fetch fault (trap plumbing).

endmodule : InstructionIssueUnit

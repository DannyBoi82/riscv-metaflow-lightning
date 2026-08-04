import DRIS_defs::*;
import RISCV_ISA::*;
import RISCV_UArch::*;  // Import microarchitecture parameters and definitions
import internal_defines_pkg::*;     // Control signals struct, ALU ops

`include "parameters.vh"
`include "memory_segments.vh"
`include "riscv_abi.vh"

`default_nettype none

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

/**
 * InstructionIssueUnit (IIU) — fetch/decode/issue front end + branch shelf.
 *
 * Branch execution model (TODO-IIU.md Phase 0, deviation from Lightning):
 * control transfers dispatch through the Scheduler/ALUs like any other
 * instruction. The exec way's writeback carries two values: result_data_W
 * is always the register-file-bound value (the pc+4 link for JAL/JALR),
 * and next_pc_W is the computed next PC, consumed only by the shelf's
 * snoop. The shelf verifies next_pc_W against the predicted PC and never
 * writes the DRIS — the exec ways are the sole producers of register-
 * file-bound data, the IIU the sole owner of the PC. The branch fence
 * holds retirement until the shelf resolves.
 *
 * Prediction: the oldest CT in a group owns the BTB's single read port.
 * JAL computes its target at decode (never mispredicts); a branch/JALR
 * keys the BTB with its own PC and takes the predicted next PC. Younger
 * CTs in the same group (possible only behind a not-taken-predicted
 * branch) get static predictions: conditional branches predict
 * fall-through, JAL computes exactly, and a younger JALR ends the group
 * before itself — pc+4 for a JALR is a guaranteed mispredict, so it
 * refetches as the oldest CT of the next group and gets a real lookup.
 * The shelf trains the BTB with one resolved branch/JALR per cycle.
 *
 * Talks to the I-side cache_controller2 (FETCH_WORDS-widened) over the
 * core_req / core_rsp seam:
 *   - a request presented while core_rsp_ready=1 is accepted that cycle;
 *   - responses (up to FETCH_WORDS words + their address) pop from the
 *     controller FIFO; core_req_stall_mem holds the FIFO head while intake
 *     is stalled (DRIS full / shelf full), so the controller doubles as the
 *     skid buffer;
 *   - core_req_cancel drops in-flight probes and queued responses on any
 *     redirect (CT cut, mispredict repair, trap).
 *
 * Issue groups are prefix-contiguous: a group ends at the block boundary
 * (controller clamp), right after the first *redirecting* CT (JAL or
 * predicted-taken branch/JALR), or right before a younger JALR, so slot w
 * always gets DRIS ID fetch_ptr + w. Short groups are holes, never noops.
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
    input  logic                      core_rsp_excpt
);

    /* =================================================================
     * Forward declarations (redirect network)
     * ================================================================= */
    logic                       mispredict_valid;
    logic [XLEN-1:0]            mispredict_pc;
    dris_id_t                   mispredict_branch_id;
    logic [$clog2(DRIS_defs::BRANCH_SHELF_ENTRIES+1)-1:0] shelf_free_count;
    logic [FETCH_WORDS-1:0]     shelf_alloc_valid;
    shelf_intake_pkt_t [FETCH_WORDS-1:0] shelf_in_pkt;
    btb_train_pkt_t             btb_train;
    logic [XLEN-1:0]            btb_predicted_pc;
    logic [1:0]                 btb_read_hist;

    logic            redirect, ct_redirect;
    logic [XLEN-1:0] redirect_pc, ct_resume_pc;
    logic            intake_stall;

    /* =================================================================
     * Fetch request / PC maintenance
     * ================================================================= */
    logic [XLEN-1:0] pc_F;   // byte address of the next fetch request
    logic [XLEN-1:0] next_pc;

    // Real backpressure, not just a hold on the response head.
    // core_req_stall_mem (peek_only) keeps the FIFO's *head* in place, but it
    // does not stop the controller: on a hit it enqueues a response and chains
    // the next probe every cycle. The response FIFO is 2 deep and drops
    // enqueues silently when full, so a stall lasting more than two cycles
    // vaporized whole fetch groups whose PCs pc_F had already marched past —
    // instructions that were never refetched (memtest2 lost 0x4000a0-0x4000ac
    // outright). Dropping the request while stalled bounds the outstanding
    // work at one held head + one in-flight probe = exactly the FIFO's depth.
    assign core_req_re     = !intake_stall;
    assign core_req_addr   = pc_F[2 +: ADDRESS_SIZE];
    assign core_req_cancel = redirect;

    // Sequential next fetch: past everything this request will return
    // (the controller clamps the group at the block boundary).
    // pc_F[2 +: BLOCK_OFFSET_BITS] is the word index within the cache block
    // (indexed part-select: variable base, constant width).
    int              words_left, grab;
    logic [XLEN-1:0] seq_next_fetch;
    always_comb begin : seq_fetch
        words_left     = BLOCK_SIZE - int'(pc_F[2 +: BLOCK_OFFSET_BITS]);
        grab           = (words_left < FETCH_WORDS) ? words_left : FETCH_WORDS;
        seq_next_fetch = pc_F + XLEN'(4 * grab);
    end : seq_fetch

    // Redirect must win over the stall hold: mispredict_valid is a one-cycle
    // pulse and core_rsp_ready can be low while the controller works a miss,
    // so "hold while stalled" alone would drop the repair PC.
    // core_rsp_ready alone is not "accepted": the controller holds ready high
    // in states where it would take a request, so pc_F must also see that we
    // actually made one (core_req_re) — otherwise a stalled cycle silently
    // skips a group's worth of PCs.
    always_comb begin : next_pc_mux
        if (redirect)                            next_pc = redirect_pc;
        else if (core_rsp_ready && core_req_re)  next_pc = seq_next_fetch;
        else                                     next_pc = pc_F;  // hold
    end : next_pc_mux

    always_ff @(posedge clock, negedge reset_n) begin : pc_reg
        if (!reset_n) pc_F <= MemorySegments::USER_TEXT_START;
        else          pc_F <= next_pc;
    end : pc_reg

    /* =================================================================
     * Per-slot decode
     * ================================================================= */
    ctrl_signals_t            slot_ctrl [FETCH_WORDS-1:0];
    logic [REG_NUM_WIDTH-1:0] slot_rd   [FETCH_WORDS-1:0];
    logic [REG_NUM_WIDTH-1:0] slot_rs1  [FETCH_WORDS-1:0];
    logic [REG_NUM_WIDTH-1:0] slot_rs2  [FETCH_WORDS-1:0];
    logic [XLEN-1:0]          slot_imm  [FETCH_WORDS-1:0];

    generate
        for (genvar w = 0; w < FETCH_WORDS; w++) begin : slot_decode
            riscv_decode dec (
                .rst_l        (reset_n),
                .instr        (core_rsp_data[w]),
                .ctrl_signals (slot_ctrl[w]),
                .rd           (slot_rd[w]),
                .rs1          (slot_rs1[w]),
                .rs2          (slot_rs2[w])
            );
            ImmediateGenerator ig (
                .instr     (core_rsp_data[w]),
                .imm_mode  (slot_ctrl[w].imm_mode),
                .immediate (slot_imm[w])
            );
        end : slot_decode
    endgenerate

    /* =================================================================
     * Group formation
     *
     * Validity is prefix-contiguous: the block-boundary clamp (from the
     * response address), the cut after the first redirecting CT, and
     * the cut before a younger JALR all truncate a prefix, so slot w's
     * DRIS ID is fetch_ptr + w.
     *
     * Per-slot next-PC prediction (ct = control transfer):
     *   - oldest CT, branch/JALR: BTB keyed on the slot's own PC
     *   - JAL anywhere: pc + imm, exact at decode (always redirects,
     *     because fetch already ran sequentially past it)
     *   - younger branch: static not-taken (pc + 4), group continues
     *   - younger JALR: cut the group *before* it; pc+4 would be a
     *     guaranteed mispredict, so refetch it as oldest of next group
     *
     * A group also never carries more CTs than the branch shelf can hold
     * (CT_PER_GROUP_MAX); the intake stall below waits for *free* shelf
     * entries, and it can only ever be satisfied if the demand fits the
     * shelf's capacity in the first place.
     * ================================================================= */
    // Shelf capacity, clamped to the group width (a group can't hold more
    // CTs than it has slots).
    localparam int CT_PER_GROUP_MAX =
        (DRIS_defs::BRANCH_SHELF_ENTRIES < FETCH_WORDS)
            ? DRIS_defs::BRANCH_SHELF_ENTRIES : FETCH_WORDS;
    logic [FETCH_WORDS-1:0] slot_valid;
    logic [FETCH_WORDS-1:0] slot_is_ct;
    logic [XLEN-1:0]        slot_pc      [FETCH_WORDS-1:0];
    logic [XLEN-1:0]        slot_pred_pc [FETCH_WORDS-1:0];
    logic                   group_has_ct;
    int                     avail;      // words before the block boundary
    logic                   cut;        // group truncated at/after this slot
    logic [$clog2(FETCH_WORDS+1)-1:0] ct_count;  // CTs needing shelf entries
    logic                   ct_redirect_pend;  // group leaves the seq path
    int                     primary_ct_slot;   // oldest CT: owns the BTB port
    logic                   primary_ct_found;

    always_comb begin : slot_prep
        avail = BLOCK_SIZE - int'(core_rsp_addr[BLOCK_OFFSET_BITS-1:0]);
        for (int w = 0; w < FETCH_WORDS; w++) begin
            slot_pc[w]    = {core_rsp_addr, 2'b00} + XLEN'(4 * w);
            slot_is_ct[w] = slot_ctrl[w].pc_source != PC_plus4;
        end
    end : slot_prep

    // Oldest CT of the group, found without reference to the BTB output
    // (no cut can precede the first CT, so position + clamp suffice).
    always_comb begin : primary_ct
        primary_ct_slot  = 0;
        primary_ct_found = 1'b0;
        for (int w = 0; w < FETCH_WORDS; w++) begin
            if (!primary_ct_found && core_rsp_data_valid &&
                (w < avail) && slot_is_ct[w]) begin
                primary_ct_slot  = w;
                primary_ct_found = 1'b1;
            end
        end
    end : primary_ct

    always_comb begin : group_formation
        cut              = 1'b0;
        group_has_ct     = 1'b0;
        ct_count         = '0;
        ct_redirect_pend = 1'b0;
        ct_resume_pc     = '0;
        for (int w = 0; w < FETCH_WORDS; w++) begin
            slot_valid[w]   = core_rsp_data_valid && !cut && (w < avail);
            slot_pred_pc[w] = slot_pc[w] + XLEN'(4);
            if (slot_valid[w] && slot_is_ct[w]) begin
                if (int'(ct_count) >= CT_PER_GROUP_MAX) begin
                    // Shelf capacity reached: end the group before this CT
                    // and refetch it as the oldest CT of the next group
                    // (same treatment as a younger JALR). Bounding the
                    // group by the shelf's *capacity* is what keeps the
                    // shelf_room stall satisfiable — a group demanding more
                    // entries than the shelf can ever hold would stall for
                    // ever. CT_PER_GROUP_MAX >= 1, so at least the oldest
                    // CT is always taken and the group is never empty.
                    slot_valid[w]    = 1'b0;
                    cut              = 1'b1;
                    ct_redirect_pend = 1'b1;
                    ct_resume_pc     = slot_pc[w];
                end else if (slot_ctrl[w].pc_source == PC_uncond) begin
                    // JAL: exact target; fetch ran past it, so always cut
                    slot_pred_pc[w]  = slot_pc[w] + slot_imm[w];
                    group_has_ct     = 1'b1;
                    ct_count        += 1'b1;
                    cut              = 1'b1;
                    ct_redirect_pend = 1'b1;
                    ct_resume_pc     = slot_pred_pc[w];
                end else if (!group_has_ct) begin
                    // oldest CT, branch/JALR: BTB prediction
                    slot_pred_pc[w] = btb_predicted_pc;
                    group_has_ct    = 1'b1;
                    ct_count       += 1'b1;
                    if (btb_predicted_pc != slot_pc[w] + XLEN'(4)) begin
                        cut              = 1'b1;  // predicted taken
                        ct_redirect_pend = 1'b1;
                        ct_resume_pc     = btb_predicted_pc;
                    end
                end else if (slot_ctrl[w].pc_source == PC_indirect) begin
                    // younger JALR: end the group before it
                    slot_valid[w]    = 1'b0;
                    cut              = 1'b1;
                    ct_redirect_pend = 1'b1;
                    ct_resume_pc     = slot_pc[w];
                end else begin
                    // younger conditional branch: static not-taken
                    group_has_ct = 1'b1;
                    ct_count    += 1'b1;
                end
            end
        end
    end : group_formation

    logic [$clog2(FETCH_WORDS+1)-1:0] group_count;
    always_comb begin
        group_count = '0;
        for (int w = 0; w < FETCH_WORDS; w++)
            group_count += slot_valid[w] ? 1'b1 : 1'b0;
    end

    /* =================================================================
     * Intake stall + issue fire
     *
     * The only legal issue stalls (Metaflow Arch p.64): DRIS full and,
     * in this design, too few free branch-shelf entries for the group's
     * CTs. A stall asserts core_req_stall_mem so the controller FIFO
     * holds the response until there's room.
     * ================================================================= */
    logic [DRIS_ID_WIDTH:0] occupancy;
    assign occupancy = fetch_ptr - retire_ptr;  // color-bit MSB makes this mod-2N

    logic dris_room, shelf_room, issue_fire;  // intake_stall declared above
    assign dris_room    = (DRIS_NUM_ENTRIES - int'(occupancy)) >= int'(group_count);
    assign shelf_room   = int'(shelf_free_count) >= int'(ct_count);
    assign intake_stall = core_rsp_data_valid && (!dris_room || !shelf_room);
    assign core_req_stall_mem = intake_stall;

    // Gate on mispredict/trap: entries written this cycle would be younger
    // than the flush point but invisible to the (registered) flush mask.
    assign issue_fire = core_rsp_data_valid && !intake_stall &&
                        !mispredict_valid && !trap_valid;

    /* =================================================================
     * Redirect at issue
     *
     * Fetch runs sequentially, so a redirect fires whenever the group
     * was cut before its natural end and execution resumes off the
     * sequential path (JAL target, predicted-taken BTB target, or a
     * younger JALR's own PC). ct_resume_pc comes from group formation.
     * ================================================================= */
    assign ct_redirect = issue_fire && ct_redirect_pend;
    assign redirect    = trap_valid | mispredict_valid | ct_redirect;

    always_comb begin : redirect_pc_mux
        if (trap_valid)            redirect_pc = trap_pc;
        else if (mispredict_valid) redirect_pc = mispredict_pc;
        else                       redirect_pc = ct_resume_pc;
    end : redirect_pc_mux

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
            dris_intake_pkts[w].pc_R           = slot_pc[w];
            dris_intake_pkts[w].rd_R           = slot_ctrl[w].rfWrite ? slot_rd[w]  : '0;
            dris_intake_pkts[w].rs1_R          = slot_ctrl[w].uses_rs1 ? slot_rs1[w] : '0;
            dris_intake_pkts[w].rs2_R          = slot_ctrl[w].uses_rs2 ? slot_rs2[w] : '0;
            dris_intake_pkts[w].ctrl_signals_R = slot_ctrl[w];
            dris_intake_pkts[w].imm_R          = slot_imm[w];
            `ifdef DEBUG
                dris_intake_pkts[w].debug_instr_R = core_rsp_data[w];
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
     * BTB: single read port (the group's oldest branch/JALR, keyed on
     * the slot's own PC) and single write port (the shelf's one resolve
     * per cycle). JALs are neither looked up nor written — their
     * targets come straight from decode. CTRL_SIGNALS_NOOP's PC_plus4
     * holds the internal write-enable off between training packets.
     * ================================================================= */
    ctrl_signals_t btb_write_ctrl;
    assign btb_write_ctrl = btb_train.valid ? btb_train.ctrl_signals
                                            : CTRL_SIGNALS_NOOP;

    BTBPredictor btb (
        .clk                       (clock),
        .rst_l                     (reset_n),
        .pc_F1                     (slot_pc[primary_ct_slot]),
        .npc_plus4_F1              (slot_pc[primary_ct_slot] + XLEN'(4)),
        .predicted_next_pc         (btb_predicted_pc),
        .read_btb_hist             (btb_read_hist),
        .taken_branch              (),
        .btb_hit                   (),
        .bcond_write               (btb_train.taken),
        .ctrl_signals_write        (btb_write_ctrl),
        .correct_branch_prediction (btb_train.correct),
        .pc_write                  (btb_train.pc),
        .npc_offset_write          (btb_train.next_pc),
        .write_btb_hist            (btb_train.hist)
    );

    /* =================================================================
     * Branch shelf intake: one packet per valid CT slot. intake_stall
     * guarantees enough free shelf entries for all of them.
     * ================================================================= */
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
        .flush_mask         (flush_mask)
    );


    // TODO: core_rsp_excpt -> instruction-fetch fault (trap plumbing).

endmodule : InstructionIssueUnit

/**
 * BranchShelf
 *
 * Holds in-flight speculative conditional branches including JALR.
   The shelf keeps track of every pc modifing instruction's predicted
   and correct PC. Correct PCs are calculated by the main execution unit, so
   the shelf does not keep track of lockers. Instead, it snoops the update bus
   for the branch's DRIS ID; when it sees a match, it captures the update's
   next_pc_W as the correct PC and marks that it has the correct PC.
    On a mispredict, the shelf produces a flush mask covering every
 * DRIS entry younger than the offending branch and signals fetch to redirect.
 *
 * The shelf never writes the DRIS: JAL/JALR link values ride the exec
 * way's result_data_W, and the exec writeback marks the branch executed.
 *
 * RISC-V deviation from Lightning/SPARC: no condition codes. Branches lock
 * on rs1/rs2 in the DRIS and dispatch like any other instruction, so the
 * patent's CC-locker mechanism disappears — the shelf watches only for
 * the branch's own completion, never its dependencies.
**/
module BranchShelf #(
    parameter int NUM_SHELF_ENTRIES = 8,
    parameter int NUM_UPDATE_PORTS  = DRIS_defs::EXECUTE_WAYS,
    parameter int FETCH_WAYS        = DRIS_defs::FETCH_WAYS
)(
    input  logic                                clock, reset_n,

    input dris_entry_t dris_entries [DRIS_NUM_ENTRIES-1:0],

    /* ============================================================
     * Shelving interface
     * ============================================================ */
    input  shelf_intake_pkt_t                   [FETCH_WAYS-1:0] shelf_in_pkt,
    output logic                                [FETCH_WAYS-1:0] shelf_alloc_valid,
    output logic [$clog2(NUM_SHELF_ENTRIES+1)-1:0] shelf_free_count,

    /* ============================================================
     * BTB training: the one resolving entry per cycle
     * ============================================================ */
    output btb_train_pkt_t                      btb_train,

    /* ============================================================
     * Update bus snoop
     *
     * Each cycle, for every shelf entry waiting on a locker, compare
     * locker_id against every update_bus[i].id_W. On a match, mark the
     * locker as clear and capture update_bus[i].result_data_W into the
     * appropriate operand slot.
     * ============================================================ */
    input  dris_writeback_pkt_t                 update_bus [NUM_UPDATE_PORTS-1:0],

    /* ============================================================
     * Global flush (from SSC on trap retirement)
     *
     * Wipes the whole shelf because every DRIS entry the shelf was
     * tracking has been purged.
     * ============================================================ */
    input  logic                                global_flush,

    /* ============================================================
     * Mispredict output -> fetch redirect
     * ============================================================ */
    output logic                                mispredict_valid,
    output logic [XLEN-1:0]                     mispredict_pc,
    output dris_id_t                            mispredict_branch_id,

    /* ============================================================
     * SSC interface
     * ============================================================ */
    output dris_id_t                            oldest_branch_id,
    output logic                                branch_fence_valid,
    output logic [DRIS_NUM_ENTRIES-1:0]         flush_mask
);

    /* =================================================================
     * Per-entry data structure
     *
     * Mirrors the patent's branch shelf entry (col. 13-14) but adapted
     * for RISC-V (no CC locker; rs1/rs2 lockers instead).
     * ================================================================= */
    typedef enum logic [1:0] {
        EMPTY = 2'b00,
        UNDET = 2'b01,    // waiting on operands
        OK    = 2'b10,    // resolved, prediction was correct
        WRONG = 2'b11     // resolved, prediction was wrong
    } shelf_status_t;

    typedef struct packed {
        shelf_status_t        status;
        dris_id_t             branch_id;        // index into DRIS for flush mask + retire
        logic [XLEN-1:0]      branch_pc;        // branch's own PC (for restart on mispredict)

        logic [XLEN-1:0]      predicted_pc;
        logic [XLEN-1:0]      correct_pc;
        logic correct_pc_valid;
        logic [1:0]           btb_hist;         // counter bits read at predict time

        ctrl_signals_t         ctrl_signals;     // pc_source gates BTB training
    } shelf_entry_t;

    shelf_entry_t shelf [NUM_SHELF_ENTRIES-1:0];
    shelf_entry_t next_shelf [NUM_SHELF_ENTRIES-1:0];

    /* =================================================================
     * Internal signals
     * ================================================================= */
    logic [NUM_SHELF_ENTRIES-1:0] entry_empty;
    logic [NUM_SHELF_ENTRIES-1:0] entry_undet;
    logic [NUM_SHELF_ENTRIES-1:0] entry_wrong;
    logic [NUM_SHELF_ENTRIES-1:0] entry_ok;
    logic [NUM_SHELF_ENTRIES-1:0] entry_ready_to_resolve;  // both lockers clear, status==UNDET

    logic [$clog2(NUM_SHELF_ENTRIES)-1:0] alloc_slot [FETCH_WAYS-1:0];      // where new entries go
    logic [$clog2(NUM_SHELF_ENTRIES)-1:0] resolve_slot;    // which entry we evaluate this cycle
    logic [$clog2(NUM_SHELF_ENTRIES)-1:0] oldest_wrong_slot;
    logic [$clog2(NUM_SHELF_ENTRIES)-1:0] oldest_undet_slot;
    int unsigned                          alloc_write_slot; // next_shelf index during allocation
    logic                                 ok_retire_safe;   // no older UNDET/WRONG blocks this OK entry

    /* =================================================================
     * Status decode
     * ================================================================= */
    always_comb begin
        for (int i = 0; i < NUM_SHELF_ENTRIES; i++) begin
            entry_empty[i] = (shelf[i].status == EMPTY);
            entry_undet[i] = (shelf[i].status == UNDET);
            entry_wrong[i] = (shelf[i].status == WRONG);
            entry_ok[i]    = (shelf[i].status == OK);
            entry_ready_to_resolve[i] = entry_undet[i] && shelf[i].correct_pc_valid;
        end
    end

    /* =================================================================
     * Allocate slot for incoming branches
     * ================================================================= */
    // Claim only for valid packets, so a sparse packet vector (CTs sit at
    // their slot index) can't strand a younger CT behind empty claims.
    logic [NUM_SHELF_ENTRIES-1:0] entry_claimed;
    always_comb begin
        entry_claimed = '0;
        for (int i = 0; i < FETCH_WAYS; i++) begin
            alloc_slot[i] = '0;
            shelf_alloc_valid[i] = 1'b0;
            if (shelf_in_pkt[i].valid) begin
                for (int j = 0; j < NUM_SHELF_ENTRIES; j++) begin
                    if (entry_empty[j] & ~entry_claimed[j]) begin
                        alloc_slot[i] = j;
                        shelf_alloc_valid[i] = 1'b1;
                        entry_claimed[j] = 1'b1;
                        break;
                    end
                end
            end
        end
    end

    always_comb begin
        shelf_free_count = '0;
        for (int i = 0; i < NUM_SHELF_ENTRIES; i++)
            shelf_free_count += entry_empty[i] ? 1'b1 : 1'b0;
    end

    /* =================================================================
     * Pick the oldest entry to resolve this cycle
     * ================================================================= */
    logic entry_resolve_valid;
    always_comb begin
        resolve_slot = '0;
        entry_resolve_valid = 1'b0;
        for (int i = 0; i < NUM_SHELF_ENTRIES; i++) begin
            if (entry_ready_to_resolve[i] & ~entry_resolve_valid) begin
                resolve_slot = i;
                entry_resolve_valid = 1'b1;
            end else if (entry_ready_to_resolve[i] & entry_resolve_valid) begin
                if (is_older(shelf[i].branch_id, shelf[resolve_slot].branch_id)) begin
                    resolve_slot = i;
                end
            end
        end
    end

    /* =================================================================
     * Find oldest WRONG entry -> drives mispredict redirect + flush mask
     *
     * On a mispredict, the oldest WRONG entry's branch_id defines the
     * cut. Anything younger gets flushed. The shelf itself also drops
     * everything younger than that ID.
     * ================================================================= */
    logic entry_wrong_valid;
    always_comb begin
        oldest_wrong_slot = '0;
        entry_wrong_valid = 1'b0;
        for (int i = 0; i < NUM_SHELF_ENTRIES; i++) begin
            if (entry_wrong[i] & ~entry_wrong_valid) begin
                oldest_wrong_slot = i;
                entry_wrong_valid = 1'b1;
            end else if (entry_wrong[i] & entry_wrong_valid) begin
                if (is_older(shelf[i].branch_id, shelf[oldest_wrong_slot].branch_id)) begin
                    oldest_wrong_slot = i;
                end
             end
        end
    end

    /* =================================================================
     * Find oldest UNDET entry -> branch fence for SSC
     *
     * Per DRIS patent ("supplies the Retire process with the ID of the
     * oldest speculative branch to prevent retiring that branch").
     * The SSC must not retire past this branch until it resolves.
     * ================================================================= */
    always_comb begin
        oldest_undet_slot   = '0;
        oldest_branch_id    = '0;
        branch_fence_valid  = 1'b0;
        for (int i = 0; i < NUM_SHELF_ENTRIES; i++) begin
            if (entry_undet[i] & ~branch_fence_valid) begin
                oldest_undet_slot = i;
                oldest_branch_id = shelf[i].branch_id;
                branch_fence_valid = 1'b1;
            end else if (entry_undet[i] & branch_fence_valid) begin
                if (is_older(shelf[i].branch_id, oldest_branch_id)) begin
                    oldest_undet_slot = i;
                    oldest_branch_id = shelf[i].branch_id;
                end
             end
        end
    end

    /* =================================================================
     * Mispredict output
     *
     * If there's a WRONG entry, broadcast its restart PC to fetch.
     * - cond branch: restart = was-it-actually-taken ? target_pc : fallthrough_pc
     *                (we predicted the opposite, so the correct PC is
     *                the OTHER direction)
     * - JAL: should never mispredict if BTB caches the target correctly
     * - JALR: mispredict on target mismatch; restart at the computed target
     * ================================================================= */
    always_comb begin
        mispredict_valid     = |entry_wrong;
        mispredict_branch_id = shelf[oldest_wrong_slot].branch_id;
        mispredict_pc        = shelf[oldest_wrong_slot].correct_pc;
    end

    /* =================================================================
     * Flush mask
     *
     * One bit per DRIS entry. Set every bit whose DRIS ID is younger than
     * mispredict_branch_id. The DRIS / SSC consumes this to invalidate
     * wrong-path instructions.
     * ================================================================= */
    always_comb begin
        flush_mask = '0;
        if (mispredict_valid) begin
            for (int i = 0; i < DRIS_NUM_ENTRIES; i++) begin
                if (is_older(mispredict_branch_id, dris_entries[i].id)) begin
                    flush_mask[i] = 1'b1;
                end
            end
        end
    end

    /* =================================================================
     * BTB training: the resolving entry, branches and JALRs only (JAL
     * targets come from decode; don't burn BTB capacity on them).
     * "Taken" is derived at resolve: the computed next PC differs from
     * fall-through. A not-taken resolve stores pc+4 in the target field
     * (the write is atomic); a later taken-history hit then predicts
     * fall-through and repairs — worse prediction, never wrong-path.
     * ================================================================= */
    always_comb begin : btb_training
        btb_train = '0;
        if (entry_resolve_valid &&
            (shelf[resolve_slot].ctrl_signals.pc_source == PC_cond ||
             shelf[resolve_slot].ctrl_signals.pc_source == PC_indirect)) begin
            btb_train.valid        = 1'b1;
            btb_train.pc           = shelf[resolve_slot].branch_pc;
            btb_train.next_pc      = shelf[resolve_slot].correct_pc;
            btb_train.taken        = shelf[resolve_slot].correct_pc !=
                                     (shelf[resolve_slot].branch_pc + XLEN'(4));
            btb_train.correct      = shelf[resolve_slot].correct_pc ==
                                     shelf[resolve_slot].predicted_pc;
            btb_train.hist         = shelf[resolve_slot].btb_hist;
            btb_train.ctrl_signals = shelf[resolve_slot].ctrl_signals;
        end
    end : btb_training

    
    /* ---- (1) Update-bus snoop ------------------------------------
     * For every UNDET entry, check each update_bus port for the
     * branch's OWN DRIS ID (completion-watching, not dependency
     * tracking). On a match, capture the computed next PC.
     * -------------------------------------------------------------- */
    always_comb begin
        next_shelf = shelf;
        // Defaults for the block-local temporaries below; without these an
        // (unintended) latch is inferred, which VCS tolerated silently.
        alloc_write_slot = '0;
        ok_retire_safe   = 1'b0;

        for (int i = 0; i < NUM_SHELF_ENTRIES; i++) begin: update_snoop
            if (entry_undet[i]) begin
                for (int k = 0; k < NUM_UPDATE_PORTS; k++) begin
                    if (update_bus[k].valid_W &&
                    update_bus[k].id_W == shelf[i].branch_id) begin
                        next_shelf[i].correct_pc = update_bus[k].next_pc_W;  // capture the PC for potential mispredict redirect
                        next_shelf[i].correct_pc_valid = 1'b1;  // mark that we have the correct PC and can resolve this entry

                    end
                end
            end
        end: update_snoop

    /* ---- (2) Resolve the picked entry ----------------------------
     * resolve_slot/entry_resolve_valid come from the earlier block.
     * Lockers come from the registered shelf, so an entry that just
     * had its lockers cleared by (1) above resolves next cycle, not
     * this one. That's the intended 1-cycle latency.
     *
     * For unconditional branches (JAL/JALR), the resolution amounts
     * to "did the BTB predict correctly?" — for JAL the target is
     * known at decode so the BTB should be right; for JALR we'd
     * compare rs1+imm against predicted_pc. JALR needs imm in the
     * entry to do this fully, which it doesn't currently have, so
     * for now we mark unconditional branches OK on resolution and
     * leave JALR mispredict detection as a TODO.
     * -------------------------------------------------------------- */
    if (entry_resolve_valid) begin
            next_shelf[resolve_slot].status =
            (shelf[resolve_slot].correct_pc == shelf[resolve_slot].predicted_pc) ?
            OK : WRONG;
        end

    /* ---- (3) Mispredict flush -------------------------------------
     * Clear the oldest WRONG entry and every entry younger than it.
     * This fires every cycle a WRONG entry exists — by the next clock
     * edge it's EMPTY so mispredict_valid drops naturally.
     * -------------------------------------------------------------- */
    if (entry_wrong_valid) begin
        for (int i = 0; i < NUM_SHELF_ENTRIES; i++) begin
            if (i == oldest_wrong_slot) begin
                next_shelf[i].status = EMPTY;
            end
            else if (shelf[i].status != EMPTY &&
                     is_older(shelf[oldest_wrong_slot].branch_id, shelf[i].branch_id)) begin
                next_shelf[i].status = EMPTY;
            end
        end
    end

    /* ---- (4) Retire OK entries ------------------------------------
     * An OK entry is safe to leave when no older entry is UNDET or
     * WRONG (an older WRONG would flush us anyway via step 3; an
     * older UNDET might still go WRONG). Multiple OK entries can
     * retire in the same cycle.
     * -------------------------------------------------------------- */
    for (int i = 0; i < NUM_SHELF_ENTRIES; i++) begin
        if (entry_ok[i]) begin
            ok_retire_safe = 1'b1;
            for (int j = 0; j < NUM_SHELF_ENTRIES; j++) begin
                if ((entry_undet[j] || entry_wrong[j]) &&
                    is_older(shelf[j].branch_id, shelf[i].branch_id)) begin
                    ok_retire_safe = 1'b0;
                end
            end
            if (ok_retire_safe) next_shelf[i].status = EMPTY;
        end
    end

    /* ---- (5) Allocate incoming branches ---------------------------
     * For each valid incoming branch, drop it into alloc_slot[i]
     * (computed in the separate block above). Populate ALL fields,
     * not just status/branch_id/pc/predicted_pc.
     *
     * Note: alloc_slot[i] is computed from the registered entry_empty,
     * so a slot just freed in step (3) or (4) won't be available
     * until next cycle. Acceptable for now.
     * -------------------------------------------------------------- */
    for (int i = 0; i < FETCH_WAYS; i++) begin
        if (shelf_in_pkt[i].valid && shelf_alloc_valid[i]) begin
            alloc_write_slot = alloc_slot[i];
            next_shelf[alloc_write_slot].status           = UNDET;
            next_shelf[alloc_write_slot].branch_id        = shelf_in_pkt[i].id;
            next_shelf[alloc_write_slot].branch_pc        = shelf_in_pkt[i].pc;
            next_shelf[alloc_write_slot].predicted_pc     = shelf_in_pkt[i].predicted_pc;
            next_shelf[alloc_write_slot].correct_pc       = '0;
            next_shelf[alloc_write_slot].correct_pc_valid = 1'b0;
            next_shelf[alloc_write_slot].btb_hist         = shelf_in_pkt[i].btb_hist;
            next_shelf[alloc_write_slot].ctrl_signals     = shelf_in_pkt[i].ctrl_signals;
        end
    end

    /* ---- (6) Global flush -----------------------------------------
     * Override everything else: wipe the whole shelf.
     * -------------------------------------------------------------- */
    if (global_flush) begin
        for (int i = 0; i < NUM_SHELF_ENTRIES; i++) begin
            next_shelf[i].status = EMPTY;
        end
    end
end

    /* =================================================================
     * State register
     * ================================================================= */
    always_ff @(posedge clock or negedge reset_n) begin
        if (~reset_n) begin
            for (int i = 0; i < NUM_SHELF_ENTRIES; i++) begin
                shelf[i] <= '0;  // status field is EMPTY = 0
            end
        end
        else begin
            shelf <= next_shelf;
        end
    end

endmodule : BranchShelf

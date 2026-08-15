import DRIS_defs::*;
import RISCV_ISA::*;
import RISCV_UArch::*;  // Import microarchitecture parameters and definitions
import internal_defines_pkg::*;     // Control signals struct, ALU ops

`include "parameters.vh"
`include "memory_segments.vh"
`include "riscv_abi.vh"

`default_nettype none

// shelf_intake_pkt_t and btb_train_pkt_t moved to the DRIS_defs package
// (rtl/ooo/1DRIS_defs.sv) so BranchShelf.sv, which compiles first, can see
// them in its port list.

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
 *   - core_req_cancel drops in-flight probes and queued responses, and is
 *     raised *only* on a mispredict repair. A CT cut or a trap redirects
 *     the PC without touching the cache; the F-queue below tracks the
 *     outstanding requests and squashes those wrong-path responses when
 *     they arrive, so a redirect no longer throws away a cache line.
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
    output logic                      perf_intake_stall,
    output logic                      perf_stall_dris_full,
    output logic                      perf_stall_shelf_full,
    // A fetch group was accepted into the DRIS this cycle.
    output logic                      perf_issue_fire
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
    /* Cancel on a mispredict only — never on a CT cut or a trap.
     *
     * This used to be `redirect`, which includes ct_redirect: a cut fires on
     * every JAL and every predicted-taken branch, i.e. on *correctly*
     * predicted control flow, so fibi raised 5,826 cancels against 793
     * mispredicts. Because the controller chains a new probe out of every
     * response cycle, the redirect a group produces lands exactly on the
     * cycle the next probe's miss resolves, and the cancel override
     * (cache_controller2.sv:363-370) clears mem_bus_request in the same
     * block that a read_miss sets it. The fill was therefore never even
     * requested: 858 I$ misses, 19 fill requests, and one block behind a
     * backward branch (main+0x50) probed 841 times and never installed.
     * 839 of the 858 died this way. See docs/perf-counters.md §4.1a.
     *
     * A mispredict is rare (793 vs 5,826) and is genuinely wrong-path work,
     * so cancelling there keeps the bandwidth saving without the pathology.
     * Everything else redirects the PC and lets the wrong-path responses
     * arrive, where the F-queue below drops them.
     *
     * Note this is *not* free of the same cost in miniature: a mispredict
     * cancel still abandons an in-flight fill (7 of fibi's 858). Tying this
     * to 1'b0 would recover those too, at the price of waiting out a
     * wrong-path fill — cheap only because tb/main_memory.sv is
     * combinational. Revisit if main memory ever gets a delay model. */
    assign core_req_cancel = mispredict_valid;

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
     * F-queue — outstanding fetch requests (F1/F2)
     *
     * The core tracks what it has asked the I-side controller for, so a
     * redirect can squash wrong-path *responses on arrival* instead of
     * killing the request at the source. Without this, dropping
     * ct_redirect from core_req_cancel is not merely a perf change — it is
     * wrong: the sequential fetches past a predicted-taken branch would
     * still arrive at the FIFO head, and slot_valid (which keys off
     * core_rsp_data_valid alone) would write them into the DRIS as
     * architectural instructions.
     *
     * Two entries, because at most two requests are outstanding: accept at
     * cycle N -> the probe resolves and enqueues at N+1 -> the response is
     * visible at the (registered) FIFO head at N+2. f1 is the younger entry
     * (just accepted, probing); f2 is the older, whose response arrives
     * next. This mirrors the controller's own 2-deep response FIFO.
     *
     * It rests on: every accepted I-side request produces exactly one
     * response, in order. core_req_we is tied low on this side, so every
     * accepted request walks IDLE -> READ_CACHE_RSP -> (hit | fill) and
     * enqueues exactly once. A cancel is the sole exception, and it voids
     * *all* of them at once (see below). The assertions are what hold that
     * invariant honest — a tracking desync silently drops instructions,
     * which is the failure mode that already cost this repo memtest2's
     * 0x4000a0-0x4000ac (see the core_req_re comment above).
     *
     * f2.addr is read only by assertion 1: slot_pc, avail and the CT cut
     * all derive from core_rsp_addr and must keep doing so.
     *
     * Two bits per entry, not one. `busy` is occupancy — a response is
     * still owed for this request — and `good` is whether it is still on
     * the fetch path. A CT cut or trap clears `good` and leaves `busy`
     * alone, because nothing cancelled the cache and the wrong-path
     * response is still coming; the queue has to be there to receive it.
     * Folding the two into a single valid bit drops occupancy on the
     * redirect, and the next wrong-path response then arrives untracked.
     * ================================================================= */
    typedef struct packed {
        logic                    busy;   // a response is still owed
        logic                    good;   // ...and it is on the current path
        logic [ADDRESS_SIZE-1:0] addr;
    } fetch_track_t;

    fetch_track_t f1, f2, f1_n, f2_n;

    // The two enables, and they move independently — that is the whole
    // point. cache_controller2 chains a new probe out of READ_CACHE_RSP and
    // READ_WAIT_MEM_RSP, so accept and consume do not travel together the
    // way the in-order core's fixed F1/F2/F3 shift register assumes:
    //   hit at N, chained probe misses at N+1 : consume, no accept
    //   fill completes (do_forward + ready=1) : accept, no consume
    //   intake stalled                        : neither
    //   steady-state hits                     : both
    //
    // core_rsp_ready is *not* suppressed by the cancel override in
    // FSM_outputs (cache_issue_read is), so the !core_req_cancel term is
    // load-bearing: without it a cancel cycle would record a request the
    // controller never took.
    logic accept, consume;
    assign accept  = core_req_re && core_rsp_ready && !core_req_cancel;
    // The FIFO's actual dequeue condition: num_deq is hardwired to 1 and
    // peek_only is core_req_stall_mem (= intake_stall), so the head pops
    // every cycle it is valid and intake is not stalling.
    assign consume = core_rsp_data_valid && !intake_stall;

    logic ftrack_overrun;   // accept into an already-occupied F1 (assertion 2)

    always_comb begin : fetch_track_next
        f1_n = f1;
        f2_n = f2;

        // F2 frees when the response it was owed is taken.
        if (consume) f2_n = '0;

        // F1 slides into a free F2.
        if (!f2_n.busy) begin
            f2_n = f1;
            f1_n = '0;
        end

        // Nothing may land on top of a request that has not slid out yet;
        // core_req_re = !intake_stall and peek_only = intake_stall suppress
        // accept and consume together, which is what makes this impossible.
        ftrack_overrun = accept && f1_n.busy;

        // A newly accepted request lands in F1.
        if (accept) f1_n = '{busy: 1'b1, good: 1'b1, addr: core_req_addr};

        // A redirect marks everything in flight wrong-path — including the
        // request accepted THIS cycle, since pc_F is still on the sequential
        // path in the cycle the redirect is computed, so this has to come
        // after the accept above. `busy` is untouched: those responses are
        // still on their way and still have to be consumed.
        if (redirect) begin
            f1_n.good = 1'b0;
            f2_n.good = 1'b0;
        end

        // ...unless this redirect is the one that cancels. The cancel
        // flushes the controller's response FIFO wholesale
        // (cache_controller2.sv:504), forces next_state to IDLE (:251) and
        // suppresses the enqueue strobes (:370), so every outstanding
        // request is voided and no response is owed for any of them. Clear
        // occupancy, not just the path bit — leaving `busy` set here would
        // strand the queue full and trip assertion 2 on the refetch.
        // Ordering: cancel implies redirect, so this must come last.
        if (core_req_cancel) begin
            f1_n = '0;
            f2_n = '0;
        end
    end : fetch_track_next

    always_ff @(posedge clock, negedge reset_n) begin : fetch_track
        if (!reset_n) begin
            f1 <= '0;
            f2 <= '0;
        end
        else begin
            f1 <= f1_n;
            f2 <= f2_n;
        end
    end : fetch_track

    // synopsys translate_off
    // Fatal, not $error: a desync means a GOOD group is about to be dropped
    // while pc_F has already run past it. That must crash the run, not show
    // up as a register mismatch dozens of instructions later.
    // The `$time > 0` guard is not decoration: the testbench's clk starts at
    // 1, so its initialization counts as a posedge at time 0 in a 4-state
    // simulator, and reset_n is still high there (it only pulses low at t=1).
    // Everything below is X on that edge. The repo's other assertions only
    // $display and survive it; these are $fatal and would not.
    always_ff @(posedge clock) begin : fetch_track_assertions
        if ((reset_n === 1'b1) && ($time > 0)) begin
            // 1. The model matches reality. Once the invariant above holds
            //    this is tautological — so if it fires, the model is broken.
            assert (!(core_rsp_data_valid && f2.busy) ||
                    (core_rsp_addr == f2.addr))
            else $fatal(1, "%0t %m: fetch tracking desync - rsp=%h f2=%h",
                        $time, {core_rsp_addr, 2'b00}, {f2.addr, 2'b00});

            // 2. Never accept into an occupied F1 (would lose a request).
            assert (!ftrack_overrun)
            else $fatal(1, "%0t %m: accepted a request with the F-queue full",
                        $time);

            // 3. A response with nothing outstanding. Also the check that
            //    the cancel really does void every outstanding request: if
            //    the FIFO flush ever left one behind, it lands here.
            assert (!(core_rsp_data_valid && !f1.busy && !f2.busy))
            else $fatal(1, "%0t %m: response with an empty F-queue", $time);
        end
    end : fetch_track_assertions
    // synopsys translate_on

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
    /* f2.good here as well as in issue_fire: a squashed group needs neither
     * a DRIS entry nor a shelf entry, so it must not be held at the FIFO
     * head when those are full. Without this term a stale wrong-path head
     * blocks the redirect target's fetch until retirement drains the DRIS —
     * not a deadlock (retirement is independent of fetch), but wasted
     * cycles for nothing. */
    assign intake_stall = core_rsp_data_valid && f2.good &&
                          (!dris_room || !shelf_room);
    assign core_req_stall_mem = intake_stall;

    /* f2.good is the wrong-path squash: a CT cut or a trap no longer
     * cancels the cache, so a response whose request they invalidated still
     * arrives, and this is where it dies. It is consumed (see `consume`
     * above) and dropped — no DRIS write, no shelf entry, no fetch_ptr
     * advance, and ct_redirect inherits the gate for free, so a squashed
     * group cannot redirect anything either.
     *
     * The mispredict/trap terms stay: f2.good is registered and cannot see
     * a redirect raised this cycle, and entries written this cycle would be
     * younger than the flush point but invisible to the (registered) flush
     * mask. The combinational gate covers this cycle, the valid bit covers
     * every cycle after. */
    assign issue_fire = core_rsp_data_valid && f2.good && !intake_stall &&
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
        .flush_mask         (flush_mask),
        .perf_resolve_valid (perf_branch_resolved),
        .perf_resolve_wrong (perf_branch_mispredicted),
        .perf_resolve_wrong_squashed (perf_branch_mispredict_squashed)
    );

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
    assign perf_intake_stall     = intake_stall;
    assign perf_stall_dris_full  = core_rsp_data_valid && f2.good && !dris_room;
    assign perf_stall_shelf_full = core_rsp_data_valid && f2.good && !shelf_room;
    assign perf_issue_fire       = issue_fire;

    // TODO: core_rsp_excpt -> instruction-fetch fault (trap plumbing).

endmodule : InstructionIssueUnit
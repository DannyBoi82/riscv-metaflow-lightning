import DRIS_defs::*;
import RISCV_ISA::*;
import RISCV_UArch::*;  // Import microarchitecture parameters and definitions
import internal_defines_pkg::*;     // Control signals struct, ALU ops

`include "parameters.vh"
`include "memory_segments.vh"
`include "riscv_abi.vh"

`default_nettype none

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
    output logic [DRIS_NUM_ENTRIES-1:0]         flush_mask,

    /* ============================================================
     * Performance-counter observation (always present, so the port
     * list has the same shape in PERF and non-PERF builds; only the
     * counters that consume these are `ifdef'd, up in LightningCore).
     * Pure observation — nothing here feeds back into the shelf.
     *
     * A resolution is the cycle an UNDET entry's status is decided
     * (step 2 below), which is one per cycle at most; perf_resolve_wrong
     * is that same event when the prediction missed. The mispredict
     * *pulse* it eventually produces is one cycle later and is counted
     * separately in the core.
     *
     * The two do not have to be equal, which is why the third signal
     * exists: steps (3) and (6) can overwrite a just-written WRONG
     * status before anyone sees it, when an *older* branch mispredicts
     * in the same cycle (or a trap wipes the shelf). Such a branch was
     * genuinely mispredicted but is itself wrong-path, so it never gets
     * its own redirect. perf_resolve_wrong_squashed counts exactly those,
     * making the two counts reconcile.
     * ============================================================ */
    output logic                                perf_resolve_valid,
    output logic                                perf_resolve_wrong,
    output logic                                perf_resolve_wrong_squashed
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

    /* =================================================================
     * Perf observation: the resolve event and its verdict. Same
     * condition and same comparison step (2) uses to write the status,
     * kept next to the training block so the two can't drift.
     * ================================================================= */
    assign perf_resolve_valid = entry_resolve_valid;
    assign perf_resolve_wrong = entry_resolve_valid &&
                                (shelf[resolve_slot].correct_pc !=
                                 shelf[resolve_slot].predicted_pc);

    /* Read back the *final* next_shelf, after steps (3)-(6) have had their
     * say: if the WRONG this cycle wrote isn't there any more, an older
     * mispredict's flush (3) or a trap wipe (6) overwrote it, and this
     * branch never gets to redirect. resolve_slot can only be an entry that
     * was UNDET in the registered shelf, so allocation (5) and the OK retire
     * (4) can't be the ones that changed it. */
    assign perf_resolve_wrong_squashed = perf_resolve_wrong &&
                                         (next_shelf[resolve_slot].status != WRONG);

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

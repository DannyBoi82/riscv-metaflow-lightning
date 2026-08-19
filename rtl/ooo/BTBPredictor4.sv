/*--------------------------------------------------------------------------*
 * BTBPredictor4 — 4-wide banked BTB for the OoO front end                    *
 *--------------------------------------------------------------------------*/

/**
 * Four-way banked version of `BTBPredictor` (rtl/core/lib.sv).
 *
 * The in-order core's BTB looks up one PC per cycle. The OoO front end
 * fetches a group of up to FETCH_WORDS consecutive words, so every slot in
 * the group needs its own lookup — otherwise only the oldest control
 * transfer gets a real prediction and every younger branch is shelved with a
 * hardcoded pc+4.
 *
 * This is a *partition*, not a replication. The group's addresses are
 * consecutive words that never leave a cache block, so their pc[3:2] values
 * are distinct by construction:
 *
 *     bank b holds exactly the entries whose pc[3:2] == b
 *     row    r = pc[ROW_BITS+3:4]        all banks read the SAME row
 *     write: one resolved branch per cycle -> we[b] = (pc_write[3:2] == b)
 *
 * Four simultaneous lookups, conflict-free by structure, for the same total
 * entry count and the same total bits as the single-banked version
 * (BTB_NUM_WORDS entries of BTB_WORD_WIDTH, reshaped from 128x62 into four
 * 32x62 banks). Aliasing behaviour is unchanged: the tag is the full word
 * address, so a hit is exact.
 *
 * Ordering / rotation
 * -------------------
 * `block_pc` is in *fetch order*: block_pc[0] is the word being requested
 * this cycle and block_pc[w] is block_pc[0] + 4w. Bank index, however, is in
 * *block-word order*. When the group starts unaligned the two disagree, so
 * the bank outputs are rotated by `start = block_pc[0][3:2]`:
 *
 *     slot w reads bank (start + w) mod FETCH_WORDS
 *
 * All outputs (`predicted_pc_block`, `read_btb_hist`, `taken_branch`,
 * `btb_hit`) are in the same fetch order as `block_pc`.
 *
 * Slots past the end of the block (start + w >= FETCH_WORDS) would need row
 * r+1, which the common row index cannot supply. They are forced to miss via
 * `in_group` — the full-address tag compare would reject them anyway, but the
 * mask makes the intent explicit and keeps `best_prediction` honest if the
 * tag is ever narrowed. Those slots are outside the fetch group and are
 * dropped by the consumer's slot_valid mask regardless.
 *
 * Read port:  combinational (sram_1r_1w reads asynchronously), so the
 *             prediction for the PC presented this cycle is available this
 *             cycle and can feed next_pc directly.
 * Write port: one per bank, synchronous, driven by the branch shelf's single
 *             resolve per cycle. Conditional branches, JAL and JALR all
 *             train; CTRL_SIGNALS_NOOP's PC_plus4 holds the write enable off
 *             between training packets.
 **/

import RISCV_ISA::*;
import RISCV_UArch::*;
import internal_defines_pkg::*;

`default_nettype none

module BTBPredictor4 #(
    parameter int FETCH_WORDS = DRIS_defs::FETCH_WAYS,
    // Total entries across all banks, so this matches the single-banked BTB's
    // budget knob directly.
    parameter int NUM_ENTRIES = RISCV_UArch::BTB_NUM_WORDS,
    parameter int WORD_WIDTH  = RISCV_UArch::BTB_WORD_WIDTH
) (
    input   logic              clk, rst_l,

    /* ============================================================
     * Read port: one lookup per slot of the fetch group.
     * ============================================================ */
    // Word addresses, fetch order: block_pc[w] == block_pc[0] + 4w.
    input   logic [XLEN-1:2]   block_pc           [FETCH_WORDS-1:0],

    // Per-slot next-PC prediction (word address). Target on a
    // hit-and-predict-taken, else the slot's own pc+4.
    output  logic [XLEN-1:2]   predicted_pc_block [FETCH_WORDS-1:0],

    // The address to fetch next: the target of the oldest slot that hits and
    // predicts taken, or the first word of the next block if none does.
    // Full PC — this drives the PC register / I$ request.
    output  logic [XLEN-1:0]   best_prediction,

    // Counter bits captured at predict time, per slot, for shelf training.
    // Zero on a miss: the stored bits belong to a different address, so a
    // missing slot trains from a cold counter.
    output  logic [1:0]        read_btb_hist      [FETCH_WORDS-1:0],

    // Per-slot predicted-taken and tag-hit. `btb_hit` separates "no entry"
    // from "entry says not-taken", which the single-ported version could not
    // express. The oldest slot with taken_branch set is also the group's cut
    // point.
    output  logic [FETCH_WORDS-1:0] taken_branch,
    output  logic [FETCH_WORDS-1:0] btb_hit,

    /* ============================================================
     * Write port: the branch shelf resolves one branch per cycle, so a
     * single write decoded into one bank is sufficient.
     * ============================================================ */
    input   logic              bcond_write,
    input   ctrl_signals_t     ctrl_signals_write,
    // Carried for interface parity with BTBPredictor; the counter update is
    // driven by the resolved direction, not by whether we guessed right.
    input   logic              correct_branch_prediction,
    input   logic [XLEN-1:0]   pc_write,
    input   logic [XLEN-1:0]   npc_offset_write,
    input   logic [1:0]        write_btb_hist
);

    localparam int BANKS     = FETCH_WORDS;
    localparam int BANK_BITS = $clog2(BANKS);
    localparam int ROWS      = NUM_ENTRIES / BANKS;
    localparam int ROW_BITS  = $clog2(ROWS);

    // Entry layout, identical to BTBPredictor: {tag, hist, target}.
    localparam int TAG_WIDTH    = XLEN - 2;
    localparam int TARGET_WIDTH = XLEN - 2;

    /* =================================================================
     * Write side: enable decode, payload, counter update.
     * ================================================================= */
    logic btb_we;
    always_comb begin : write_enable
        case (ctrl_signals_write.pc_source)
            PC_cond, PC_indirect, PC_uncond: btb_we = 1'b1;
            default:                         btb_we = 1'b0;
        endcase
    end : write_enable

    // Was the resolving branch actually taken? Unconditional and indirect
    // jumps always are; conditionals take the shelf's resolved direction.
    logic train_taken;
    assign train_taken = ((ctrl_signals_write.pc_source == PC_cond) & bcond_write)
                       |  (ctrl_signals_write.pc_source == PC_indirect)
                       |  (ctrl_signals_write.pc_source == PC_uncond);

    // Saturating 2-bit counter, from the bits captured at predict time.
    logic [1:0] write_hist;
    always_comb begin : counter_update
        case (write_btb_hist)
            2'b00:   write_hist = train_taken ? 2'b01 : 2'b00;
            2'b01:   write_hist = train_taken ? 2'b10 : 2'b00;
            2'b10:   write_hist = train_taken ? 2'b11 : 2'b01;
            2'b11:   write_hist = train_taken ? 2'b11 : 2'b10;
            default: write_hist = 2'b00;
        endcase
    end : counter_update

    logic [WORD_WIDTH-1:0] btb_write_data;
    assign btb_write_data = {pc_write[XLEN-1:2], write_hist,
                             npc_offset_write[XLEN-1:2]};

    // Row is common to every bank; only the enable is decoded.
    logic [BANK_BITS-1:0] write_bank;
    logic [ROW_BITS-1:0]  write_row;
    assign write_bank = pc_write[BANK_BITS+1:2];
    assign write_row  = pc_write[ROW_BITS+BANK_BITS+1:BANK_BITS+2];

    /* =================================================================
     * The banks. One row index shared by all four reads — the group's
     * addresses differ only in the bits we bank on.
     * ================================================================= */
    logic [ROW_BITS-1:0]                 read_row;
    logic [BANK_BITS-1:0]                start;
    logic [BANKS-1:0][WORD_WIDTH-1:0]    bank_read;

    assign start    = block_pc[0][BANK_BITS+1:2];
    assign read_row = block_pc[0][ROW_BITS+BANK_BITS+1:BANK_BITS+2];

    generate
        genvar b;
        for (b = 0; b < BANKS; b++) begin : btb_bank
            sram_1r_1w #(
                .NUM_WORDS  (ROWS),
                .WORD_WIDTH (WORD_WIDTH)
            ) bank (
                .clk        (clk),
                .rst_l      (rst_l),
                .we         (btb_we && (write_bank == BANK_BITS'(b))),
                .read_addr  (read_row),
                .write_addr (write_row),
                .write_data (btb_write_data),
                .read_data  (bank_read[b])
            );
        end : btb_bank
    endgenerate

    /* =================================================================
     * Rotate banks into fetch order and evaluate each slot.
     * ================================================================= */
    logic [FETCH_WORDS-1:0]                    in_group;
    logic [FETCH_WORDS-1:0][WORD_WIDTH-1:0]    slot_entry;
    logic [FETCH_WORDS-1:0][TAG_WIDTH-1:0]     slot_tag;
    logic [FETCH_WORDS-1:0][1:0]               slot_hist;
    logic [FETCH_WORDS-1:0][TARGET_WIDTH-1:0]  slot_target;

    generate
        genvar w;
        for (w = 0; w < FETCH_WORDS; w++) begin: slot_predict
            // slot w lives in bank (start + w) mod BANKS; the adder wraps
            // naturally at BANK_BITS wide, which is the rotate.
            assign slot_entry[w] = bank_read[start + BANK_BITS'(w)];
            assign {slot_tag[w], slot_hist[w], slot_target[w]} = slot_entry[w];

            // Does slot w still lie inside the block the row index came from?
            assign in_group[w] = (start <= BANK_BITS'(FETCH_WORDS - 1 - w));

            assign btb_hit[w]     = in_group[w] &&
                                    (slot_tag[w] == block_pc[w]);
            // 2'b1x predicts taken, 2'b0x predicts not-taken.
            assign taken_branch[w]      = btb_hit[w] && slot_hist[w][1];
            assign read_btb_hist[w]     = btb_hit[w] ? slot_hist[w] : 2'b00;
            assign predicted_pc_block[w] = taken_branch[w]
                                         ? slot_target[w]
                                         : (block_pc[w] + 1'b1);
        end : slot_predict
    endgenerate

    /* =================================================================
     * Best prediction: oldest predicted-taken slot wins; otherwise walk
     * to the first word of the next block. The group is truncated at the
     * block boundary, so that is where sequential fetch resumes
     * regardless of how many words this group actually covered.
     * ================================================================= */
    logic [XLEN-1:2] seq_next_block, best_word;
    assign seq_next_block = {block_pc[0][XLEN-1:BANK_BITS+2] + 1'b1,
                             BANK_BITS'(0)};

    always_comb begin : best_pick
        best_word = seq_next_block;
        // Descending so the lowest (oldest) taken slot writes last.
        for (int w = FETCH_WORDS - 1; w >= 0; w--) begin
            if (taken_branch[w]) best_word = slot_target[w];
        end
    end : best_pick

    assign best_prediction = {best_word, 2'b00};

endmodule : BTBPredictor4

`default_nettype wire

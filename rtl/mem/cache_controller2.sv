/**
 * Writeback cache controller (write-allocate / fetch-on-write).
 *
 * Protocol with the core (same seam and timing as cache_controller_ref):
 *   - Requests are accepted LIVE: core_rsp_ready=1 in a cycle means the
 *     request presented on core_req_* that cycle is accepted and its cache
 *     probe issues that same cycle. On a miss, ready drops in the same cycle
 *     the probe resolves, so the next request (still level-held by the core,
 *     whose M1 only advances on ready) is never lost. Do NOT pipeline the
 *     core request inputs: a 1-cycle acceptance delay desynchronizes the
 *     response stream from the core's fetch bubble/squash logic.
 *   - Responses (probe hits and read-miss fill-forwards) go through the same
 *     2-deep FIFO as the ref controller; peek_only holds the head while the
 *     core is stalled and flush drops responses on a redirect.
 *
 * Write path (the writeback part):
 *   - Stores never go straight to memory. A store probes the cache first
 *     (WRITE_CACHE_RSP). On a hit the old word is latched; on a miss the
 *     line is fetched first (write-allocate) and the old word is taken from
 *     the fill. WRITE_CACHE_DATA then commits a full-word byte-merge of the
 *     store into the cache (handles sb/sh without flushing anything) and the
 *     cache marks the line dirty.
 *   - When a fill evicts a dirty line, the victim (line + address + dirty,
 *     exported by cache3) is latched and WRITE_EVICT_WRITEBACK streams it to
 *     memory one word per cycle (main memory writes a single word per cycle).
 *
 * FSM:
 *   IDLE                  — accept a live request: probe the cache.
 *   READ_CACHE_RSP        — read probe resolving. Hit: pulse data to core,
 *                           chain the next live request. Miss: request a
 *                           block-aligned fill (hold here, cache stalled,
 *                           until the bus grants).
 *   READ_WAIT_MEM_RSP     — fill in flight. On the matching response: refill
 *                           the cache, forward the word to the core, then
 *                           either write back a dirty victim or chain.
 *   WRITE_CACHE_RSP       — write probe resolving. Hit: latch old word.
 *                           Miss: request the fill (write-allocate).
 *   WRITE_WAIT_MEM_RSP    — write-allocate fill in flight; old word comes
 *                           from the fill data.
 *   WRITE_CACHE_DATA      — commit the merged store word into the cache.
 *   WRITE_EVICT_WRITEBACK — stream the latched dirty victim to memory,
 *                           one word (beat) per cycle.
 */

import DRIS_defs::*;
import RISCV_ISA::*;
import RISCV_UArch::*;  // Import microarchitecture parameters and definitions
import internal_defines_pkg::*;     // Control signals struct, ALU ops

module cache_controller2 #(
    parameter INDEX_BITS        = 4,
    parameter BLOCK_OFFSET_BITS = 2,
    parameter BLOCK_SIZE        = 2 ** BLOCK_OFFSET_BITS,
    parameter WAYS              = 4,
    parameter WORD_SIZE         = 32,
    parameter FETCH_WORDS       = 1,  // words per read response (>1 for the I-side)
    parameter ADDRESS_SIZE      = 30,
    parameter POLICY            = -1
) (
    input  logic clk, rst_l,

    // Core-facing request
    input  logic                          core_req_we,
    input  logic                          core_req_re,
    input  logic [ADDRESS_SIZE-1:0]       core_req_addr,
    input  logic [3:0]                    core_req_store_mask,
    input  logic [WORD_SIZE-1:0]          core_req_store_data,
    input  logic                          core_req_cancel,
    input  logic                          core_req_stall_mem,
    input dris_id_t                      core_req_id,
    input ctrl_signals_t                  core_req_ctrl_signals,
    // Core-facing response
    output logic [ADDRESS_SIZE-1:0]       core_rsp_addr,
    output logic [FETCH_WORDS-1:0][WORD_SIZE-1:0] core_rsp_data,
    output logic                          core_rsp_data_valid,
    output logic                          core_rsp_ready,
    output logic                          core_rsp_excpt,
    output dris_id_t                      core_rsp_id,
    output ctrl_signals_t                 core_rsp_ctrl_signals,

    // Memory-facing response
    input  logic [BLOCK_SIZE-1:0][WORD_SIZE-1:0] mem_rsp_data,
    input  logic                          mem_rsp_valid,
    input  logic [ADDRESS_SIZE-1:0]       mem_rsp_addr,
    input  logic                          mem_rsp_ready,
    input  logic                          mem_rsp_excpt,
    // Memory-facing request
    output logic                          mem_req_data_load_en,
    output logic [3:0]                    mem_req_store_mask,
    output logic [ADDRESS_SIZE-1:0]       mem_req_addr,
    output logic [WORD_SIZE-1:0]          mem_req_store_data,

    // Performance counters
    output logic                          is_eviction,
    output logic                          read_hit,
    output logic                          read_miss
);

    // ---------------- Cache control signals ----------------
    // cache in
    logic [ADDRESS_SIZE-1:0]               address;
    logic                                  rd_en, wr_en, ud_en, flush, cancel, stall;
    logic [BLOCK_SIZE-1:0]                 cache_wr_valid;
    logic [BLOCK_SIZE-1:0][WORD_SIZE-1:0]  cache_wr_word;
    logic [BLOCK_SIZE-1:0]                 cache_fill_valid;
    logic [BLOCK_SIZE-1:0][WORD_SIZE-1:0]  cache_fill_data;

    // cache out
    logic [FETCH_WORDS-1:0][WORD_SIZE-1:0] read_data;
    logic [BLOCK_SIZE-1:0][WORD_SIZE-1:0]  evicted_line;
    logic [ADDRESS_SIZE-1:0]               evicted_addr;
    logic                                  evicted_dirty;

    // ---------------- In-process request ----------------
    // Copy of the accepted request the FSM is currently working on. Doubles as
    // the miss-address latch matched against mem_rsp_addr during fills.
    logic [ADDRESS_SIZE-1:0]       core_req_addr_latched;
    dris_id_t                      core_req_id_latched;
    ctrl_signals_t                  core_req_ctrl_signals_latched;
    logic [3:0]                    core_req_store_mask_latched;
    logic [WORD_SIZE-1:0]          core_req_store_data_latched;

    // Old contents of the word a store targets (for byte-merging sb/sh).
    logic [WORD_SIZE-1:0]          old_word_latched;

    // Dirty victim captured on the fill cycle that evicted it.
    logic [BLOCK_SIZE-1:0][WORD_SIZE-1:0]  evicted_line_latched;
    logic [ADDRESS_SIZE-1:0]               evicted_addr_latched;

    // Writeback bookkeeping.
    logic                          wb_pending;
    logic [BLOCK_OFFSET_BITS-1:0]  wb_beat;
    // A read-miss fill that evicted a dirty line still owes the core its
    // forwarded word: deliver it in READ_FWD after the writeback, so the
    // enqueue is simultaneous with ready=1 (the core's W-alignment depends
    // on that; enqueueing during the writeback gets dequeued into a bubble).
    logic                          fwd_pending;

    // ---------------- FSM helper strobes ----------------
    logic cache_issue_read;      // probe the cache with the live request address
    logic cache_store;           // commit the merged store word this cycle
    logic do_fill;               // refill the cache from mem_rsp_data
    logic do_forward;            // forward the fill word to the core (read miss)
    logic do_evict_writeback;    // drive one writeback beat onto the mem bus
    logic use_latched_addr;      // cache address mux: 1 = in-process store addr
    logic mem_bus_request;       // request a block fill on the mem bus
    logic core_req_bus_wait_en;  // accept the live request (latch it)
    logic latch_old_word_hit;    // old word <- read_data (write probe hit)
    logic latch_old_word_fill;   // old word <- mem_rsp_data (write-allocate)
    logic cache_stall;           // hold a missed probe visible while bus busy
    logic core_hit_valid;        // pulse core_rsp_data_valid from read_data
    logic do_forward_saved;      // forward the saved fill word (post-writeback)

    typedef enum logic [2:0] {
        IDLE,
        READ_CACHE_RSP,
        READ_WAIT_MEM_RSP,
        WRITE_CACHE_RSP,
        WRITE_WAIT_MEM_RSP,
        WRITE_CACHE_DATA,
        WRITE_EVICT_WRITEBACK,
        READ_FWD
    } controller_state_t;
    controller_state_t state, next_state;

    logic mem_rsp_good;
    assign mem_rsp_good = mem_rsp_valid &&
                    (mem_rsp_addr          [ADDRESS_SIZE-1:BLOCK_OFFSET_BITS] ==
                     core_req_addr_latched [ADDRESS_SIZE-1:BLOCK_OFFSET_BITS]);

    // synopsys translate_off
    always_ff @(posedge clk) begin
        assert (~(core_req_re & core_req_we))
        else   $display("uh oh we can't be doing that (re & we asserted same cycle)\n");
    end

    // synopsys translate_on

    // ============================================================
    // FSM — next state
    // ============================================================
    always_comb begin: FSM_next_state
        next_state = state;

        case (state)
            IDLE: begin
                if      (core_req_re) next_state = READ_CACHE_RSP;
                else if (core_req_we) next_state = WRITE_CACHE_RSP;
            end

            READ_CACHE_RSP: begin
                if (read_hit) begin
                    if      (core_req_re) next_state = READ_CACHE_RSP;
                    else if (core_req_we) next_state = WRITE_CACHE_RSP;
                    else                         next_state = IDLE;
                end
                else if (read_miss)
                    next_state = mem_rsp_ready ? READ_WAIT_MEM_RSP : READ_CACHE_RSP;
                else
                    next_state = IDLE;  // probe was cancelled last cycle
            end

            READ_WAIT_MEM_RSP: begin
                if (mem_rsp_good) begin
                    if      (is_eviction && evicted_dirty) next_state = WRITE_EVICT_WRITEBACK;
                    else if (core_req_re)           next_state = READ_CACHE_RSP;
                    else if (core_req_we)           next_state = WRITE_CACHE_RSP;
                    else                                   next_state = IDLE;
                end
            end

            WRITE_CACHE_RSP: begin
                if      (read_hit)  next_state = WRITE_CACHE_DATA;
                else if (read_miss)
                    next_state = mem_rsp_ready ? WRITE_WAIT_MEM_RSP : WRITE_CACHE_RSP;
                else
                    next_state = IDLE;
            end

            WRITE_WAIT_MEM_RSP: begin
                if (mem_rsp_good) next_state = WRITE_CACHE_DATA;
            end

            WRITE_CACHE_DATA: begin
                next_state = wb_pending ? WRITE_EVICT_WRITEBACK : IDLE;
            end

            WRITE_EVICT_WRITEBACK: begin
                if (mem_rsp_ready && (wb_beat == BLOCK_OFFSET_BITS'(BLOCK_SIZE - 1)))
                    next_state = fwd_pending ? READ_FWD : IDLE;
            end

            READ_FWD: begin
                if      (core_req_re) next_state = READ_CACHE_RSP;
                else if (core_req_we) next_state = WRITE_CACHE_RSP;
                else                  next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase

        // A redirect drops whatever is in flight (I-side only; the D-side
        // never cancels).
        if (core_req_cancel) next_state = IDLE;
    end: FSM_next_state

    // ============================================================
    // FSM — output / helper-strobe generation
    // ============================================================
    always_comb begin: FSM_outputs
        cache_issue_read     = 1'b0;
        cache_store          = 1'b0;
        do_fill              = 1'b0;
        do_forward           = 1'b0;
        do_evict_writeback   = 1'b0;
        use_latched_addr     = 1'b0;
        mem_bus_request      = 1'b0;
        core_req_bus_wait_en = 1'b0;
        latch_old_word_hit   = 1'b0;
        latch_old_word_fill  = 1'b0;
        cache_stall          = 1'b0;
        core_hit_valid       = 1'b0;
        do_forward_saved     = 1'b0;
        core_rsp_ready       = 1'b0;

        case (state)
            IDLE: begin
                core_rsp_ready = 1'b1;
                if (core_req_re || core_req_we) begin
                    cache_issue_read     = 1'b1;
                    core_req_bus_wait_en = 1'b1;
                end
            end

            READ_CACHE_RSP: begin
                if (read_hit) begin
                    core_rsp_ready = 1'b1;
                    core_hit_valid = 1'b1;
                    // Chain the next live request back-to-back.
                    if (core_req_re || core_req_we) begin
                        cache_issue_read     = 1'b1;
                        core_req_bus_wait_en = 1'b1;
                    end
                end
                else if (read_miss) begin
                    mem_bus_request = 1'b1;
                    // Bus busy: keep the missed probe visible in the cache
                    // and keep requesting until granted.
                    if (~mem_rsp_ready) cache_stall = 1'b1;
                end
            end

            READ_WAIT_MEM_RSP: begin
                if (mem_rsp_good) begin
                    do_fill = 1'b1;
                    if (!(is_eviction && evicted_dirty)) begin
                        // Forward the word and unstall the core in the SAME
                        // cycle (like the ref controller). The simultaneity
                        // matters: ready=1 releases EMW so the waiting load
                        // moves M2->W exactly one cycle before the FIFO head
                        // shows its data. Also accept the live request.
                        do_forward     = 1'b1;
                        core_rsp_ready = 1'b1;
                        if (core_req_re || core_req_we) begin
                            cache_issue_read     = 1'b1;
                            core_req_bus_wait_en = 1'b1;
                        end
                    end
                    else begin
                        // Dirty eviction: keep ready=0 (can't accept during
                        // the writeback) and DON'T enqueue the forward yet —
                        // an enqueue without ready=1 gets dequeued into a
                        // pipeline bubble and lost. Save the word; READ_FWD
                        // delivers it after the writeback.
                        latch_old_word_fill = 1'b1;
                    end
                end
            end

            WRITE_CACHE_RSP: begin
                if (read_hit) begin
                    latch_old_word_hit = 1'b1;
                end
                else if (read_miss) begin
                    mem_bus_request = 1'b1;   // write-allocate fill
                    if (~mem_rsp_ready) cache_stall = 1'b1;
                end
            end

            WRITE_WAIT_MEM_RSP: begin
                if (mem_rsp_good) begin
                    do_fill             = 1'b1;
                    latch_old_word_fill = 1'b1;
                end
            end

            WRITE_CACHE_DATA: begin
                cache_store      = 1'b1;
                use_latched_addr = 1'b1;  // the store's own address, not the buffer's
            end

            WRITE_EVICT_WRITEBACK: begin
                do_evict_writeback = 1'b1;
            end

            READ_FWD: begin
                // Deliver the saved fill word with ready=1 simultaneous,
                // restoring the ref controller's W-stage alignment, and
                // accept the live request like a hit cycle.
                do_forward_saved = 1'b1;
                core_rsp_ready   = 1'b1;
                if (core_req_re || core_req_we) begin
                    cache_issue_read     = 1'b1;
                    core_req_bus_wait_en = 1'b1;
                end
            end

            default: ;
        endcase

        // A redirect kills the in-flight request: don't accept, probe,
        // request a fill, or reply.
        if (core_req_cancel) begin
            cache_issue_read     = 1'b0;
            core_req_bus_wait_en = 1'b0;
            mem_bus_request      = 1'b0;
            core_hit_valid       = 1'b0;
            do_forward           = 1'b0;
            do_forward_saved     = 1'b0;
        end
    end: FSM_outputs

    // ============================================================
    // Datapath helper blocks
    // ============================================================

    // -------- cache address mux (drives: address) --------
    // Probes use the live request address; the store commit (a fresh cache request)
    // must use the in-process store's address.
    assign address = use_latched_addr ? core_req_addr_latched : core_req_addr;

    // -------- cache request drivers --------
    assign rd_en  = cache_issue_read;
    assign flush  = 1'b0;             // never flush: dirty data lives here
    assign cancel = core_req_cancel;
    assign stall  = cache_stall;

    // -------- store byte-merge (drives: wr_en, cache_wr_*) --------
    // Merge the (possibly partial) store into the word's old contents so the
    // cache always commits a full word. No set flushes, sb/sh included.
    logic [WORD_SIZE-1:0] merged_store_word;
    always_comb begin
        for (int b = 0; b < WORD_SIZE/8; b++) begin
            merged_store_word[b*8 +: 8] = core_req_store_mask_latched[b]
                ? core_req_store_data_latched[b*8 +: 8]
                : old_word_latched[b*8 +: 8];
        end
    end

    always_comb begin: cache_store_block
        wr_en          = 1'b0;
        cache_wr_word  = '0;
        cache_wr_valid = '0;

        if (cache_store) begin
            wr_en = 1'b1;
            cache_wr_word [core_req_addr_latched[BLOCK_OFFSET_BITS-1:0]] = merged_store_word;
            cache_wr_valid[core_req_addr_latched[BLOCK_OFFSET_BITS-1:0]] = 1'b1;
        end
    end: cache_store_block

    // -------- cache fill block (drives: ud_en, cache_fill_*) --------
    always_comb begin: cache_fill_block
        ud_en            = 1'b0;
        cache_fill_data  = '0;
        cache_fill_valid = '0;

        if (do_fill) begin
            ud_en            = 1'b1;
            cache_fill_data  = mem_rsp_data;
            cache_fill_valid = '1;
        end
    end: cache_fill_block

    // -------- mem bus driver --------
    // do_evict_writeback and mem_bus_request are mutually exclusive by FSM
    // construction. Fills are block-aligned; writebacks stream one word per
    // cycle (main memory only writes a single word at a time).
    always_comb begin: mem_bus_driver_block
        mem_req_data_load_en = 1'b0;
        mem_req_store_mask   = '0;
        mem_req_store_data   = '0;
        mem_req_addr         = {core_req_addr_latched[ADDRESS_SIZE-1:BLOCK_OFFSET_BITS],
                                {BLOCK_OFFSET_BITS{1'b0}}};

        if (do_evict_writeback) begin
            mem_req_store_mask = 4'hf;
            mem_req_addr       = evicted_addr_latched + ADDRESS_SIZE'(wb_beat);
            mem_req_store_data = evicted_line_latched[wb_beat];
        end
        else if (mem_bus_request) begin
            mem_req_data_load_en = 1'b1;
        end
    end: mem_bus_driver_block

    // -------- core response path --------
    // Responses go through the same 2-deep FIFO the reference controller
    // uses: peek_only holds the head entry while the core is stalled
    // (core_req_stall_mem), so a 1-cycle hit/fill pulse is never lost, and
    // flush drops in-flight responses on a redirect.
    // Depth 2 = one head held under peek_only + one in-flight probe's response.
    // The core's backpressure (see the overflow assert below) is what keeps
    // the outstanding work inside that bound.
    localparam int RSP_FIFO_ELEMENTS = 2;
    logic                                              fifo_enable;
    logic [$clog2(RSP_FIFO_ELEMENTS+1)-1:0]            fifo_elems;
    logic [FETCH_WORDS*WORD_SIZE + ADDRESS_SIZE + $bits(dris_id_t) + $bits(ctrl_signals_t) : 0]
    fifo_data;  // {valid, data, addr}

    // Read-miss fill-forward: slice FETCH_WORDS words out of the fill block
    // starting at the requested offset, clamped at the block end — the same
    // rule as cache3's read mux, so hit and miss responses are shape-identical.
    logic [FETCH_WORDS-1:0][WORD_SIZE-1:0] fwd_words, rsp_words;
    always_comb begin
        automatic int base = int'(core_req_addr_latched[BLOCK_OFFSET_BITS-1:0]);
        fwd_words = '0;
        for (int w = 0; w < FETCH_WORDS; w++) begin
            if (base + w < BLOCK_SIZE)
                fwd_words[w] = mem_rsp_data[base + w];
        end
    end

    // do_forward_saved only exists on the write-capable D-side (dirty-victim
    // eviction on a read miss), where FETCH_WORDS=1: word 0 carries the value.
    always_comb begin
        if      (do_forward)       rsp_words = fwd_words;
        else if (do_forward_saved) begin
            rsp_words    = '0;
            rsp_words[0] = old_word_latched;
        end
        else                       rsp_words = read_data;
    end

    assign fifo_enable = core_hit_valid | do_forward | do_forward_saved;
    assign fifo_data   = {1'b1, rsp_words, core_req_addr_latched, core_req_id_latched, core_req_ctrl_signals_latched};

    // always_ff @(posedge clk, negedge rst_l) begin
    //     $display($time, "cache_controller2: fifo_data=%b, fifo_enable=%b, core_req_id_latched=%h", fifo_data, fifo_enable, core_req_id_latched);
    // end

    fifo #(
        .WIDTH       (1 + FETCH_WORDS*WORD_SIZE + ADDRESS_SIZE + $bits(dris_id_t) + $bits(ctrl_signals_t)),
        .MAX_ELEMENTS(RSP_FIFO_ELEMENTS)
    ) feefifofum (
        .clk, .rst_l,
        .peek_only  (core_req_stall_mem),
        .flush      (core_req_cancel),
        .enq_data   (fifo_data),
        .num_enq    (fifo_enable),
        .num_deq    (1'b1),
        .deq_data   ({core_rsp_data_valid, core_rsp_data, core_rsp_addr, core_rsp_id, core_rsp_ctrl_signals}),
        .num_suc_enq(),
        .num_suc_deq(),
        .num_q_elem (fifo_elems)
    );

    // The FIFO drops enqueues silently when full, and a dropped instruction
    // response is invisible until the register dump disagrees dozens of
    // instructions later. The core must supply backpressure (drop core_req_re
    // while stalled) so this can never happen; assert it rather than trust it.
    // synopsys translate_off
    always_ff @(posedge clk) begin
        assert (!(rst_l && fifo_enable && !core_req_cancel &&
                  fifo_elems == RSP_FIFO_ELEMENTS && core_req_stall_mem))
        else $error("%0t %m: response FIFO overflow, dropped addr=%h — the core kept requesting while stalled",
                    $time, {core_req_addr_latched, 2'b00});
    end
    // synopsys translate_on

    assign core_rsp_excpt = mem_rsp_excpt;

    // ============================================================
    // Cache instance
    // ============================================================
    cache3 #(
        .INDEX_BITS(INDEX_BITS),
        .BLOCK_OFFSET_BITS(BLOCK_OFFSET_BITS),
        .WAYS(WAYS),
        .WORD_SIZE(WORD_SIZE),
        .FETCH_WORDS(FETCH_WORDS),
        .ADDRESS_SIZE(ADDRESS_SIZE),
        .POLICY(POLICY)
    ) craching_out (
        .clk, .rst_l,
        .address,
        .rd_en,
        .wr_en,
        .ud_en,
        .flush,
        .cancel,
        .stall,
        .core_write_data_valid (cache_wr_valid),
        .core_write_data       (cache_wr_word),
        .memory_data_valid     (cache_fill_valid),
        .memory_data           (cache_fill_data),
        .read_data,
        .read_addr             (),
        .read_hit,
        .read_miss,
        .is_eviction,
        .evicted_line,
        .evicted_addr,
        .evicted_dirty
    );

    // ============================================================
    // State / data registers
    // ============================================================
    always_ff @(posedge clk, negedge rst_l) begin: state_reg
        if (~rst_l) state <= IDLE;
        else        state <= next_state;
    end: state_reg

    always_ff @(posedge clk, negedge rst_l) begin: in_process_request_register
        if (~rst_l) begin
            core_req_addr_latched       <= '0;
            core_req_id_latched         <= '0;
            core_req_ctrl_signals_latched <= '0;
            core_req_store_mask_latched <= '0;
            core_req_store_data_latched <= '0;
        end
        else if (core_req_bus_wait_en) begin
            core_req_addr_latched       <= core_req_addr;
            core_req_id_latched         <= core_req_id;
            core_req_ctrl_signals_latched <= core_req_ctrl_signals;
            core_req_store_mask_latched <= core_req_store_mask;
            core_req_store_data_latched <= core_req_store_data;
        end
    end: in_process_request_register

    always_ff @(posedge clk, negedge rst_l) begin: old_word_register
        if (~rst_l)
            old_word_latched <= '0;
        else if (latch_old_word_hit)
            old_word_latched <= read_data[0];  // cache reads start at the requested offset
        else if (latch_old_word_fill)
            old_word_latched <= mem_rsp_data[core_req_addr_latched[BLOCK_OFFSET_BITS-1:0]];
    end: old_word_register

    always_ff @(posedge clk, negedge rst_l) begin: evicted_line_register
        if (~rst_l) begin
            evicted_line_latched <= '0;
            evicted_addr_latched <= '0;
        end
        else if (is_eviction && evicted_dirty) begin
            evicted_line_latched <= evicted_line;
            evicted_addr_latched <= evicted_addr;
        end
    end: evicted_line_register

    always_ff @(posedge clk, negedge rst_l) begin: writeback_bookkeeping
        if (~rst_l) begin
            wb_pending  <= 1'b0;
            wb_beat     <= '0;
            fwd_pending <= 1'b0;
        end
        else begin
            // A read-path fill that evicts dirty still owes the forward.
            if (do_fill && is_eviction && evicted_dirty
                && (state == READ_WAIT_MEM_RSP))
                fwd_pending <= 1'b1;
            else if (do_forward_saved)
                fwd_pending <= 1'b0;

            if (do_fill && is_eviction && evicted_dirty)
                wb_pending <= 1'b1;
            else if (do_evict_writeback && mem_rsp_ready
                     && (wb_beat == BLOCK_OFFSET_BITS'(BLOCK_SIZE - 1)))
                wb_pending <= 1'b0;

            if (do_evict_writeback && mem_rsp_ready)
                wb_beat <= wb_beat + 1'b1;  // wraps to 0 on the last beat
        end
    end: writeback_bookkeeping

    // synopsys translate_off
`ifdef DEBUG_CACHE_IFACE
    always_ff @(posedge clk) begin
        if (rst_l) begin
            $display("%0t %m st=%s req(re=%b we=%b a=%h cncl=%b) ltch=%h rdy=%b hit=%b miss=%b evd=%b fwd=%b hv=%b acc=%b stl=%b | rsp(v=%b a=%h d=%h)",
                $time, state.name(), core_req_re, core_req_we,
                {core_req_addr, 2'b00}, core_req_cancel, {core_req_addr_latched, 2'b00},
                core_rsp_ready, read_hit, read_miss, is_eviction && evicted_dirty,
                do_forward, core_hit_valid,
                core_req_bus_wait_en, core_req_stall_mem,
                core_rsp_data_valid, {core_rsp_addr, 2'b00}, core_rsp_data);
            if (cache_store)
                $display("%0t %m STORE-COMMIT addr=%h merged=%h mask=%b old=%h data=%h",
                    $time, {core_req_addr_latched, 2'b00}, merged_store_word,
                    core_req_store_mask_latched, old_word_latched, core_req_store_data_latched);
            if (do_evict_writeback)
                $display("%0t %m WB-BEAT beat=%0d addr=%h data=%h memrdy=%b",
                    $time, wb_beat, {mem_req_addr, 2'b00}, mem_req_store_data, mem_rsp_ready);
            if (is_eviction)
                $display("%0t %m EVICT-LATCH dirty=%b addr=%h line=%h",
                    $time, evicted_dirty, {evicted_addr, 2'b00}, evicted_line);
            if (do_fill)
                $display("%0t %m FILL addr=%h data=%h", $time,
                    {mem_rsp_addr, 2'b00}, mem_rsp_data);
        end
    end
`endif
    // synopsys translate_on

endmodule : cache_controller2

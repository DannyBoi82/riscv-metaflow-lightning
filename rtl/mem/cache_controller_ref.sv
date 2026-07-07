/**
 * Cache controller — refactored for readability.
 *
 * Behavior, interface, and cycle-level timing are IDENTICAL to the original
 * (Epel/Mayer 2026). Changes are organizational only and fully synthesizable
 * (pure combinational logic in always_comb; no tasks, no latches — every
 * signal has a default assignment at the top of the always_comb block).
 *
 * What changed vs. the original:
 *   1. Removed the dead-code duplicate WAIT_FOR_BUS branch (the original
 *      `unique case` had two `WAIT_FOR_BUS:` arms; only the first was reached).
 *   2. The "commit a write-through store to the cache array" sequence
 *      appeared in 4 places. It's now a single combinational block guarded
 *      by `do_store_commit`, with the source addr/mask/data muxed by
 *      `commit_use_registered`.
 *   3. The "issue a fresh cache probe for the next core read" sequence
 *      appeared in 3 places. It's now guarded by `do_issue_read`.
 *   4. Replaced magic numbers (32, 30, 4) with WORD_SIZE / ADDRESS_SIZE /
 *      BLOCK_SIZE / BLOCK_OFFSET_BITS where appropriate.
 *   5. Grouped signal declarations by purpose; renamed a few internals.
 *   6. Added comments describing each FSM state and transition.
 *
 * FSM:
 *   IDLE          — no probe in flight. New core req either kicks off a
 *                   cache probe (read) or is sent straight to the mem bus
 *                   (write-through).
 *   CACHE_RSP     — one cycle after a probe. On hit, push to response FIFO
 *                   and optionally launch the next probe. On miss, request
 *                   a line fill from memory.
 *   WAIT_FOR_RSP  — line fill in flight. When matching mem_rsp_valid
 *                   arrives, write the line and (optionally) start next req.
 *   WAIT_FOR_BUS  — write-through queued but mem bus was busy. Hold the
 *                   registered store until mem_rsp_ready, then commit.
 */

module cache_controller_ref #(
    parameter INDEX_BITS        = 4,
    parameter BLOCK_OFFSET_BITS = 2,
    parameter BLOCK_SIZE        = 2 ** BLOCK_OFFSET_BITS,
    parameter WAYS              = 4,
    parameter WORD_SIZE         = 32,
    parameter ADDRESS_SIZE      = 30,
    parameter POLICY            = -1
) (
    input  logic clk, rst_l,

    /* ---------------- Core-facing request ---------------- */
    input  logic                          core_req_we,
    input  logic                          core_req_re,
    input  logic [ADDRESS_SIZE-1:0]       core_req_addr,
    input  logic [3:0]                    core_req_store_mask,
    input  logic [WORD_SIZE-1:0]          core_req_store_data,
    input  logic                          core_req_cancel,
    input  logic                          core_req_stall_mem,

    /* ---------------- Core-facing response --------------- */
    output logic [ADDRESS_SIZE-1:0]       core_rsp_addr,
    output logic [WORD_SIZE-1:0]          core_rsp_data,
    output logic                          core_rsp_data_valid,
    output logic                          core_rsp_ready,
    output logic                          core_rsp_excpt,

    /* ---------------- Memory-facing response ------------- */
    input  logic [BLOCK_SIZE-1:0][WORD_SIZE-1:0] mem_rsp_data,
    input  logic                          mem_rsp_valid,
    input  logic [ADDRESS_SIZE-1:0]       mem_rsp_addr,
    input  logic                          mem_rsp_ready,
    input  logic                          mem_rsp_excpt,

    /* ---------------- Memory-facing request -------------- */
    output logic                          mem_req_data_load_en,
    output logic [3:0]                    mem_req_store_mask,
    output logic [ADDRESS_SIZE-1:0]       mem_req_addr,
    output logic [WORD_SIZE-1:0]          mem_req_store_data,

    /* ---------------- Performance counters --------------- */
    output logic                          is_eviction,
    output logic                          read_hit,
    output logic                          read_miss
);

    // =======================================================================
    // FSM state
    // =======================================================================
    typedef enum logic [1:0] {
        IDLE,
        WAIT_FOR_RSP,
        CACHE_RSP,
        WAIT_FOR_BUS
    } state_t;
    state_t state, next_state;

    // =======================================================================
    // Cache-array control signals (driven into `cache` instance)
    // =======================================================================
    logic [ADDRESS_SIZE-1:0]               address;
    logic                                  rd_en, wr_en, ud_en, flush, cancel, stall;
    logic [BLOCK_SIZE-1:0]                 cache_wr_valid;
    logic [BLOCK_SIZE-1:0][WORD_SIZE-1:0]  cache_wr_word;
    logic [BLOCK_SIZE-1:0]                 cache_fill_valid;
    logic [BLOCK_SIZE-1:0][WORD_SIZE-1:0]  cache_fill_data;
    logic [WORD_SIZE-1:0]                  read_data;

    // =======================================================================
    // Address / store registers (preserve in-flight request across cycles)
    // =======================================================================
    logic                          enable;            // enables req_addr capture
    logic [ADDRESS_SIZE-1:0]       req_addr;          // address of in-flight probe

    logic                          register_store_data;
    logic [3:0]                    registered_store_mask;
    logic [WORD_SIZE-1:0]          registered_store_data;
    logic [ADDRESS_SIZE-1:0]       registered_addr;

    // =======================================================================
    // Response FIFO controls
    // =======================================================================
    logic                                       fifo_enable;
    logic [WORD_SIZE + ADDRESS_SIZE : 0]        fifo_data;  // {valid, data, addr}

    // =======================================================================
    // Helper signals for factored-out logic
    // =======================================================================
    // do_store_commit: drive the cache + bus signals to commit a write-through
    //   store. Source operands chosen by commit_use_registered:
    //     0 -> use core_req_*  (live core inputs)
    //     1 -> use registered_* (previously latched store, replayed from
    //                            WAIT_FOR_BUS)
    logic do_store_commit;
    logic commit_use_registered;

    // do_issue_read: kick off a fresh cache probe using core_req_addr. Used
    //   to back-to-back chain reads through CACHE_RSP.
    logic do_issue_read;

    // Internal aliases used by the commit block; defaulted in always_comb.
    logic [ADDRESS_SIZE-1:0]       commit_addr;
    logic [3:0]                    commit_mask;
    logic [WORD_SIZE-1:0]          commit_data;

    // =======================================================================
    // Cache instance
    // =======================================================================
    cache3 #(
        .INDEX_BITS(INDEX_BITS),
        .BLOCK_OFFSET_BITS(BLOCK_OFFSET_BITS),
        .WAYS(WAYS),
        .WORD_SIZE(WORD_SIZE),
        .FETCH_WORDS(1),
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
        .memory_data_valid(cache_fill_valid),
        .memory_data      (cache_fill_data),
        .read_data,
        .read_addr        (),
        .read_hit         (read_hit),
        .read_miss        (read_miss),
        .is_eviction      (is_eviction),
        .evicted_line     (),
        .evicted_addr     (),
        .evicted_dirty    ()
    );

    // =======================================================================
    // Main combinational FSM
    // =======================================================================
    always_comb begin
        // ---- Defaults: every signal driven, no latches ----------------------
        next_state           = state;

        core_rsp_ready       = 1'b1;
        core_rsp_excpt       = mem_rsp_excpt;

        mem_req_data_load_en = 1'b0;
        mem_req_store_mask   = '0;
        mem_req_addr         = core_req_addr;
        mem_req_store_data   = core_req_store_data;

        address              = {core_req_addr[ADDRESS_SIZE-1:BLOCK_OFFSET_BITS],
                                {BLOCK_OFFSET_BITS{1'b0}}}; // block-aligned default
        rd_en                = 1'b0;
        wr_en                = 1'b0;
        ud_en                = 1'b0;
        flush                = 1'b0;
        cancel               = 1'b0;
        stall                = 1'b0;
        cache_wr_word        = '0;
        cache_wr_valid       = '0;
        cache_fill_data      = '0;
        cache_fill_valid     = '0;

        enable               = 1'b0;
        register_store_data  = 1'b0;

        fifo_enable          = 1'b0;
        fifo_data            = '0;

        do_store_commit       = 1'b0;
        commit_use_registered = 1'b0;
        do_issue_read         = 1'b0;

        unique case (state)
            // ---------------------------------------------------------------
            // IDLE: nothing in flight. Accept a new core request.
            // ---------------------------------------------------------------
            IDLE: begin
                if (core_req_re) begin
                    do_issue_read = 1'b1;
                    next_state    = CACHE_RSP;
                end
                else if (core_req_we) begin
                    // Write-through: must drive the mem bus this cycle. If the
                    // bus is free (mem_rsp_ready), commit immediately;
                    // otherwise latch and wait in WAIT_FOR_BUS.
                    mem_req_store_mask = core_req_store_mask;
                    if (mem_rsp_ready) begin
                        do_store_commit       = 1'b1;
                        commit_use_registered = 1'b0;
                    end
                    else begin
                        register_store_data = 1'b1;
                        next_state          = WAIT_FOR_BUS;
                    end
                end

                if (core_req_cancel) begin
                    next_state         = IDLE;
                    mem_req_store_mask = '0;
                end
            end

            // ---------------------------------------------------------------
            // CACHE_RSP: probe issued last cycle is now resolving.
            // ---------------------------------------------------------------
            CACHE_RSP: begin
                next_state = IDLE;

                if (read_hit) begin
                    // Push the hit data into the response FIFO.
                    fifo_enable = 1'b1;
                    fifo_data   = {1'b1, read_data, req_addr};

                    // Pipeline: if the core has another request ready, launch
                    // it now so we stay back-to-back.
                    if (core_req_re) begin
                        do_issue_read = 1'b1;
                        next_state    = CACHE_RSP;
                    end
                    else if (core_req_we) begin
                        mem_req_store_mask = core_req_store_mask;
                        if (mem_rsp_ready) begin
                            do_store_commit       = 1'b1;
                            commit_use_registered = 1'b0;
                        end
                        else begin
                            register_store_data = 1'b1;
                            next_state          = WAIT_FOR_BUS;
                        end
                    end
                end
                else if (read_miss) begin
                    // Request a line fill from memory. If the bus isn't ready
                    // yet, hold here and keep asserting the request.
                    core_rsp_ready       = 1'b0;
                    mem_req_data_load_en = 1'b1;
                    mem_req_addr         = {req_addr[ADDRESS_SIZE-1:BLOCK_OFFSET_BITS],
                                            {BLOCK_OFFSET_BITS{1'b0}}};
                    if (mem_rsp_ready) begin
                        next_state = WAIT_FOR_RSP;
                    end
                    else begin
                        stall      = 1'b1;
                        next_state = CACHE_RSP;
                    end
                end

                if (core_req_cancel) begin
                    next_state         = IDLE;
                    cancel             = 1'b1;
                    mem_req_store_mask = '0;
                end
            end

            // ---------------------------------------------------------------
            // WAIT_FOR_RSP: waiting for the line fill from main memory.
            // ---------------------------------------------------------------
            WAIT_FOR_RSP: begin
                core_rsp_ready = 1'b0;
                next_state     = WAIT_FOR_RSP;

                if (mem_rsp_valid &&
                    (mem_rsp_addr[ADDRESS_SIZE-1:BLOCK_OFFSET_BITS] ==
                     req_addr   [ADDRESS_SIZE-1:BLOCK_OFFSET_BITS])) begin
                    // Fill arrived. Write the whole line into the cache and
                    // forward the requested word to the response FIFO.
                    core_rsp_ready   = 1'b1;
                    ud_en            = 1'b1;
                    cache_fill_valid = '1;
                    cache_fill_data  = mem_rsp_data;
                    address          = req_addr;

                    fifo_enable = 1'b1;
                    fifo_data   = {1'b1,
                                   mem_rsp_data[req_addr[BLOCK_OFFSET_BITS-1:0]],
                                   req_addr};

                    next_state = IDLE;

                    // Same back-to-back chaining as in CACHE_RSP.
                    if (core_req_re) begin
                        do_issue_read = 1'b1;
                        next_state    = CACHE_RSP;
                        // do_issue_read drives address = core_req_addr below;
                        // that overrides the `address = req_addr` set above.
                    end
                    else if (core_req_we) begin
                        mem_req_store_mask = core_req_store_mask;
                        if (mem_rsp_ready) begin
                            do_store_commit       = 1'b1;
                            commit_use_registered = 1'b0;
                            // Note: commit overrides `address = req_addr`
                            // above with the store's own address.
                        end
                        else begin
                            register_store_data = 1'b1;
                            next_state          = WAIT_FOR_BUS;
                        end
                    end
                end

                if (core_req_cancel) begin
                    next_state         = IDLE;
                    mem_req_store_mask = '0;
                    cancel             = 1'b1;
                end
            end

            // ---------------------------------------------------------------
            // WAIT_FOR_BUS: replay a queued write-through when bus frees up.
            // ---------------------------------------------------------------
            WAIT_FOR_BUS: begin
                $display($time,, "You reached the WAIT_FOR_BUS state in the cache controller FSM. If this isn't working how you expected, please contact course staff.");
                next_state         = WAIT_FOR_BUS;
                core_rsp_ready     = 1'b0;
                mem_req_store_mask = registered_store_mask;
                mem_req_store_data = registered_store_data;
                mem_req_addr       = registered_addr;

                if (mem_rsp_ready) begin
                    next_state            = IDLE;
                    do_store_commit       = 1'b1;
                    commit_use_registered = 1'b1;
                end
            end

            default: next_state = IDLE;
        endcase

        // ===================================================================
        // Factored helpers — these execute *after* the case so they win the
        // last-assignment race for the signals they drive. This matches the
        // original code, which also lets the action-block override defaults
        // set earlier in the same always_comb.
        // ===================================================================

        // ---- do_issue_read: launch a new cache probe from core_req_addr ---
        if (do_issue_read) begin
            enable  = 1'b1;          // capture core_req_addr into req_addr
            rd_en   = 1'b1;
            address = core_req_addr; // probe the full (word-granular) address
        end

        // ---- do_store_commit: write-through commit into the cache array ---
        if (do_store_commit) begin
            commit_addr = commit_use_registered ? registered_addr       : core_req_addr;
            commit_mask = commit_use_registered ? registered_store_mask : core_req_store_mask;
            commit_data = commit_use_registered ? registered_store_data : core_req_store_data;

            address = commit_addr;
            if (commit_mask == 4'hf) begin
                // Full-word store: install the word in the cache.
                cache_wr_word [commit_addr[BLOCK_OFFSET_BITS-1:0]] = commit_data;
                cache_wr_valid[commit_addr[BLOCK_OFFSET_BITS-1:0]] = 1'b1;
                wr_en = 1'b1;
            end
            else begin
                // Partial store: punt and flush the line (per spec, simplest
                // correct behavior — write-merging is a 4b optimization).
                flush = 1'b1;
            end
        end
        else begin
            // Defaults so commit_* are never inferred as latches.
            commit_addr = '0;
            commit_mask = '0;
            commit_data = '0;
        end
    end

    // =======================================================================
    // State register
    // =======================================================================
    always_ff @(posedge clk, negedge rst_l) begin
        if (~rst_l) state <= IDLE;
        else        state <= next_state;
    end

    // =======================================================================
    // Capture the address of the in-flight probe.
    // =======================================================================
    always_ff @(posedge clk, negedge rst_l) begin
        if (~rst_l)        req_addr <= '0;
        else if (enable)   req_addr <= core_req_addr;
    end

    // =======================================================================
    // Latch a queued store while waiting for the mem bus.
    // =======================================================================
    always_ff @(posedge clk, negedge rst_l) begin
        if (~rst_l) begin
            registered_store_mask <= '0;
            registered_store_data <= '0;
            registered_addr       <= '0;
        end
        else if (register_store_data) begin
            registered_store_mask <= core_req_store_mask;
            registered_store_data <= core_req_store_data;
            registered_addr       <= core_req_addr;
        end
    end

    // =======================================================================
    // Response FIFO (decouples cache hit timing from core-visible response)
    // =======================================================================
    fifo #(
        .WIDTH       (1 + WORD_SIZE + ADDRESS_SIZE),
        .MAX_ELEMENTS(2)
    ) feefifofum (
        .clk, .rst_l,
        .peek_only (core_req_stall_mem),
        .flush     (core_req_cancel),
        .enq_data  (fifo_data),
        .num_enq   (fifo_enable),
        .num_deq   (1'b1),
        .deq_data  ({core_rsp_data_valid, core_rsp_data, core_rsp_addr}),
        .num_suc_enq(),
        .num_suc_deq(),
        .num_q_elem ()
    );

endmodule : cache_controller_ref
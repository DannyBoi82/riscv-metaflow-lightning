import internal_defines_pkg::*;

/**
 * cache3.sv
 *
 * Cleaned-up version of cache2.sv (originally Varun Rajesh, 2025; eviction-export
 * additions by Elisa Mayer / Feya Epel, 2026). Behavior is identical to cache2;
 * this version only renames signals, fixes hardcoded widths, removes a dead
 * signal, and pulls a compound gate into named subexpressions.
 *
 * --- Renames (cache2 -> cache3) ---
 *   Port  user_read_hit      ->  read_hit
 *   Port  user_read_miss     ->  read_miss
 *   Port  user_is_eviction   ->  is_eviction
 *   Wire  decoded_address    ->  incoming_addr     (new addr on input ports this cycle)
 *   Wire  write_address      ->  current_addr      (addr of the request being processed)
 *   Wire  cache_read_data    ->  current_set       (registered set being processed)
 *   Wire  cache_write_data   ->  next_set_data     (set value to write back to SRAM)
 *   Wire  read_set           ->  sram_read_set     (raw combinational SRAM output)
 *   Wire  read_hit  (int)    ->  tag_hit           (raw tag-compare hit  this cycle)
 *   Wire  read_miss (int)    ->  tag_miss          (raw tag-compare miss this cycle)
 *   Wire  is_eviction (int)  ->  eviction_cond     (raw combinational eviction condition)
 *
 * --- Other cleanup ---
 *   - Removed dead signal `read` (declared, defaulted to 0, never assigned).
 *   - Replaced hardcoded [3:0][31:0] / [3:0] widths in
 *     inflight_request_state_t.new_data, .word_write_en, write_data,
 *     and write_data_valid with BLOCK_SIZE / WORD_SIZE parameters.
 *   - Broke the new-request acceptance gate into four named signals
 *     (have_incoming_request, miss_refill_pending, load_just_missed,
 *     can_accept_new) instead of one compound boolean.
 *
 * --- Two-cycle hit latency (unchanged) ---
 *   Cycle 0:  caller asserts rd_en + address. SRAM begins a read on
 *             incoming_addr.index. The FSM stages the request into next_inflight.
 *   Cycle 1:  curr_inflight holds the request. Tag compare runs against
 *             current_set (the registered state_data). On hit, read_data and
 *             read_hit are valid. On miss, FSM transitions to MISS_UPDATE.
 *
 * Parameters (unchanged):
 *   INDEX_BITS         Bits forming the set index.
 *   BLOCK_OFFSET_BITS  Bits forming the block offset.
 *   BLOCK_SIZE         Words per block (= 2 ** BLOCK_OFFSET_BITS).
 *   WAYS               Associativity (must be a power of 2).
 *   WORD_SIZE          Bits per word.
 *   ADDRESS_SIZE       Bits in the address.
 *   POLICY             0 = DIRECT, 1 = LRU, 2 = MRU.
 */

module cache3 #(
    parameter INDEX_BITS        = 4,
    parameter BLOCK_OFFSET_BITS = 2,
    parameter BLOCK_SIZE        = 2 ** BLOCK_OFFSET_BITS,
    parameter WAYS              = 4,
    parameter WORD_SIZE         = 32,
    parameter FETCH_WORDS       = 4,  // number of words returned on a read
    parameter ADDRESS_SIZE      = 30,
    parameter POLICY            = -1
) (
    input  logic clk,
    input  logic rst_l,

    input  logic [ADDRESS_SIZE-1:0]               address,
    input  logic                                  rd_en,    // accept a read request
    input  logic                                  ud_en,    // refill data is being supplied this cycle
    input  logic                                  wr_en,    // accept a write request
    input  logic                                  flush,    // invalidate the indexed set
    input  logic                                  cancel,   // drop the in-flight request
    input  logic                                  stall,    // freeze the pipeline (refills still drain)

    input  logic [BLOCK_SIZE-1:0]                 core_write_data_valid,
    input  logic [BLOCK_SIZE-1:0]                 memory_data_valid,
    input  logic [BLOCK_SIZE-1:0][WORD_SIZE-1:0]  core_write_data,
    input  logic [BLOCK_SIZE-1:0][WORD_SIZE-1:0]  memory_data,

    output logic [FETCH_WORDS-1:0][WORD_SIZE-1:0]  read_data,
    output logic [ADDRESS_SIZE-1:0]               read_addr,
    output logic                                  read_hit,
    output logic                                  read_miss,
    output logic                                  is_eviction,

    output logic [BLOCK_SIZE-1:0][WORD_SIZE-1:0]  evicted_line,
    output logic [ADDRESS_SIZE-1:0]               evicted_addr,
    output logic                                  evicted_dirty
);

    // -------------------------------------------------------------------------
    // Derived parameters
    // -------------------------------------------------------------------------
    localparam int METADATA_BITS_PER_WAY = (POLICY == 0) ? 1
                                         : (POLICY == 1) ? $clog2(WAYS)
                                         : (POLICY == 2) ? 1
                                         : 1;
    localparam int METADATA_BITS = METADATA_BITS_PER_WAY * WAYS;
    localparam int TAG_BITS      = ADDRESS_SIZE - INDEX_BITS - BLOCK_OFFSET_BITS;
    localparam int CACHE_DEPTH   = 2 ** INDEX_BITS;

    initial begin
        if (WAYS != (2 ** $clog2(WAYS)))
            $fatal(1, "WAYS must be a power of 2");
        if (WAYS <= 0)
            $fatal(1, "WAYS must be greater than 0");
        if ((POLICY == 0) != (WAYS == 1))
            $fatal(1, "POLICY must be DIRECT if and only if WAYS is 1");
    end

    // -------------------------------------------------------------------------
    // Data structures
    // -------------------------------------------------------------------------
    typedef struct packed {
        logic                                  dirty;
        logic [BLOCK_SIZE-1:0]                 valid;
        logic [TAG_BITS-1:0]                   tag;
        logic [BLOCK_SIZE-1:0][WORD_SIZE-1:0]  line;
    } cache_block_t;

    typedef struct packed {
        logic [METADATA_BITS-1:0]  metadata;
        cache_block_t [WAYS-1:0]   blocks;
    } cache_set_t;

    typedef struct packed {
        logic [TAG_BITS-1:0]          tag;
        logic [INDEX_BITS-1:0]        index;
        logic [BLOCK_OFFSET_BITS-1:0] block_offset;
    } address_t;

    typedef enum logic [2:0] {
        IDLE = '0,
        LOAD,
        MISS_UPDATE,
        STORE,
        FLUSH
    } cache_state_t;

    typedef struct packed {
        cache_state_t                          request_type;
        cache_set_t                            state_data;
        address_t                              req_addr;
        logic [BLOCK_SIZE-1:0][WORD_SIZE-1:0]  new_data;
        logic [BLOCK_SIZE-1:0]                 word_write_en;
    } inflight_request_state_t;

    // -------------------------------------------------------------------------
    // Pipelined state
    //
    // curr_inflight is the registered FSM state; next_inflight is computed
    // combinationally each cycle. A request entering at the input ports gets
    // latched into curr_inflight on the next clock edge, and the tag compare
    // and read-data mux run against curr_inflight on the cycle after that.
    // Hence the 2-cycle hit latency.
    // -------------------------------------------------------------------------
    inflight_request_state_t  curr_inflight, next_inflight;

    // Address views:
    //   incoming_addr  = new address on the input ports THIS cycle.
    //   current_addr   = address of the request being PROCESSED this cycle
    //                    (curr_inflight.req_addr, with block_offset cleared
    //                    during a refill).
    address_t  incoming_addr, current_addr;

    // Cache-set views:
    //   sram_read_set  = raw combinational read from the SRAM, indexed by
    //                    incoming_addr; used to seed next_inflight.state_data.
    //   current_set    = the registered set being processed
    //                    (curr_inflight.state_data).
    //   next_set_data  = the set value to write back into the SRAM this cycle.
    cache_set_t  sram_read_set, current_set, next_set_data;

    // Per-way comparison results against current_addr and current_set.
    logic [WAYS-1:0]  way_tag_match;    // tag matches (regardless of valid)
    logic [WAYS-1:0]  way_valid;        // any valid bit set in the way
    logic [WAYS-1:0]  way_hit;          // valid && tag_match
    logic [WAYS-1:0]  way_block_hit;    // valid for requested word && tag_match
    logic [WAYS-1:0]  way_write_enable;

    // FSM intent / handshake signals.
    logic  hit_check;        // gate so tag-compare results only count when expected
    logic  tag_hit;          // (|way_block_hit) when hit_check
    logic  tag_miss;         // ~(|way_block_hit) when hit_check
    logic  enable;           // "doing real work this cycle"
    logic  write;            // FSM intent to write the SRAM
    logic  update;           // metadata bump on a load hit
    logic  int_flush;        // invalidate the indexed set (per-set flush)
    logic  cache_we;         // actual SRAM write-enable (after stall/cancel gating)
    logic  eviction_cond;    // raw combinational eviction condition
    logic  mark_dirty;       // this cycle's write is a core store (not a refill)

    logic [BLOCK_SIZE-1:0][WORD_SIZE-1:0]  write_data;
    logic [BLOCK_SIZE-1:0]                 write_data_valid;

    assign incoming_addr = address;

    // -------------------------------------------------------------------------
    // New-request acceptance gates
    //
    // The original code expressed this as one compound condition. Splitting it
    // up makes the FSM's gating much easier to follow:
    //   - have_incoming_request : caller is asking for something this cycle
    //   - miss_refill_pending   : we owe a refill before taking anything new
    //   - load_just_missed      : this cycle's tag compare missed; we're about
    //                             to transition LOAD -> MISS_UPDATE and must
    //                             not overwrite that transition
    // -------------------------------------------------------------------------
    logic  have_incoming_request;
    logic  miss_refill_pending;
    logic  load_just_missed;
    logic  can_accept_new;

    assign have_incoming_request = rd_en || wr_en || flush;
    assign miss_refill_pending   = (curr_inflight.request_type == MISS_UPDATE) && !ud_en;
    assign load_just_missed      = (curr_inflight.request_type == LOAD) && tag_miss;
    assign can_accept_new        = have_incoming_request && !miss_refill_pending && !load_just_missed;

    // -------------------------------------------------------------------------
    // Main FSM
    // -------------------------------------------------------------------------
    always_comb begin : fsm_logic
        // Defaults
        next_inflight     = curr_inflight;
        current_set       = curr_inflight.state_data;
        current_addr      = curr_inflight.req_addr;
        read_addr         = curr_inflight.req_addr;

        enable            = 1'b0;
        write             = 1'b0;
        update            = 1'b0;
        int_flush         = 1'b0;
        hit_check         = 1'b0;
        cache_we          = 1'b0;
        mark_dirty        = 1'b0;

        write_data        = '0;
        write_data_valid  = '0;

        read_hit          = 1'b0;
        read_miss         = 1'b0;
        is_eviction       = 1'b0;

        unique case (curr_inflight.request_type)
            LOAD: begin
                hit_check = 1'b1;
                if (tag_hit) begin
                    // Hit: bump metadata, signal hit, return to IDLE.
                    enable        = 1'b1;
                    update        = 1'b1;
                    cache_we      = ~stall && ~cancel;
                    next_inflight = '0;
                    read_hit      = 1'b1;
                end
                else begin
                    // Miss: transition to MISS_UPDATE and wait for refill.
                    read_miss                  = 1'b1;
                    next_inflight.request_type = MISS_UPDATE;
                end
            end

            STORE: begin
                hit_check        = 1'b1;
                enable           = 1'b1;
                write            = ~stall && ~cancel;
                cache_we         = 1'b1;
                mark_dirty       = 1'b1;
                write_data       = curr_inflight.new_data;
                write_data_valid = curr_inflight.word_write_en;
                next_inflight    = '0;
            end

            MISS_UPDATE: begin
                // Waiting for memory_data. When ud_en arrives, write the refill
                // line and report an eviction (if any) to the caller.
                hit_check                  = ud_en;
                enable                     = ud_en;
                write                      = ud_en;
                cache_we                   = ud_en && ~cancel;
                next_inflight              = ud_en ? '0 : curr_inflight;
                write_data                 = memory_data;
                write_data_valid           = memory_data_valid;
                current_addr.block_offset  = '0;          // refill writes the whole block
                is_eviction                = eviction_cond;
            end

            FLUSH: begin
                hit_check     = 1'b1;
                enable        = 1'b1;
                cache_we      = 1'b1;
                int_flush     = 1'b1;
                next_inflight = '0;
            end

            IDLE: begin
                // Nothing in flight; defaults stand.
            end
        endcase

        // Latch a new request if we can. If the new request hits the same set
        // as the one we're processing, forward the just-computed set value so
        // we see our own pending write.
        if (can_accept_new) begin
            if (incoming_addr.index == curr_inflight.req_addr.index
                && ~cancel
                && curr_inflight.request_type != IDLE) begin
                next_inflight.state_data = next_set_data;
            end
            else begin
                next_inflight.state_data = sram_read_set;
            end

            next_inflight.request_type  = rd_en ? LOAD : (wr_en ? STORE : FLUSH);
            next_inflight.req_addr      = incoming_addr;
            next_inflight.new_data      = core_write_data;
            next_inflight.word_write_en = core_write_data_valid;
        end

        // Stall freezes the FSM unless refill data is arriving (refills must
        // drain regardless of stall, otherwise the cache would deadlock).
        if (stall && !ud_en) begin
            next_inflight = curr_inflight;
        end
    end

    always_ff @(posedge clk, negedge rst_l) begin : cache_state_ff
        if (~rst_l)         curr_inflight <= '0;
        else if (cancel)    curr_inflight <= '0;
        else                curr_inflight <= next_inflight;
    end

    // -------------------------------------------------------------------------
    // SRAM instance
    // -------------------------------------------------------------------------
    sram_1r_1w #(
        .NUM_WORDS  (CACHE_DEPTH),
        .WORD_WIDTH ($bits(cache_set_t)),
        .RESET_VAL  (1'b0)
    ) cache_money (
        .clk        (clk),
        .rst_l      (rst_l),
        .we         (cache_we),
        .read_addr  (incoming_addr.index),
        .write_addr (current_addr.index),
        .write_data (next_set_data),
        .read_data  (sram_read_set)
    );

    // -------------------------------------------------------------------------
    // Tag compares (against current_set / current_addr)
    // -------------------------------------------------------------------------
    always_comb begin
        for (int way = 0; way < WAYS; way++) begin
            way_tag_match[way] = (current_set.blocks[way].tag == current_addr.tag);
            way_valid[way]     = |current_set.blocks[way].valid;
            way_block_hit[way] = current_set.blocks[way].valid[current_addr.block_offset]
                                 && way_tag_match[way];
            way_hit[way]       = way_valid[way] && way_tag_match[way];
        end
    end

    // -------------------------------------------------------------------------
    // Tag-compare result (gated by hit_check)
    // -------------------------------------------------------------------------
    always_comb begin
        tag_hit  = 1'b0;
        tag_miss = 1'b0;
        if (hit_check) begin
            tag_hit  =  (|way_block_hit);
            tag_miss = ~(|way_block_hit);
        end
    end

    // -------------------------------------------------------------------------
    // Eviction condition
    // -------------------------------------------------------------------------
    assign eviction_cond = (enable && write)         // a write is happening
                        && (~|way_hit)               // no way matches
                        && (&way_valid)              // all ways are populated
                        && (|current_set.metadata);  // metadata is initialized

    // -------------------------------------------------------------------------
    // Metadata update
    // -------------------------------------------------------------------------
    always_comb begin
        if (enable) begin
            if (int_flush) begin
                next_set_data.metadata = '0;
            end
            else if (update) begin
                // Load hit: bump metadata. Load miss (caught here too): leave alone.
                if (|way_block_hit)
                    next_set_data.metadata = calculate_metadata(current_set.metadata, way_block_hit);
                else
                    next_set_data.metadata = current_set.metadata;
            end
            else begin
                // Write case: always update metadata to reflect the way written.
                next_set_data.metadata = calculate_metadata(current_set.metadata, way_write_enable);
            end
        end
        else begin
            next_set_data.metadata = current_set.metadata;
        end
    end

    // -------------------------------------------------------------------------
    // Per-way write enable
    // -------------------------------------------------------------------------
    always_comb begin
        if (enable && write) begin
            if (|way_hit) begin
                // Tag matches an in-use way: write that way.
                way_write_enable = way_hit;
            end
            else if (&way_valid) begin
                // No tag match, all ways occupied: evict using policy.
                if (|current_set.metadata)
                    way_write_enable = select_eviction_target(current_set.metadata);
                else
                    way_write_enable = WAYS'(1);
            end
            else begin
                // At least one way is free: select the first free way.
                way_write_enable = '0;
                for (int way = 0; way < WAYS; way++) begin
                    if (way_valid[way] == 1'b0) begin
                        way_write_enable[way] = 1'b1;
                        break;
                    end
                end
            end
        end
        else begin
            way_write_enable = '0;
        end
    end

    // -------------------------------------------------------------------------
    // Per-way write-data generator
    // -------------------------------------------------------------------------
    always_comb begin
        for (int way = 0; way < WAYS; way++) begin
            if (int_flush) begin
                // Flush: wipe this way.
                next_set_data.blocks[way].tag   = 'x;
                next_set_data.blocks[way].valid = '0;
                next_set_data.blocks[way].line  = 'x;
                next_set_data.blocks[way].dirty = 1'b0;
            end
            else if (way_write_enable[way]) begin
                if (eviction_cond) begin
                    // Eviction: nuke the line and replace fully.
                    next_set_data.blocks[way].tag   = current_addr.tag;
                    next_set_data.blocks[way].valid = write_data_valid;
                    next_set_data.blocks[way].line  = write_data;
                    next_set_data.blocks[way].dirty = mark_dirty;
                end
                else begin
                    // Fill into a free way OR partial write to an existing line:
                    // merge new words with old based on write_data_valid.
                    // Dirty if a core store touches the line; a refill into a
                    // free way starts clean (ignore the stale dirty bit there).
                    next_set_data.blocks[way].tag   = current_addr.tag;
                    next_set_data.blocks[way].valid = current_set.blocks[way].valid | write_data_valid;
                    next_set_data.blocks[way].dirty = mark_dirty
                        || (way_valid[way] && current_set.blocks[way].dirty);
                    for (int blk = 0; blk < BLOCK_SIZE; blk++) begin
                        next_set_data.blocks[way].line[blk] = write_data_valid[blk]
                            ? write_data[blk]
                            : current_set.blocks[way].line[blk];
                    end
                end
            end
            else begin
                // Way unchanged.
                next_set_data.blocks[way] = current_set.blocks[way];
            end
        end
    end

    // -------------------------------------------------------------------------
    // Read-word mux
    // -------------------------------------------------------------------------
    //need to turn any 0 words into noops in the controller
    always_comb begin
        read_data = '0;
        for (int way = 0; way < WAYS; way++) begin
            if (way_block_hit[way]) begin
                for (int word = 0; word < FETCH_WORDS && (current_addr.block_offset + word) < BLOCK_SIZE; word++) begin
                    read_data[word] = current_set.blocks[way].line[current_addr.block_offset + word];
                end
            end
        end
    end

    // -------------------------------------------------------------------------
    // Evicted-line export
    // -------------------------------------------------------------------------
    always_comb begin
        evicted_line  = '0;
        evicted_addr  = '0;
        evicted_dirty = 1'b0;
        for (int way = 0; way < WAYS; way++) begin
            if (way_write_enable[way] && eviction_cond) begin
                evicted_line  = current_set.blocks[way].line;
                evicted_addr  = {current_set.blocks[way].tag,
                                 current_addr.index,
                                 {BLOCK_OFFSET_BITS{1'b0}}};
                evicted_dirty = current_set.blocks[way].dirty;
            end
        end
    end

    // =========================================================================
    // Policy functions (unchanged from cache2)
    // =========================================================================

    function automatic logic [METADATA_BITS-1:0] calculate_metadata_direct(
        logic [METADATA_BITS-1:0] current_metadata,
        logic [WAYS-1:0]          update_index);
        return '1;
    endfunction

    function automatic logic [METADATA_BITS-1:0] calculate_metadata_mru(
        logic [METADATA_BITS-1:0] current_metadata,
        logic [WAYS-1:0]          update_index);
        // Metadata is the one-hot index of the MRU way.
        return update_index;
    endfunction

    function automatic logic [METADATA_BITS-1:0] calculate_metadata_lru(
        logic [METADATA_BITS-1:0] current_metadata,
        logic [WAYS-1:0]          update_index);

        logic [METADATA_BITS_PER_WAY-1:0]  metadata_array         [WAYS];
        logic [METADATA_BITS_PER_WAY-1:0]  metadata_mux_output;
        logic [METADATA_BITS_PER_WAY-1:0]  updated_metadata_array [WAYS];
        logic [METADATA_BITS-1:0]          updated_metadata;

        // Unpack metadata for easier handling.
        for (int way = 0; way < WAYS; way++)
            metadata_array[way] = current_metadata[METADATA_BITS_PER_WAY*way +: METADATA_BITS_PER_WAY];

        if (current_metadata == '0) begin
            // Initialize: LRU order = way index.
            for (int way = 0; way < WAYS; way++)
                updated_metadata_array[way] = way;
        end
        else begin
            // Find current LRU value of the way being updated.
            metadata_mux_output = '0;
            for (int way = 0; way < WAYS; way++)
                metadata_mux_output |= update_index[way] ? metadata_array[way] : '0;

            // Ways older than the update: age by 1.
            // Ways younger than the update: unchanged.
            // The updated way: reset to 0 (most-recently-used).
            for (int way = 0; way < WAYS; way++) begin
                if      (metadata_array[way] < metadata_mux_output) updated_metadata_array[way] = metadata_array[way] + 1;
                else if (metadata_array[way] > metadata_mux_output) updated_metadata_array[way] = metadata_array[way];
                else                                                updated_metadata_array[way] = 0;
            end
        end

        // Repack for return.
        for (int way = 0; way < WAYS; way++)
            updated_metadata[METADATA_BITS_PER_WAY*way +: METADATA_BITS_PER_WAY] = updated_metadata_array[way];

        return updated_metadata;
    endfunction

    function automatic logic [METADATA_BITS-1:0] calculate_metadata(
        logic [METADATA_BITS-1:0] current_metadata,
        logic [WAYS-1:0]          update_index);
        if      (POLICY == 0) return calculate_metadata_direct(current_metadata, update_index);
        else if (POLICY == 1) return calculate_metadata_lru   (current_metadata, update_index);
        else if (POLICY == 2) return calculate_metadata_mru   (current_metadata, update_index);
        else begin
            $fatal(1, "Unimplemented cache policy %d", POLICY);
            return '0;
        end
    endfunction

    function automatic logic [WAYS-1:0] select_eviction_target_direct(
        logic [METADATA_BITS-1:0] current_metadata);
        return '1;
    endfunction

    function automatic logic [WAYS-1:0] select_eviction_target_mru(
        logic [METADATA_BITS-1:0] current_metadata);
        // Metadata is the one-hot MRU index, which is itself the eviction target.
        return current_metadata;
    endfunction

    function automatic logic [WAYS-1:0] select_eviction_target_lru(
        logic [METADATA_BITS-1:0] current_metadata);
        logic [WAYS-1:0] eviction_target;
        eviction_target = '0;
        for (int way = 0; way < WAYS; way++)
            eviction_target[way] = &current_metadata[METADATA_BITS_PER_WAY*way +: METADATA_BITS_PER_WAY];
        return eviction_target;
    endfunction

    function automatic logic [WAYS-1:0] select_eviction_target(
        logic [METADATA_BITS-1:0] current_metadata);
        if      (POLICY == 0) return select_eviction_target_direct(current_metadata);
        else if (POLICY == 1) return select_eviction_target_lru   (current_metadata);
        else if (POLICY == 2) return select_eviction_target_mru   (current_metadata);
        else begin
            $fatal(1, "Unimplemented eviction policy %d", POLICY);
            return '0;
        end
    endfunction

endmodule : cache3

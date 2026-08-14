// RISC-V Includes
`include "riscv_abi.vh"
`include "riscv_isa.vh"
`include "memory_segments.vh"

// Local Includes
import internal_defines_pkg::*;
`include "parameters.vh"
`include "riscv_commit.vh"

`default_nettype none

module riscv_core_interface (
     input  logic                 clk, rst_l,
     input  logic                 mem_excpt,
     input  logic [3:0] [31:0]    mem_data_load,
     input  logic [29:0]          mem_data_load_addr,
     input  logic                 mem_data_load_valid,

     output logic                 mem_data_load_en,
     output logic                 halted,
     output logic [3:0]           mem_data_store_mask,
     output logic [29:0]          mem_data_addr,
     output logic                 mem_data_stall,
     output logic [31:0]          mem_data_store
`ifdef SIMULATION_18447
     // Commit packets for the verify-trace flow (riscv_commit.vh), driven
     // from the core's retirement seam (see LightningCore). RF_WAYS = 7 of
     // the COMMIT_WAYS_MAX slots are used; the rest stay invalid.
     ,
     output RISCV_Commit::commit_pkt_t [RISCV_Commit::COMMIT_WAYS_MAX-1:0]
                                   commit_pkts
`endif
);

    /* Memory facing controls & data */
    logic [DATA_CACHE_BLOCK_SIZE - 1 : 0][WORD_SIZE - 1 : 0] mem_rsp_data;
    logic                                         mem_rsp_valid;
    logic [ADDRESS_SIZE - 1 : 0 ]                 mem_rsp_addr;
    logic                                         mem_rsp_ready;
    logic                                         mem_rsp_excpt;

    assign mem_rsp_data  = mem_data_load;
    assign mem_rsp_addr  = mem_data_load_addr;
    assign mem_rsp_valid = mem_data_load_valid;
    assign mem_rsp_excpt = mem_excpt;

    // I-side fetch width: words per I-cache response (Lightning fetch group)
    localparam int FETCH_WORDS = DRIS_defs::FETCH_WAYS;

    /////////////////////////////// i cache signals ///////////////////////////////
    logic                                         core_req_we_i;
    logic                                         core_req_re_i;
    logic [ADDRESS_SIZE - 1 : 0]                  core_req_addr_i;
    logic [3:0]                                   core_req_store_mask_i;
    logic [WORD_SIZE - 1 : 0]                     core_req_store_data_i;
    logic                                         core_req_cancel_i;
    logic                                         core_req_stall_mem_i;
    logic [ADDRESS_SIZE - 1 : 0 ]                 core_rsp_addr_i;
    logic [FETCH_WORDS - 1 : 0][WORD_SIZE - 1 : 0] core_rsp_data_i;
    logic                                         core_rsp_data_valid_i;
    logic                                         core_rsp_ready_i;
    logic                                         core_rsp_excpt_i;
    logic                                         mem_req_data_load_en_i;
    logic [3:0]                                   mem_req_store_mask_i;
    logic [ADDRESS_SIZE - 1 : 0 ]                 mem_req_addr_i;
    logic [WORD_SIZE - 1 : 0 ]                    mem_req_store_data_i;
    logic                                         is_eviction_i;
    logic                                         read_hit_i;
    logic                                         read_miss_i;

    /////////////////////////////// d cache signals ///////////////////////////////
    logic                                         core_req_we_d;
    logic                                         core_req_re_d;
    logic [ADDRESS_SIZE - 1 : 0]                  core_req_addr_d;
    logic [3:0]                                   core_req_store_mask_d;
    logic [WORD_SIZE - 1 : 0]                     core_req_store_data_d;
    logic                                         core_req_cancel_d;
    logic                                         core_req_stall_mem_d;
    dris_id_t                                     core_req_id_d;
    ctrl_signals_t                                core_req_ctrl_signals_d;
    logic [ADDRESS_SIZE - 1 : 0 ]                 core_rsp_addr_d;
    logic [WORD_SIZE - 1 : 0 ]                    core_rsp_data_d;
    logic                                         core_rsp_data_valid_d;
    logic                                         core_rsp_ready_d;
    logic                                         core_rsp_excpt_d;
    dris_id_t                                     core_rsp_id_d;
    ctrl_signals_t                                core_rsp_ctrl_signals_d;
    logic                                         mem_req_data_load_en_d;
    logic [3:0]                                   mem_req_store_mask_d;
    logic [ADDRESS_SIZE - 1 : 0 ]                 mem_req_addr_d;
    logic [WORD_SIZE - 1 : 0 ]                    mem_req_store_data_d;
    logic                                         is_eviction_d;
    logic                                         read_hit_d;
    logic                                         read_miss_d;

    // arbitration
    logic choose_d_cache;
    assign choose_d_cache = mem_req_data_load_en_d | (mem_req_store_mask_d !== 4'b0000);

    always_comb begin: cache_to_mem_mux
        if (choose_d_cache) begin
            mem_data_load_en    = mem_req_data_load_en_d;
            mem_data_store_mask = mem_req_store_mask_d;
            mem_data_addr       = mem_req_addr_d;
            mem_data_store      = mem_req_store_data_d;
        end else begin
            mem_data_load_en    = mem_req_data_load_en_i;
            mem_data_store_mask = mem_req_store_mask_i;
            mem_data_addr       = mem_req_addr_i;
            mem_data_store      = mem_req_store_data_i;
        end
    end

    assign mem_data_stall = 1'b0;

    logic i_active, d_active, i_d_conflict;
    assign i_active    = mem_req_data_load_en_i || (mem_req_store_mask_i != 0);
    assign d_active    = mem_req_data_load_en_d || (mem_req_store_mask_d != 0);
    assign i_d_conflict = i_active && d_active;

    LightningCore #(
        .FETCH_WORDS  (FETCH_WORDS),
        .ADDRESS_SIZE (ADDRESS_SIZE)
    ) core_inst (
        .clock               (clk),
        .reset_n             (rst_l),
        .halted,
`ifdef SIMULATION_18447
        .commit_pkts,
`endif
        .core_req_re         (core_req_re_i),
        .core_req_addr       (core_req_addr_i),
        .core_req_cancel     (core_req_cancel_i),
        .core_req_stall_mem  (core_req_stall_mem_i),
        .core_rsp_data       (core_rsp_data_i),
        .core_rsp_addr       (core_rsp_addr_i),
        .core_rsp_data_valid (core_rsp_data_valid_i),
        .core_rsp_ready      (core_rsp_ready_i),
        .core_rsp_excpt      (core_rsp_excpt_i),

        // D-side: driven by the core's MemoryScheduler (was tied off idle
        // while the memory unit did not exist).
        .core_req_re_d         (core_req_re_d),
        .core_req_we_d         (core_req_we_d),
        .core_req_addr_d       (core_req_addr_d),
        .core_req_store_mask_d (core_req_store_mask_d),
        .core_req_store_data_d (core_req_store_data_d),
        .core_req_cancel_d     (core_req_cancel_d),
        .core_req_stall_mem_d  (core_req_stall_mem_d),
        .core_req_ctrl_signals_d (core_req_ctrl_signals_d),
        .core_req_id_d         (core_req_id_d),
        .core_rsp_data_d       (core_rsp_data_d),
        .core_rsp_addr_d       (core_rsp_addr_d),
        .core_rsp_data_valid_d (core_rsp_data_valid_d),
        .core_rsp_ready_d      (core_rsp_ready_d),
        .core_rsp_excpt_d      (core_rsp_excpt_d),
        .core_rsp_id_d         (core_rsp_id_d),
        .core_rsp_ctrl_signals_d (core_rsp_ctrl_signals_d),

        /* Cache-event fan-in for the core's PERF counters. These wires
         * exist here already (the controllers below drive them); the core
         * is the only place with a cycle counter to normalize them
         * against. Same plumbing as riscv_core_interface_inorder. */
        .is_eviction_i         (is_eviction_i),
        .read_hit_i            (read_hit_i),
        .read_miss_i           (read_miss_i),
        .is_eviction_d         (is_eviction_d),
        .read_hit_d            (read_hit_d),
        .read_miss_d           (read_miss_d),
        .choose_d_cache        (choose_d_cache),
        .i_d_conflict          (i_d_conflict)
    );

`ifdef SIMULATION_18447
    /* Watches the fetch address the core hands the I-cache and reports any
     * request outside the loaded program image (tb/ifetch_bounds_check.sv).
     * Reporting only, unless built with +define+IFETCH_BOUNDS_FATAL. */
    ifetch_bounds_check #(
        .ADDRESS_SIZE (ADDRESS_SIZE),
        .CORE_NAME    ("lightning")
    ) ifetch_bounds (
        .clk, .rst_l,
        .core_req_re   (core_req_re_i),
        .core_req_addr (core_req_addr_i)
    );

    /* Idealized I$ residency model (tb/icache_shadow.sv). Classifies every
     * real I$ miss against a cache of the same geometry that never drops a
     * fill, so avoidable misses can be told apart from the cold-miss floor.
     * Inert unless built with PARAMS='+define+ICACHE_SHADOW'. */
    logic [ADDRESS_SIZE-1:0] probe_addr_i;

    icache_shadow #(
        .ADDRESS_SIZE      (ADDRESS_SIZE),
        .INDEX_BITS        (INSTR_CACHE_INDEX_BITS),
        .BLOCK_OFFSET_BITS (INSTR_CACHE_BLOCK_OFFSET_BITS),
        .WAYS              (INSTR_CACHE_WAYS),
        .CORE_NAME         ("lightning")
    ) icache_shadow_i (
        .clk, .rst_l,
        .probe_addr      (probe_addr_i),
        .read_hit        (read_hit_i),
        .read_miss       (read_miss_i),
        .is_eviction     (is_eviction_i),
        .core_req_cancel (core_req_cancel_i)
    );

    /* I-side request-stream occupancy (tb/ifetch_inflight.sv). Compare the
     * "ready but no request" line against the inorder core's, which is 0 by
     * construction. Inert unless built with PARAMS='+define+IFETCH_INFLIGHT'. */
    ifetch_inflight #(
        .CORE_NAME ("lightning")
    ) ifetch_inflight_i (
        .clk, .rst_l,
        .core_req_re         (core_req_re_i),
        .core_rsp_ready      (core_rsp_ready_i),
        .core_rsp_data_valid (core_rsp_data_valid_i),
        .core_req_cancel     (core_req_cancel_i),
        .halted
    );
`endif

    // i-cache fixed signals (request/cancel now come from the core's IIU)
    assign core_req_we_i         = 1'b0;
    assign core_req_store_mask_i = 4'b0000;
    assign core_req_store_data_i = 32'h0;
    assign mem_req_store_mask_i  = 4'b0000;
    assign mem_req_store_data_i  = 32'h0;

    cache_controller2 #(
        .INDEX_BITS         (INSTR_CACHE_INDEX_BITS),
        .BLOCK_OFFSET_BITS  (INSTR_CACHE_BLOCK_OFFSET_BITS),
        .BLOCK_SIZE         (INSTR_CACHE_BLOCK_SIZE),
        .WAYS               (INSTR_CACHE_WAYS),
        .WORD_SIZE          (WORD_SIZE),
        .FETCH_WORDS        (FETCH_WORDS),
        .ADDRESS_SIZE       (ADDRESS_SIZE),
        .POLICY             (INSTR_CACHE_POLICY)
    ) tony (
        .clk, .rst_l,
        .core_req_we            (core_req_we_i),
        .core_req_re            (core_req_re_i),
        .core_req_addr          (core_req_addr_i),
        .core_req_store_mask    (core_req_store_mask_i),
        .core_req_store_data    (core_req_store_data_i),
        .core_req_cancel        (core_req_cancel_i),
        .core_req_stall_mem     (core_req_stall_mem_i),
        /* I-cache requests carry neither an ID nor control signals, and the
         * I-side never connects core_rsp_id, so these are pure tie-offs.
         * Sized with '0 rather than 6'hF / 'h0: those were narrower and wider
         * than dris_id_t / ctrl_signals_t respectively, which simulators
         * silently zero-extend or truncate but DC rejects outright (LINK-3).
         * '0 also stays correct if LTG_DRIS_ENTRIES changes dris_id_t's
         * width, which a literal cannot. */
        .core_req_id            ('0),
        .core_req_ctrl_signals  ('0),
        .core_rsp_addr          (core_rsp_addr_i),
        .core_rsp_data          (core_rsp_data_i),
        .core_rsp_data_valid    (core_rsp_data_valid_i),
        .core_rsp_ready         (core_rsp_ready_i),
        .core_rsp_excpt         (core_rsp_excpt_i),
        .core_rsp_ctrl_signals  (), // i-cache responses don't have control signals
        .core_rsp_id            (), // i-cache responses don't have an ID
        .mem_rsp_data           (mem_rsp_data),
        .mem_rsp_valid          (mem_rsp_valid),
        .mem_rsp_addr           (mem_rsp_addr),
        .mem_rsp_ready          (~choose_d_cache),
        .mem_rsp_excpt          (mem_rsp_excpt),
        .mem_req_data_load_en   (mem_req_data_load_en_i),
        .mem_req_store_mask     (),
        .mem_req_addr           (mem_req_addr_i),
        .mem_req_store_data     (),
        .is_eviction            (is_eviction_i),
        .read_hit               (read_hit_i),
        .read_miss              (read_miss_i)
`ifdef SIMULATION_18447
        ,
        .probe_addr             (probe_addr_i)
`endif
    );

    cache_controller2 #(
        .INDEX_BITS         (DATA_CACHE_INDEX_BITS),
        .BLOCK_OFFSET_BITS  (DATA_CACHE_BLOCK_OFFSET_BITS),
        .BLOCK_SIZE         (DATA_CACHE_BLOCK_SIZE),
        .WAYS               (DATA_CACHE_WAYS),
        .WORD_SIZE          (WORD_SIZE),
        .ADDRESS_SIZE       (ADDRESS_SIZE),
        .POLICY             (DATA_CACHE_POLICY)
    ) tony_d (
        .clk, .rst_l,
        .core_req_we            (core_req_we_d),
        .core_req_re            (core_req_re_d),
        .core_req_addr          (core_req_addr_d),
        .core_req_store_mask    (core_req_store_mask_d),
        .core_req_store_data    (core_req_store_data_d),
        .core_req_cancel        (core_req_cancel_d),
        .core_req_stall_mem     (core_req_stall_mem_d),
        .core_req_id            (core_req_id_d),
        .core_req_ctrl_signals  (core_req_ctrl_signals_d),
        .core_rsp_addr          (core_rsp_addr_d),
        .core_rsp_data          (core_rsp_data_d),
        .core_rsp_data_valid    (core_rsp_data_valid_d),
        .core_rsp_ready         (core_rsp_ready_d),
        .core_rsp_excpt         (core_rsp_excpt_d),
        .core_rsp_id            (core_rsp_id_d),
        .core_rsp_ctrl_signals  (core_rsp_ctrl_signals_d),
        .mem_rsp_data           (mem_rsp_data),
        .mem_rsp_valid          (mem_rsp_valid),
        .mem_rsp_addr           (mem_rsp_addr),
        .mem_rsp_ready          (choose_d_cache),
        .mem_rsp_excpt          (mem_rsp_excpt),
        .mem_req_data_load_en   (mem_req_data_load_en_d),
        .mem_req_store_mask     (mem_req_store_mask_d),
        .mem_req_addr           (mem_req_addr_d),
        .mem_req_store_data     (mem_req_store_data_d),
        .is_eviction            (is_eviction_d),
        .read_hit               (read_hit_d),
        .read_miss              (read_miss_d)
`ifdef SIMULATION_18447
        ,
        .probe_addr             ()
`endif
    );

endmodule: riscv_core_interface

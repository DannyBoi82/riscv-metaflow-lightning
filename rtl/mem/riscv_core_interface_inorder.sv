// RISC-V Includes
`include "riscv_abi.vh"
`include "riscv_isa.vh"
`include "riscv_uarch.vh"
`include "memory_segments.vh"
`include "riscv_commit.vh"

// Local Includes
`include "internal_defines.vh"
`include "parameters.vh"

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
     // Commit packets for the verify-trace flow (riscv_commit.vh); the
     // in-order core retires one instruction per cycle in slot 0.
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

    /////////////////////////////// i cache signals ///////////////////////////////
    logic                                         core_req_we_i;
    logic                                         core_req_re_i;
    logic [ADDRESS_SIZE - 1 : 0]                  core_req_addr_i;
    logic [3:0]                                   core_req_store_mask_i;
    logic [WORD_SIZE - 1 : 0]                     core_req_store_data_i;
    logic                                         core_req_cancel_i;
    logic                                         core_req_stall_mem_i;
    logic [ADDRESS_SIZE - 1 : 0 ]                 core_rsp_addr_i;
    logic [WORD_SIZE - 1 : 0 ]                    core_rsp_data_i;
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
    /* The class seam arbitrates I/D combinationally (core_req_re_d /
     * choose_d_cache -> mem_rsp_ready -> controller -> mem_req_* -> back) —
     * a false loop for Verilator's per-vector analysis, same species as
     * fifo.sv (see porting log). Behavior blessed by the lab4b-vl rig and
     * the full inorder asm regression. Inline waivers because v5.048
     * ignores lint.vlt -file waivers for this file (known quirk). */
    // verilator lint_off UNOPTFLAT
    logic                                         core_req_re_d;
    // verilator lint_on UNOPTFLAT
    logic [ADDRESS_SIZE - 1 : 0]                  core_req_addr_d;
    logic [3:0]                                   core_req_store_mask_d;
    logic [WORD_SIZE - 1 : 0]                     core_req_store_data_d;
    logic                                         core_req_cancel_d;
    logic                                         core_req_stall_mem_d;
    logic [ADDRESS_SIZE - 1 : 0 ]                 core_rsp_addr_d;
    logic [WORD_SIZE - 1 : 0 ]                    core_rsp_data_d;
    logic                                         core_rsp_data_valid_d;
    logic                                         core_rsp_ready_d;
    logic                                         core_rsp_excpt_d;
    logic                                         mem_req_data_load_en_d;
    logic [3:0]                                   mem_req_store_mask_d;
    logic [ADDRESS_SIZE - 1 : 0 ]                 mem_req_addr_d;
    logic [WORD_SIZE - 1 : 0 ]                    mem_req_store_data_d;
    logic                                         is_eviction_d;
    logic                                         read_hit_d;
    logic                                         read_miss_d;

    /////////////////////////////// core signals ///////////////////////////////
    logic                                         correct_branch_prediction;
    logic                                         flushing;

    // arbitration (UNOPTFLAT: see the core_req_re_d note above)
    // verilator lint_off UNOPTFLAT
    logic choose_d_cache;
    // verilator lint_on UNOPTFLAT
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

`ifdef SIMULATION_18447
    /* The core's packet array is SUPERSCALAR_WAYS wide; pad it out to the
     * fixed COMMIT_WAYS_MAX interface width (unused slots stay invalid). */
    RISCV_Commit::commit_pkt_t [RISCV_UArch::SUPERSCALAR_WAYS-1:0]
        core_commit_pkts;

    always_comb begin : commit_pkt_padding
        commit_pkts = '0;
        for (int i = 0; i < RISCV_UArch::SUPERSCALAR_WAYS; i++)
            commit_pkts[i] = core_commit_pkts[i];
    end : commit_pkt_padding
`endif

    riscv_core core_inst (
`ifdef SIMULATION_18447
        .commit_pkts            (core_commit_pkts),
`endif
        .clk, .rst_l, .halted,
        .instr_mem_excpt        (core_rsp_excpt_i),
        .data_mem_excpt         (core_rsp_excpt_d),
        .instr                  (core_rsp_data_i),
        .data_load              (core_rsp_data_d),
        .data_load_en           (core_req_re_d),
        .data_store_mask        (core_req_store_mask_d),
        .data_store             (core_req_store_data_d),
        .instr_addr             (core_req_addr_i),
        .data_addr              (core_req_addr_d),
        .is_eviction_i,
        .read_hit_i,
        .read_miss_i,
        .is_eviction_d,
        .read_hit_d,
        .read_miss_d,
        .choose_d_cache,
        .i_d_conflict,
        .instr_stall            (core_req_stall_mem_i),
        .data_stall             (core_req_stall_mem_d),
        .instr_valid            (core_rsp_data_valid_i),
        .data_valid             (core_rsp_data_valid_d),
        .i_cache_ready          (core_rsp_ready_i),
        .d_cache_ready          (core_rsp_ready_d),
        .correct_branch_prediction,
        .flushing
    );

    // i-cache fixed signals
    assign core_req_we_i         = 1'b0;
    assign core_req_store_mask_i = 4'b0000;
    assign core_req_store_data_i = 32'h0;
    assign mem_req_store_mask_i  = 4'b0000;
    assign mem_req_store_data_i  = 32'h0;
    assign core_req_cancel_i     = ~correct_branch_prediction;
    assign core_req_re_i         = core_rsp_ready_i;

    // d-cache fixed signals
    assign core_req_we_d         = (core_req_store_mask_d != 4'b0000);
    assign core_req_cancel_d     = 1'b0;

    cache_controller_ref #(
        .INDEX_BITS         (INSTR_CACHE_INDEX_BITS),
        .BLOCK_OFFSET_BITS  (INSTR_CACHE_BLOCK_OFFSET_BITS),
        .BLOCK_SIZE         (INSTR_CACHE_BLOCK_SIZE),
        .WAYS               (INSTR_CACHE_WAYS),
        .WORD_SIZE          (WORD_SIZE),
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
        .core_rsp_addr          (core_rsp_addr_i),
        .core_rsp_data          (core_rsp_data_i),
        .core_rsp_data_valid    (core_rsp_data_valid_i),
        .core_rsp_ready         (core_rsp_ready_i),
        .core_rsp_excpt         (core_rsp_excpt_i),
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
    );

    cache_controller_ref #(
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
        .core_rsp_addr          (core_rsp_addr_d),
        .core_rsp_data          (core_rsp_data_d),
        .core_rsp_data_valid    (core_rsp_data_valid_d),
        .core_rsp_ready         (core_rsp_ready_d),
        .core_rsp_excpt         (core_rsp_excpt_d),
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
    );

endmodule: riscv_core_interface
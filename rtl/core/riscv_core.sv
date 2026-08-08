/**
 * riscv_core.sv
 *
 * RISC-V 32-bit Processor
 *
 * ECE 18-447
 * Carnegie Mellon University
 *
 * Top-level core. Each cycle, fetches the next instruction, executes it, and
 * updates architectural state (regfile, memory). 8-stage pipeline:
 *
 *   F1 -> F2 -> F3 -> D -> E -> M1 -> M2 -> W
 *
 * F1..F3 are three fetch stages (covering a 2-cycle I$ and the F1 pipe reg).
 * M1..M2 are two memory stages (covering a 2-cycle D$).
 *
 * Naming convention: <signal>_<stage>, e.g. pc_F1, alu_out_E, ctrl_signals_M1.
 **/

/*----------------------------------------------------------------------------*
 *  You may edit this file and add or change any files in the src directory.  *
 *----------------------------------------------------------------------------*/

`include "riscv_abi.vh"
`include "riscv_isa.vh"
`include "riscv_uarch.vh"
`include "memory_segments.vh"
`include "riscv_commit.vh"

// Control/ALU/immediate types: must be imported per-file (VCS compiles
// each file as a separate compilation unit; see rtl/core/lib.sv).
import internal_defines_pkg::*;

// Trace & perf are simulation-only. Comment out before synthesis / submission.
//`define TRACE
`define PERF

// Either TRACE or PERF needs the per-stage instr/imm tracking signals to
// exist. DEBUG_PIPELINE is the umbrella define for "any debug propagation".
`ifdef TRACE
    `define DEBUG_PIPELINE
`endif
`ifdef PERF
    `ifndef DEBUG_PIPELINE
        `define DEBUG_PIPELINE
    `endif
`endif

`default_nettype none

`define TWO_BIT_PRED

module riscv_core
    (input  logic           clk, rst_l,
     input  logic           instr_mem_excpt, data_mem_excpt,
     input  logic [31:0]    instr, data_load,
     input  logic           instr_valid, data_valid,
     input  logic           i_cache_ready, d_cache_ready,
     // Cache perf-counter inputs (consumed only by the PERF block)
     input  logic           is_eviction_i, read_hit_i, read_miss_i,
     input  logic           is_eviction_d, read_hit_d, read_miss_d,
     input  logic           choose_d_cache,
     input  logic           i_d_conflict,

     output logic           data_load_en, halted,
     output logic [3:0]     data_store_mask,
     output logic [29:0]    instr_addr, data_addr,
     output logic           instr_stall, data_stall,
     output logic [31:0]    data_store,
     output logic           correct_branch_prediction,
     output logic           flushing
`ifdef SIMULATION_18447
     /* Commit packets for the verify-trace flow (see riscv_commit.vh).
      * Simulation-only so synthesis keeps its original interface; the
      * commit plumbing below is dead logic there and gets pruned. */
     ,
     output RISCV_Commit::commit_pkt_t [RISCV_UArch::SUPERSCALAR_WAYS-1:0]
                            commit_pkts
`endif
     );

    import RISCV_ISA::*;
    import RISCV_ABI::ECALL_ARG_HALT;
    import MemorySegments::USER_TEXT_START;
    import RISCV_UArch::SUPERSCALAR_WAYS;

`ifndef SIMULATION_18447
    // Off-simulation stand-in for the ifdef'd port so the commit logic
    // below always elaborates (and then prunes) the same way.
    RISCV_Commit::commit_pkt_t [SUPERSCALAR_WAYS-1:0] commit_pkts;
`endif

    // ====================================================================
    // Pipeline signal declarations (live signals only; debug-only signals
    // are declared further down, inside `ifdef DEBUG_PIPELINE / `ifdef PERF).
    // ====================================================================

    // ---------- Fetch1 ----------
    logic [31:0]    pc_F1, npc_plus4_F1, next_pc_F1;
    logic           stall_F1;
    logic [1:0]     btb_hist_F1;
    logic           hit_F1;             // BTB output (only used downstream by PERF)
    logic           taken_branch_M1;    // BTB output (only used downstream by PERF)

    // ---------- Fetch2 ----------
    logic [31:0]    pc_F2, npc_plus4_F2;
    logic           stall_F2;
    logic [1:0]     btb_hist_F2;

    // ---------- Fetch3 ----------
    logic [31:0]    pc_F3, npc_plus4_F3, instr_F3;
    logic           stall_F3;
    logic [1:0]     btb_hist_F3;

    // ---------- Decode ----------
    logic [31:0]    pc_D, npc_plus4_D, instr_D, instr_D_mux;
    logic [31:0]    se_immediate_D;
    logic [31:0]    rs1_data_D, rs2_data_D;
    logic [31:0]    rs1_data_fwded_D, rs2_data_fwded_D;
    ctrl_signals_t  ctrl_signals_D;
    logic [4:0]     rs1_D, rs2_D, rd_D;
    logic           stall_D;
    logic [1:0]     btb_hist_D;

    // ---------- Execute ----------
    logic [31:0]    pc_E, npc_plus4_E, npc_offset_E;
    logic [31:0]    rs1_data_E, rs2_data_E;
    logic [31:0]    se_immediate_E;
    logic [31:0]    alu_src1_E, alu_src2_E, alu_out_E;
    ctrl_signals_t  ctrl_signals_E;
    logic [4:0]     rd_E;
    logic           bcond_E;
    logic           stall_E;
    logic [1:0]     btb_hist_E;

    // ---------- Memory1 ----------
    // rs1 propagated through the pipeline so syscall (a0) reaches W.
    // rs2 used here for the store-data path (DataMasker).
    logic [31:0]    pc_M1, npc_plus4_M1, npc_offset_M1;
    logic [31:0]    rs1_data_M1, rs2_data_M1;
    logic [31:0]    alu_out_M1;
    ctrl_signals_t  ctrl_signals_M1;
    logic [4:0]     rd_M1;
    logic           bcond_M1;
    logic           stall_M1;
    logic [1:0]     btb_hist_M1;

    // ---------- Memory2 ----------
    // Only the syscall-halt path (rs1_data) and the result/control signals
    // need to propagate; everything else is dead at this stage.
    logic [31:0]    rs1_data_M2;
    logic [31:0]    alu_out_M2;
    ctrl_signals_t  ctrl_signals_M2;
    logic [4:0]     rd_M2;
    logic           stall_M2;

    // ---------- Writeback ----------
    logic [31:0]    rs1_data_W;          // for syscall halt (a0)
    logic [31:0]    alu_out_W;
    logic [31:0]    data_load_W;
    logic [31:0]    rd_data_W;
    ctrl_signals_t  ctrl_signals_W;
    logic [4:0]     rd_W;
    logic           stall_W;

    // ---------- Branch-predictor recovery state ----------
    logic [31:0]    correct_next_pc;
    logic [31:0]    predicted_next_pc;
    logic [31:0]    predicted_next_pc_F2, predicted_next_pc_F3,
                    predicted_next_pc_D,  predicted_next_pc_E,
                    predicted_next_pc_M1;

    // ---------- Stall control ----------
    logic           FD_stall, EMW_stall;

    // ---------- Halt detection ----------
    logic           syscall_halt, exception_halt;
    logic [31:0]    a0_value;

    // ====================================================================
    // Debug-only signals (TRACE / PERF). Synthesized away when both undef.
    // ====================================================================
    // ---------- Commit plumbing (always compiled) ----------
    // Instruction word, PC, and real-instruction valid bit carried to W for
    // commit packet emission (verify-trace). valid_* is set for fetched
    // program instructions and cleared wherever the pipeline manufactures a
    // bubble or a stage holds a stale copy, so exactly one commit fires per
    // architecturally retired instruction. Also used by TRACE/PERF.
    logic [31:0] instr_E, instr_M1, instr_M2, instr_W;
    logic [31:0] pc_M2, pc_W;
    logic        valid_F2, valid_F3, valid_D, valid_E,
                 valid_M1, valid_M2, valid_W;

    // Commit inputs to the register file. This core retires one instruction
    // per cycle, so only slot 0 is ever used; the regfile stays at its
    // default SUPERSCALAR_WAYS width.
    logic        commit_fire;
    logic [SUPERSCALAR_WAYS-1:0]        rf_commit_valid;
    logic [SUPERSCALAR_WAYS-1:0][31:0]  rf_commit_pc, rf_commit_insn;
    RISCV_Commit::commit_mem_t [SUPERSCALAR_WAYS-1:0] rf_commit_mem;

    `ifdef DEBUG
        /* Request payload carried to W for the verify-mem seam. The access
         * itself issues in M1 — these are the values that actually go on the
         * bus, address included: reporting alu_out_W instead would re-derive
         * the address the trace is supposed to be checking, and a corrupted
         * data_addr would go unnoticed as long as loads and stores were
         * corrupted alike. Reporting at W only delays it, and this core's
         * memory ops are already in program order. data_load_W (the raw
         * cache word) is already at W. */
        logic [29:0] data_addr_M2, data_addr_W;
        logic [31:0] data_store_M2, data_store_W;
        logic [3:0]  data_store_mask_M2, data_store_mask_W;
    `endif

    `ifdef DEBUG_PIPELINE
        // Used by TRACE ($display) and PERF (counters).
        logic [31:0] se_immediate_M1, se_immediate_M2, se_immediate_W;
    `endif

    `ifdef PERF
        // Per-stage tracking carried only for performance counters.
        logic [4:0]  rs1_E, rs1_M1, rs1_M2, rs1_W;
        logic        tempstall_E, tempstall_M1, tempstall_M2, tempstall_W;
        logic        hit_F2, hit_F3, hit_D, hit_E, hit_M1, hit_M2, hit_W;
        logic        taken_branch_M2, taken_branch_W;
    `endif

    // ====================================================================
    // FETCH1: PC register and next-PC selection
    // ====================================================================
    adder #($bits(pc_F1)) PCPlus4_Adder
        (.A(pc_F1), .B(32'd4), .cin(1'b0),
         .sum(npc_plus4_F1), .cout());

    register #($bits(pc_F1), USER_TEXT_START) PC_Reg
        (.clk, .rst_l,
         .en(~halted && (~stall_F1 | ~correct_branch_prediction)),
         .clear(1'b0), .D(next_pc_F1), .Q(pc_F1));

    assign instr_addr  = pc_F1[31:2];
    assign next_pc_F1  = correct_branch_prediction ? predicted_next_pc
                                                   : correct_next_pc;

    // Recovery PC computed from the resolved control-flow op in M1.
    always_comb begin
        unique case (ctrl_signals_M1.pc_source)
            PC_uncond, PC_indirect: correct_next_pc = npc_offset_M1;
            PC_cond:                correct_next_pc = bcond_M1 ? npc_offset_M1
                                                               : npc_plus4_M1;
            default:                correct_next_pc = npc_plus4_M1;
        endcase
    end

    // BTB (read in F1, written in M1).
    BTBPredictor predictor (
        .clk, .rst_l,
        .ctrl_signals_write       (ctrl_signals_M1),
        .correct_branch_prediction,
        .btb_hit                  (hit_F1),
        .bcond_write              (bcond_M1),
        .pc_F1,
        .pc_write                 (pc_M1),
        .npc_plus4_F1,
        .npc_offset_write         (npc_offset_M1),
        .predicted_next_pc,
        .read_btb_hist            (btb_hist_F1),
        .write_btb_hist           (btb_hist_M1),
        .taken_branch             (taken_branch_M1));

    // ====================================================================
    // F1 -> F2  (PC register stage 1)
    // ====================================================================
    always_ff @(posedge clk, negedge rst_l) begin: IF1toIF2
        if (~rst_l) begin
            pc_F2        <= 32'd0;
            npc_plus4_F2 <= {28'd0, pc_mispredict_flush};
            valid_F2     <= 1'b0;
        end
        else if (~correct_branch_prediction) begin
            pc_F2        <= {28'd0, pc_mispredict_flush};
            npc_plus4_F2 <= {28'd0, pc_mispredict_flush};
            valid_F2     <= 1'b0;
        end
        else if (~stall_F2) begin
            valid_F2              <= 1'b1;   // F1 always holds a real PC
            pc_F2                 <= pc_F1;
            npc_plus4_F2          <= npc_plus4_F1;
            btb_hist_F2           <= btb_hist_F1;
            predicted_next_pc_F2  <= predicted_next_pc;
            `ifdef PERF
                hit_F2 <= hit_F1;
            `endif
        end
    end

    // ====================================================================
    // F2 -> F3  (PC register stage 2)
    // ====================================================================
    always_ff @(posedge clk, negedge rst_l) begin: IF2toIF3
        if (~rst_l) begin
            pc_F3        <= 32'd0;
            npc_plus4_F3 <= {28'd0, pc_mispredict_flush};
            valid_F3     <= 1'b0;
        end
        else if (~correct_branch_prediction) begin
            pc_F3        <= {28'd0, pc_mispredict_flush};
            npc_plus4_F3 <= {28'd0, pc_mispredict_flush};
            valid_F3     <= 1'b0;
        end
        else if (~stall_F3 & stall_F2) begin
            // F3 is draining but F2 is frozen. Insert a bubble in F3 so the
            // same instruction doesn't get re-latched from the live F2 reg.
            pc_F3        <= {28'd0, pc_stall_bubble};
            npc_plus4_F3 <= {28'd0, pc_stall_bubble};
            valid_F3     <= 1'b0;
        end
        else if (~stall_F3) begin
            valid_F3              <= valid_F2;
            pc_F3                 <= pc_F2;
            npc_plus4_F3          <= npc_plus4_F2;
            btb_hist_F3           <= btb_hist_F2;
            predicted_next_pc_F3  <= predicted_next_pc_F2;
            `ifdef PERF
                hit_F3 <= hit_F2;
            `endif
        end
    end

    // F3: instruction returns from I$. Bubble-tagged PCs squash to NOP.
    assign instr_F3 = (pc_F3[3:0] == pc_mispredict_flush ||
                       pc_F3[3:0] == pc_stall_bubble)
                    ? 32'h00000013     // addi x0, x0, 0  (NOP)
                    : instr;

    // ====================================================================
    // F3 -> D  (decode register)
    // ====================================================================
    always_ff @(posedge clk, negedge rst_l) begin: IF3toID
        if (~rst_l) begin
            pc_D    <= 32'd0;
            instr_D <= 32'h00000013;
            valid_D <= 1'b0;
        end
        else if (~correct_branch_prediction) begin
            pc_D    <= {28'd0, pc_mispredict_flush};
            instr_D <= 32'h00000013;
            valid_D <= 1'b0;
        end
        else if (~stall_D) begin
            valid_D              <= valid_F3;
            pc_D                 <= pc_F3;
            npc_plus4_D          <= npc_plus4_F3;
            instr_D              <= instr_F3;
            btb_hist_D           <= btb_hist_F3;
            predicted_next_pc_D  <= predicted_next_pc_F3;
            `ifdef PERF
                hit_D <= hit_F3;
            `endif
        end
    end

    // Treat zero-instruction (uninitialized memory) as a NOP.
    assign instr_D_mux = (instr_D == 32'd0) ? 32'h00000013 : instr_D;

    // ====================================================================
    // DECODE: control-signal generation, immediate gen, regfile read
    // ====================================================================
    /* rd/rs1/rs2 outputs intentionally unconnected: the register specifiers
     * are sliced out of the instruction directly below. */
    // verilator lint_off PINMISSING
    riscv_decode Decoder (
        .rst_l,
        .instr        (instr_D_mux),
        .ctrl_signals (ctrl_signals_D));
    // verilator lint_on PINMISSING

    ImmediateGenerator imm_gen (
        .instr     (instr_D_mux),
        .imm_mode  (ctrl_signals_D.imm_mode),
        .immediate (se_immediate_D));

    // For ecall, force rs1 = a0 (x10) so the syscall arg reaches W.
    assign rs1_D = (ctrl_signals_D.syscall) ? 5'd10 : instr_D[19:15];
    assign rs2_D = instr_D[24:20];
    assign rd_D  = instr_D[11:7];

    register_file #(.FORWARD(1)) rf (
        .clk, .rst_l,
        .rd_we        (ctrl_signals_W.rfWrite),
        .rs1          (rs1_D),
        .rs2          (rs2_D),
        .rd           (rd_W),
        .rd_data      (rd_data_W),
        .commit_valid (rf_commit_valid),
        .commit_pc    (rf_commit_pc),
        .commit_insn  (rf_commit_insn),
        .commit_mem   (rf_commit_mem),
        .rs1_data     (rs1_data_D),
        .rs2_data     (rs2_data_D),
        .commit_pkts  (commit_pkts));

    // ====================================================================
    // D -> E  (execute register)
    // ====================================================================
    always_ff @(posedge clk, negedge rst_l) begin: IDtoEX
        if (~rst_l) begin
            ctrl_signals_E <= CTRL_SIGNALS_NOOP;
            valid_E        <= 1'b0;
        end
        else if (~correct_branch_prediction) begin
            pc_E           <= {28'd0, pc_mispredict_flush};
            npc_plus4_E    <= {28'd0, pc_mispredict_flush};
            ctrl_signals_E <= CTRL_SIGNALS_NOOP;
            valid_E        <= 1'b0;
        end
        else if (~stall_D) begin
            valid_E              <= valid_D;
            instr_E              <= instr_D_mux;
            pc_E                 <= pc_D;
            npc_plus4_E          <= npc_plus4_D;
            ctrl_signals_E       <= ctrl_signals_D;
            rs1_data_E           <= rs1_data_fwded_D;
            rs2_data_E           <= rs2_data_fwded_D;
            se_immediate_E       <= se_immediate_D;
            rd_E                 <= rd_D;
            btb_hist_E           <= btb_hist_D;
            predicted_next_pc_E  <= predicted_next_pc_D;

            `ifdef PERF
                rs1_E       <= rs1_D;
                tempstall_E <= stall_D;
                hit_E       <= hit_D;
            `endif
        end
        else if (stall_D & ~EMW_stall) begin
            // FD-stall (load-use): inject a bubble into E.
            ctrl_signals_E <= CTRL_SIGNALS_NOOP;
            valid_E        <= 1'b0;
        end
    end

    // Branch-prediction check (M1-resolved vs M1-predicted).
    // Treats already-flushing cycles as "correct" to avoid double-flushing.
    assign correct_branch_prediction =
        (predicted_next_pc_M1 === correct_next_pc) ||
        (ctrl_signals_M1.pc_source === PC_plus4)   ||
        flushing;

    // ====================================================================
    // EXECUTE: branch-target adder, ALU
    // ====================================================================
    // npc_offset_E = (PC or rs1) + imm — JALR uses rs1 as base, others use PC.
    adder #($bits(pc_F1)) NextPCAdder (
        .A    (ctrl_signals_E.pc_source == PC_indirect ? rs1_data_E : pc_E),
        .B    (se_immediate_E),
        .cin  (1'b0),
        .sum  (npc_offset_E),
        .cout ());

    // ALU source muxes
    mux #(2, 32) ALU_Src1_Mux (
        .in  ({rs1_data_E, pc_E}),
        .sel (!ctrl_signals_E.usePC),
        .out (alu_src1_E));

    mux #(2, 32) ALU_Src2_Mux (
        .in  ({rs2_data_E, se_immediate_E}),
        .sel (!ctrl_signals_E.useImm),
        .out (alu_src2_E));

    riscv_alu ALU (
        .alu_src1 (alu_src1_E),
        .alu_src2 (alu_src2_E),
        .alu_op   (ctrl_signals_E.alu_op),
        .alu_out  (alu_out_E));

    assign bcond_E = alu_out_E[0];   // branch comparators write result in bit 0

    // ====================================================================
    // E -> M1  (memory register stage 1)
    // ====================================================================
    always_ff @(posedge clk, negedge rst_l) begin: EXtoMEM1
        if (~rst_l) begin
            ctrl_signals_M1 <= CTRL_SIGNALS_NOOP;
            valid_M1        <= 1'b0;
        end
        else if (~stall_M1 & correct_branch_prediction) begin
            valid_M1              <= valid_E;
            instr_M1              <= instr_E;
            pc_M1                 <= pc_E;
            npc_plus4_M1          <= npc_plus4_E;
            npc_offset_M1         <= npc_offset_E;
            ctrl_signals_M1       <= ctrl_signals_E;
            rs1_data_M1           <= rs1_data_E;
            rs2_data_M1           <= rs2_data_E;
            alu_out_M1            <= alu_out_E;
            rd_M1                 <= rd_E;
            bcond_M1              <= bcond_E;
            btb_hist_M1           <= btb_hist_E;
            predicted_next_pc_M1  <= predicted_next_pc_E;

            `ifdef DEBUG_PIPELINE
                se_immediate_M1  <= se_immediate_E;
            `endif
            `ifdef PERF
                rs1_M1       <= rs1_E;
                tempstall_M1 <= tempstall_E;
                hit_M1       <= hit_E;
            `endif
        end
        else if (~stall_M2) begin
            /* Mispredict-resolution cycle: M2 latched M1's instruction on
             * this edge but M1 did not refill (the enable above is gated by
             * correct_branch_prediction), so M1 now holds a stale copy of
             * the mispredicted control-flow op and will feed it to M2 a
             * second time next cycle. Architecturally invisible (same data
             * rewritten), but it must not commit twice. */
            valid_M1 <= 1'b0;
        end
    end

    // ====================================================================
    // MEMORY1: data-memory request issue (load enable, store mask, store data)
    // ====================================================================
    assign data_load_en = ctrl_signals_M1.memRead & d_cache_ready;
    assign data_addr    = alu_out_M1[31:2];
    assign data_stall   = EMW_stall;

    // Byte offset within the 32-bit word (M1 issues, W aligns the load).
    logic [1:0] byte_offset_M1;
    assign byte_offset_M1 = alu_out_M1[1:0];

    DataStoreMaskGenerator storemask (
        .ctrl_signals    (ctrl_signals_M1),
        .byte_offset     (byte_offset_M1),
        .data_store_mask);

    DataMasker datastoremask (
        .ldst_mode   (ctrl_signals_M1.ldst_mode),
        .byte_offset (byte_offset_M1),
        .rs2_data    (rs2_data_M1),
        .data_store);

    // ====================================================================
    // M1 -> M2  (memory register stage 2)
    // ====================================================================
    always_ff @(posedge clk, negedge rst_l) begin: MEM1toMEM2
        if (~rst_l) begin
            ctrl_signals_M2 <= CTRL_SIGNALS_NOOP;
            valid_M2        <= 1'b0;
        end
        else if (~stall_M2) begin
            valid_M2        <= valid_M1;
            instr_M2        <= instr_M1;
            pc_M2           <= pc_M1;
            ctrl_signals_M2 <= ctrl_signals_M1;
            rs1_data_M2     <= rs1_data_M1;
            alu_out_M2      <= alu_out_M1;
            rd_M2           <= rd_M1;

            `ifdef DEBUG
                data_addr_M2       <= data_addr;
                data_store_M2      <= data_store;
                data_store_mask_M2 <= data_store_mask;
            `endif
            `ifdef DEBUG_PIPELINE
                se_immediate_M2  <= se_immediate_M1;
            `endif
            `ifdef PERF
                rs1_M2          <= rs1_M1;
                tempstall_M2    <= stall_M1;
                hit_M2          <= hit_M1;
                taken_branch_M2 <= taken_branch_M1;
            `endif
        end
    end

    // Memory operations issue in M1; M2 only exists to wait for the load.
    assign data_load_W = data_load;

    // ====================================================================
    // M2 -> W  (writeback register)
    // ====================================================================
    always_ff @(posedge clk, negedge rst_l) begin: MEM2toWB
        if (~rst_l) begin
            ctrl_signals_W <= CTRL_SIGNALS_NOOP;
            valid_W        <= 1'b0;
        end
        else if (~stall_W) begin
            valid_W        <= valid_M2;
            instr_W        <= instr_M2;
            pc_W           <= pc_M2;
            ctrl_signals_W <= ctrl_signals_M2;
            rs1_data_W     <= rs1_data_M2;
            alu_out_W      <= alu_out_M2;
            rd_W           <= rd_M2;

            `ifdef DEBUG
                data_addr_W       <= data_addr_M2;
                data_store_W      <= data_store_M2;
                data_store_mask_W <= data_store_mask_M2;
            `endif
            `ifdef DEBUG_PIPELINE
                se_immediate_W  <= se_immediate_M2;
            `endif
            `ifdef PERF
                rs1_W          <= rs1_M2;
                tempstall_W    <= stall_M2;
                hit_W          <= hit_M2;
                taken_branch_W <= taken_branch_M2;
            `endif
        end
    end

    // ====================================================================
    // WRITEBACK: select between ALU result and aligned load data
    // ====================================================================
    logic [1:0] byte_offset_W;
    assign byte_offset_W = alu_out_W[1:0];

    RDDataMux datamux (
        .ctrl_signals (ctrl_signals_W),
        .byte_offset  (byte_offset_W),
        .data_load    (data_load_W),
        .alu_out      (alu_out_W),
        .rd_data      (rd_data_W));

    // ====================================================================
    // COMMIT (verify-trace seam): the instruction in W retires on the clock
    // edge where W refills (~stall_W) — the same edge its regfile write
    // lands, so the sampled packet and the write are always consistent. The
    // valid chain guarantees exactly one packet per architecturally retired
    // instruction (no bubbles, no stale mispredict copies). The halting
    // instruction commits on the halt edge even if stall_W is high (a
    // younger memory op can hold EMW_stall): the refsim's step loop
    // executes the halting ecall, so both traces must end with its line —
    // and simulation $finishes on that edge, so it can't fire twice.
    // ====================================================================
    assign commit_fire = valid_W & (~stall_W | halted);

    always_comb begin
        rf_commit_valid    = '0;
        rf_commit_pc       = '0;
        rf_commit_insn     = '0;
        rf_commit_valid[0] = commit_fire;
        rf_commit_pc[0]    = pc_W;
        rf_commit_insn[0]  = instr_W;
    end

    // Byte enables of a load, within its containing word: the read-side twin
    // of lib.sv's DataStoreMaskGenerator, which only handles stores.
    function automatic logic [3:0] load_byte_mask(ldst_mode_t ldst_mode,
            logic [1:0] byte_offset);

        unique case (ldst_mode)
            LDST_W:           return 4'b1111;
            LDST_H, LDST_HU:  return byte_offset[1] ? 4'b1100 : 4'b0011;
            LDST_B, LDST_BU:  return 4'b0001 << byte_offset;
            default:          return 4'b0000;
        endcase
    endfunction: load_byte_mask

    // Byte enables -> bit mask, for zeroing the lanes an access didn't touch.
    function automatic logic [31:0] expand_mask(logic [3:0] byte_mask);
        return {{8{byte_mask[3]}}, {8{byte_mask[2]}},
                {8{byte_mask[1]}}, {8{byte_mask[0]}}};
    endfunction: expand_mask

    /* The memory half of the commit packet (verify-mem, see riscv_commit.vh).
     * Bus values only: the raw cache word masked to the accessed lanes, not
     * the sign-extended value RDDataMux hands the register file — load
     * extension is the register trace's business. */
    always_comb begin
        rf_commit_mem = '0;
`ifdef DEBUG
        if (ctrl_signals_W.memRead) begin
            rf_commit_mem[0].addr  = {data_addr_W, byte_offset_W};
            rf_commit_mem[0].rmask = load_byte_mask(ctrl_signals_W.ldst_mode,
                    byte_offset_W);
            rf_commit_mem[0].rdata = data_load_W
                    & expand_mask(rf_commit_mem[0].rmask);
        end
        else if (ctrl_signals_W.memWrite) begin
            rf_commit_mem[0].addr  = {data_addr_W, byte_offset_W};
            rf_commit_mem[0].wmask = data_store_mask_W;
            rf_commit_mem[0].wdata = data_store_W
                    & expand_mask(data_store_mask_W);
        end
`endif
    end

    // ====================================================================
    // STALL & FLUSH CONTROL
    // ====================================================================
    // A flush "tag" sits in any of F2/F3/D/M1 when we're recovering from a
    // misprediction. Used to gate further mispredicts (see correct_branch_prediction).
    assign flushing =
        (pc_F2[3:0] === pc_mispredict_flush) ||
        (pc_F3[3:0] === pc_mispredict_flush) ||
        (pc_D [3:0] === pc_mispredict_flush) ||
        (pc_M1[3:0] === pc_mispredict_flush);

    StallFDController staller (
        .ctrl_signals_D, .ctrl_signals_E,
        .ctrl_signals_M1, .ctrl_signals_M2, .ctrl_signals_W,
        .rs1_D, .rs2_D,
        .rd_E, .rd_M1, .rd_M2, .rd_W,
        .instr_valid,
        .stall (FD_stall));

    // EMW_stall: hold the back half of the pipe when D$ is busy or when a
    // load reaches W without its data being valid yet.
    always_comb begin
        EMW_stall = 1'b0;
        if ((ctrl_signals_M1.memRead | ctrl_signals_M1.memWrite) & ~d_cache_ready)
            EMW_stall = 1'b1;
        else if (ctrl_signals_W.memRead & ~data_valid)
            EMW_stall = 1'b1;
    end

    // Front-half stall: load-use, EMW back-pressure, or I$ not ready.
    // (See the per-case truth table below; default is "no stall".)
    always_comb begin
        {instr_stall, stall_F1, stall_F2, stall_F3, stall_D} = 5'b00000;

        if (FD_stall | EMW_stall | ~d_cache_ready) begin
            // Back-pressure: freeze the entire front half.
            {instr_stall, stall_F1, stall_F2, stall_F3, stall_D} = 5'b11111;
        end
        else if (~instr_valid & ~i_cache_ready) begin
            // Waiting on both: freeze front-half (request still in flight).
            {instr_stall, stall_F1, stall_F2, stall_F3, stall_D} = 5'b11111;
        end
        else if (instr_valid & ~i_cache_ready) begin
            // Instr is back but cache is busy: hold F1/F2 only.
            instr_stall = 1'b1;
            stall_F1    = 1'b1;
            stall_F2    = 1'b1;
        end
        // Remaining cases (~instr_valid &  i_cache_ready) and
        //                  (instr_valid &  i_cache_ready) need no stall.
    end

    // Back-half stages (E/M1/M2/W) all share EMW_stall.
    assign {stall_E, stall_M1, stall_M2, stall_W} = {4{EMW_stall}};

    // ====================================================================
    // FORWARDING (D-stage bypass)
    // ====================================================================
    ForwardingController fwder (
        .ctrl_signals_D, .ctrl_signals_E,
        .ctrl_signals_M1, .ctrl_signals_M2, .ctrl_signals_W,
        .rs1_D, .rs2_D,
        .rd_E, .rd_M1, .rd_M2, .rd_W,
        .alu_out_E, .alu_out_M1, .alu_out_M2, .alu_out_W,
        .rd_data_W,
        .rs1_data_D, .rs2_data_D,
        .rs1_data_fwded (rs1_data_fwded_D),
        .rs2_data_fwded (rs2_data_fwded_D));

    // ====================================================================
    // HALT detection (syscalls and exceptions)
    // ====================================================================
    assign a0_value       = rs1_data_W;     // rs1 was forced to x10 on syscall
    assign syscall_halt   = ctrl_signals_W.syscall && (a0_value == ECALL_ARG_HALT);
    assign exception_halt = instr_mem_excpt | data_mem_excpt
                          | ctrl_signals_W.illegal_instr;
    assign halted         = rst_l & (syscall_halt | exception_halt);

    // ====================================================================
    // SIMULATION-ONLY: exception/halt reporting
    // ====================================================================
`ifdef SIMULATION_18447
    always_ff @(posedge clk) begin
        if (rst_l && instr_mem_excpt)
            $display("Instruction memory exception at address 0x%x.", instr_addr << 2);
        if (rst_l && data_mem_excpt)
            $display("Data memory exception at address 0x%x.", data_addr << 2);
        if (rst_l && syscall_halt)
            $display("ECALL invoked with halt argument. Terminating simulation at 0x%x.", pc_F1);
    end
`endif

    // ====================================================================
    // PERFORMANCE COUNTERS (PERF only)
    // ====================================================================
`ifdef PERF
    // ----- Cycle / instruction counts -----
    int elapsed_cycles;
    int total_instructions;
    int total_fetch_instructions;
    int total_stall_cycles;
    int stall_num_FD, stall_num_EMW;

    // ----- Instruction-type counts -----
    int ALU_inst_num, Lx_inst_num, Sx_inst_num;

    // ----- Branch counters indexed by [backward][taken][hit][rewind] -----
    //   backward: se_immediate_W < 0  (i.e. loop branch)
    //   taken:    taken_branch_W
    //   hit:      hit_W (BTB hit at fetch)
    //   rewind:   ~correct_branch_prediction (we mispredicted)
    int branch_cnt[2][2][2][2];
    int flush_cycles;

    // ----- JAL/JALR counters indexed by [is_link][hit][rewind] -----
    int jal_cnt [2][2][2];   // JAL  : is_link = (rd  == ra)
    int jalr_cnt[2][2][2];   // JALR : is_link = (rs1 == ra)

    // ----- Cache counters -----
    int eviction_i, hits_i, miss_i;
    int eviction_d, hits_d, miss_d;
    int num_i_cache, num_d_cache, num_conflicts;

    // ----- Stall-run-length histogram (capped at 4) -----
    int stall_categories[5];
    int curr_stall_cycles;
    int prev_stall;

    // ----- I$ stall breakdown (mutually exclusive with FD/EMW stalls) -----
    int stall_icache_case1;   // ~instr_valid & ~i_cache_ready
    int stall_icache_case2;   // ~instr_valid &  i_cache_ready
    int stall_icache_case3;   //  instr_valid & ~i_cache_ready

    // --------------------------------------------------------------------
    // Pretty-printer (called on syscall halt by both PERF and TRACE blocks)
    // --------------------------------------------------------------------
    task automatic print_perf_metrics();
        int b, t, h, r;
        $display("\t\t PERFORMANCE METRICS:");
        $display("\t total cycles:              %0d", elapsed_cycles);
        $display("\t total fetch cycles:        %0d", total_fetch_instructions);
        $display("\t total stall cycles:        %0d", total_stall_cycles);
        $display("\t  stall for FD:             %0d", stall_num_FD);
        $display("\t  stall for EMW:            %0d", stall_num_EMW);
        $display("\t  I$ stall (~valid,~ready): %0d", stall_icache_case1);
        $display("\t  I$ stall (~valid, ready): %0d", stall_icache_case2);
        $display("\t  I$ stall ( valid,~ready): %0d", stall_icache_case3);
        $display("\t  flush cycles:             %0d", flush_cycles);

        $display("\t stall run-length hist:");
        for (int i = 0; i <= 4; i++)
            $display("\t    [%0d]: %0d", i, stall_categories[i]);

        $display("\t Non-Control Flow Types:");
        $display("\t  ALU:    %0d", ALU_inst_num);
        $display("\t  Loads:  %0d", Lx_inst_num);
        $display("\t  Stores: %0d", Sx_inst_num);

        $display("\t Branches (back|taken|hit|rewind):");
        for (b = 0; b < 2; b++)
            for (t = 0; t < 2; t++)
                for (h = 0; h < 2; h++)
                    for (r = 0; r < 2; r++)
                        $display("\t  %0b%0b%0b%0b: %0d",
                                 b, t, h, r, branch_cnt[b][t][h][r]);

        $display("\t JAL (rd=ra|hit|rewind):");
        for (b = 0; b < 2; b++)
            for (h = 0; h < 2; h++)
                for (r = 0; r < 2; r++)
                    $display("\t  %0b%0b%0b: %0d", b, h, r, jal_cnt[b][h][r]);

        $display("\t JALR (rs1=ra|hit|rewind):");
        for (b = 0; b < 2; b++)
            for (h = 0; h < 2; h++)
                for (r = 0; r < 2; r++)
                    $display("\t  %0b%0b%0b: %0d", b, h, r, jalr_cnt[b][h][r]);

        $display("\t Cache Counters:");
        $display("\t  I$ evictions: %0d | hits: %0d | misses: %0d", eviction_i, hits_i, miss_i);
        $display("\t  D$ evictions: %0d | hits: %0d | misses: %0d", eviction_d, hits_d, miss_d);
        $display("\t  I$ accesses:  %0d | D$ accesses: %0d", num_i_cache, num_d_cache);
        $display("\t  I$/D$ conflicts: %0d", num_conflicts);
    endtask

    // --------------------------------------------------------------------
    // Counter update logic
    // --------------------------------------------------------------------
    always_ff @(posedge clk, negedge rst_l) begin: perf_metrics
        if (~rst_l) begin
            elapsed_cycles            <= 0;
            total_instructions        <= 0;
            total_fetch_instructions  <= 0;
            total_stall_cycles        <= 0;
            stall_num_FD              <= 0;
            stall_num_EMW             <= 0;
            ALU_inst_num              <= 0;
            Lx_inst_num               <= 0;
            Sx_inst_num               <= 0;
            eviction_i <= 0; hits_i <= 0; miss_i <= 0;
            eviction_d <= 0; hits_d <= 0; miss_d <= 0;
            num_i_cache <= 0; num_d_cache <= 0; num_conflicts <= 0;
            curr_stall_cycles  <= 0;
            prev_stall         <= 0;
            foreach (branch_cnt[b,t,h,r]) branch_cnt[b][t][h][r] <= 0;
            foreach (jal_cnt  [b,h,r])    jal_cnt  [b][h][r]     <= 0;
            foreach (jalr_cnt [b,h,r])    jalr_cnt [b][h][r]     <= 0;
            foreach (stall_categories[i]) stall_categories[i]    <= 0;
            stall_icache_case1 <= 0;
            stall_icache_case2 <= 0;
            stall_icache_case3 <= 0;
            flush_cycles       <= 0;
        end
        else if (~halted) begin
            elapsed_cycles <= elapsed_cycles + 1;

            // Fetch throughput
            if (~stall_F2)
                total_fetch_instructions <= total_fetch_instructions + 1;

            // Retired instructions (no bubbles, no wrong-path)
            if (ctrl_signals_W != CTRL_SIGNALS_NOOP &&
                instr_W != 32'h00000013 &&
                correct_branch_prediction)
                total_instructions <= total_instructions + 1;

            // Stall tracking
            if (tempstall_W)                  total_stall_cycles <= total_stall_cycles + 1;
            if (FD_stall)                     stall_num_FD       <= stall_num_FD  + 1;
            if (EMW_stall | ~d_cache_ready)   stall_num_EMW      <= stall_num_EMW + 1;

            // I$ stall cases (only counted when not already stalling for FD/EMW)
            if (~FD_stall & ~EMW_stall) begin
                if (~instr_valid & ~i_cache_ready) stall_icache_case1 <= stall_icache_case1 + 1;
                if (~instr_valid &  i_cache_ready) stall_icache_case2 <= stall_icache_case2 + 1;
                if ( instr_valid & ~i_cache_ready) stall_icache_case3 <= stall_icache_case3 + 1;
            end

            if (flushing) flush_cycles <= flush_cycles + 1;

            // Stall run-length histogram
            if (~prev_stall & tempstall_W)
                curr_stall_cycles <= 1;
            else if (prev_stall & tempstall_W)
                curr_stall_cycles <= curr_stall_cycles + 1;
            else if (prev_stall & ~tempstall_W) begin
                stall_categories[curr_stall_cycles < 4 ? curr_stall_cycles : 4]
                    <= stall_categories[curr_stall_cycles < 4 ? curr_stall_cycles : 4] + 1;
                curr_stall_cycles <= 0;
            end
            else begin
                stall_categories[0] <= stall_categories[0] + 1;
            end
            prev_stall <= tempstall_W;

            // Instruction type (W stage)
            if (ctrl_signals_W.pc_source == PC_plus4) begin
                if      (ctrl_signals_W.mem2RF)   Lx_inst_num  <= Lx_inst_num  + 1;
                else if (ctrl_signals_W.memWrite) Sx_inst_num  <= Sx_inst_num  + 1;
                else                              ALU_inst_num <= ALU_inst_num + 1;
            end

            // Branch counters
            if (ctrl_signals_W.pc_source == PC_cond) begin
                automatic logic bwd = se_immediate_W[31];
                branch_cnt[bwd][taken_branch_W][hit_W][~correct_branch_prediction]
                    <= branch_cnt[bwd][taken_branch_W][hit_W][~correct_branch_prediction] + 1;
            end

            // JAL counters
            if (ctrl_signals_W.pc_source == PC_uncond) begin
                jal_cnt[rd_W == 5'd1][hit_W][~correct_branch_prediction]
                    <= jal_cnt[rd_W == 5'd1][hit_W][~correct_branch_prediction] + 1;
            end

            // JALR counters
            if (ctrl_signals_W.pc_source == PC_indirect) begin
                jalr_cnt[rs1_W == 5'd1][hit_W][~correct_branch_prediction]
                    <= jalr_cnt[rs1_W == 5'd1][hit_W][~correct_branch_prediction] + 1;
            end

            // Cache counters
            if (is_eviction_i) eviction_i <= eviction_i + 1;
            if (read_hit_i)    hits_i     <= hits_i     + 1;
            if (read_miss_i)   miss_i     <= miss_i     + 1;
            if (is_eviction_d) eviction_d <= eviction_d + 1;
            if (read_hit_d)    hits_d     <= hits_d     + 1;
            if (read_miss_d)   miss_d     <= miss_d     + 1;
            if (choose_d_cache) num_d_cache   <= num_d_cache   + 1;
            else                num_i_cache   <= num_i_cache   + 1;
            if (i_d_conflict)   num_conflicts <= num_conflicts + 1;
        end
    end

    // Print on halt (TRACE block calls the same task; both gated on syscall).
    always_ff @(posedge clk) begin
        if (ctrl_signals_W.syscall)
            print_perf_metrics();
    end
`endif /* PERF */

    // ====================================================================
    // CYCLE-BY-CYCLE TRACE (TRACE only; very slow, comment out before submit)
    // ====================================================================
`ifdef SIMULATION_18447
`ifdef TRACE
    opcode_t           opcode;
    funct7_t           funct7;
    rtype_funct3_t     rtype_funct3;
    itype_int_funct3_t itype_int_funct3;
    logic [4:0]        rs1_W_trace, rs2_W_trace;

    assign opcode           = opcode_t'(instr_W[6:0]);
    assign funct7           = funct7_t'(instr_W[31:25]);
    assign rtype_funct3     = rtype_funct3_t'(instr_W[14:12]);
    assign itype_int_funct3 = itype_int_funct3_t'(instr_W[14:12]);

    // Reuse PERF's rs1_W when both are on; otherwise rebuild here.
    `ifdef PERF
        assign rs1_W_trace = rs1_W;
    `else
        assign rs1_W_trace = (ctrl_signals_W.syscall) ? 5'd10 : instr_W[19:15];
    `endif
    assign rs2_W_trace = instr_W[24:20];

    always_ff @(posedge clk) begin
        if (rst_l) begin
            $display({"\n", {80{"-"}}});
            $display("- Simulation Cycle %0d", $time);
            $display({{80{"-"}}, "\n"});

            $display("\tPC: 0x%x", pc_W);
            $display("\tInstruction: 0x%x\n", instr_W);

            $display("\tInstruction Memory Exception: %0b", instr_mem_excpt);
            $display("\tData Memory Exception:        %0b", data_mem_excpt);
            $display("\tIllegal Instruction Exception: %0b", ctrl_signals_W.illegal_instr);
            $display("\tHalted: %0b\n", halted);

            $display("\tOpcode: 0x%02x (%s)", opcode, opcode.name);
            $display("\tFunct3: 0x%01x (%s | %s)",
                     rtype_funct3, rtype_funct3.name, itype_int_funct3.name);
            $display("\tFunct7: 0x%02x (%s)", funct7, funct7.name);
            $display("\trs1: %0d", rs1_W_trace);
            $display("\trs2: %0d", rs2_W_trace);
            $display("\trd:  %0d | data %x", rd_W, rd_data_W);
            $display("\tSign Extended Immediate: %0d", se_immediate_W);

            `ifdef PERF
                if (syscall_halt) print_perf_metrics();
            `endif
        end
    end
`endif /* TRACE */
`endif /* SIMULATION_18447 */

endmodule: riscv_core
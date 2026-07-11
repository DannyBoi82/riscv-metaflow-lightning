`default_nettype none

`include "riscv_commit.vh"

import DRIS_defs::*;
import RISCV_ISA::*;
import RISCV_UArch::*;  // Import microarchitecture parameters and definitions
import internal_defines_pkg::*;     // Control signals struct, ALU ops

/**
 * LightningCore — top of the Metaflow Lightning OoO core.
 *
 * Instantiates and wires the DRIS, the IIU (fetch/rename front end +
 * branch shelf), the Scheduler, the Sane State Controller, the register
 * file (447src), and the execute ways (per-way riscv_alu + next-PC
 * block, per TODO-IIU.md Phase 4).
 *
 * The issue packets register at the I/E boundary (issue_pkts_reg), so
 * execute is a real pipeline stage: writebacks land one cycle after
 * issue, and dependents issue two cycles behind their producer (the
 * locker broadcast is one edge later). One issue group is therefore
 * in flight across a mispredict/trap flush. Do NOT clear the register
 * on a flush — instructions older than the mispredicted branch can be
 * in it and must complete or retirement deadlocks. Instead the DRIS
 * drops any writeback whose target entry is no longer valid, so a
 * wrong-path in-flight writeback can't corrupt a reallocated entry.
 *
 * The only external seams are the I-side cache controller
 * (core_req_* / core_rsp_*, owned by the IIU) and halted. The D-side
 * (memory unit + D-cache) is not built yet: loads/stores currently
 * dispatch through the ALUs like everything else, so only memory-free
 * programs produce correct results. The SSC's store-release port
 * (mem_write_valid/mem_write_id) and the DRIS's memory writeback ports
 * are placeholders until the memory unit exists.
 *
 * Instantiated by riscv_core_interface in place of the in-order
 * riscv_core; the D-side controller there is tied off until the
 * memory unit exists.
 */
module LightningCore #(
    parameter int FETCH_WORDS  = DRIS_defs::FETCH_WAYS,
    parameter int EXEC_UNITS   = DRIS_defs::EXECUTE_WAYS,
    parameter int ADDRESS_SIZE = 30
)(
    input  logic clock, reset_n,

    output logic halted,

`ifdef SIMULATION_18447
    /* Commit packets for the verify-trace flow (see riscv_commit.vh).
     * TODO(SSC): only partially populated — the SSC's reg_commits carry
     * neither PC/insn nor non-writing retirements (branches, stores, the
     * halting ecall), so packets fire only for register-writing
     * retirements with pc/insn = 0. That keeps the harness's shadow
     * regfile (and the end-state simulation.reg dump) correct, but
     * verify-trace is unsupported on CORE=lightning until the SSC emits
     * full per-slot retire info. */
    output RISCV_Commit::commit_pkt_t [RISCV_Commit::COMMIT_WAYS_MAX-1:0]
                 commit_pkts,
`endif

    /* ============================================================
     * I-side cache controller (core_req_* / core_rsp_* seam),
     * driven straight through the IIU
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

    localparam int WRITEBACK_PORTS = EXEC_UNITS + DRIS_defs::MEMORY_WRITE_PORTS
                                                + DRIS_defs::MEMORY_READ_PORTS;
    localparam int RETIRES_PER_CYCLE = DRIS_defs::REG_FILE_WRITE_PORTS;

    // The register file needs one write port per retire slot; the
    // Scheduler only uses read pairs [EXEC_UNITS-1:0].
    localparam int RF_WAYS = DRIS_defs::REG_FILE_WRITE_PORTS;

    /* =================================================================
     * Inter-unit nets
     * ================================================================= */
    dris_entry_t dris_entries [DRIS_NUM_ENTRIES-1:0];

    // IIU -> DRIS intake (IIU emits unpacked, DRIS takes packed)
    dris_intake_pkt_t                   dris_intake_pkts [FETCH_WORDS-1:0];
    dris_intake_pkt_t [FETCH_WORDS-1:0] fetch_pkts;
    logic [DRIS_ID_WIDTH:0]             fetch_ptr;

    // Scheduler -> execute -> DRIS writeback / update bus
    issue_pkt_t                              issue_pkts [EXEC_UNITS-1:0];
    logic [DRIS_NUM_ENTRIES-1:0]             set_dispatched;
    dris_writeback_pkt_t [WRITEBACK_PORTS-1:0] writeback_pkts;
    dris_writeback_pkt_t                     update_bus [EXEC_UNITS-1:0];

    // SSC
    logic [DRIS_ID_WIDTH:0]      retire_ptr;
    logic [DRIS_NUM_ENTRIES-1:0] clear_valid;
    reg_file_commit_pkt_t [RETIRES_PER_CYCLE-1:0] reg_commits;
    logic                        mem_write_valid;   // no memory unit yet
    dris_id_t                    mem_write_id;
    logic                        trap_valid;
    logic [XLEN-1:0]             trap_pc;
    dris_id_t                    trap_id;

    // Branch shelf fence / flush (IIU -> SSC)
    dris_id_t                    oldest_branch_id;
    logic                        branch_fence_valid;
    logic [DRIS_NUM_ENTRIES-1:0] flush_mask;

    // Scheduler <-> register file read ports
    logic [EXEC_UNITS-1:0]    sched_read_rf;    // informational; reads are always live
    logic [REG_NUM_WIDTH-1:0] sched_rs1_addr [EXEC_UNITS-1:0];
    logic [REG_NUM_WIDTH-1:0] sched_rs2_addr [EXEC_UNITS-1:0];
    logic [XLEN-1:0]          sched_rs1_data [EXEC_UNITS-1:0];
    logic [XLEN-1:0]          sched_rs2_data [EXEC_UNITS-1:0];

    /* =================================================================
     * DRIS
     * ================================================================= */
    always_comb begin : intake_repack
        for (int w = 0; w < FETCH_WORDS; w++)
            fetch_pkts[w] = dris_intake_pkts[w];
    end : intake_repack

    DRIS dris (
        .clock            (clock),
        .reset_n          (reset_n),
        .fetch_pkts       (fetch_pkts),
        .writeback_pkts   (writeback_pkts),
        .set_dispatched   (set_dispatched),
        .clear_valid      (clear_valid),
        .fetch_ptr        (fetch_ptr),
        .dris_entries     (dris_entries)
    );

    /* =================================================================
     * IIU — fetch/rename front end + branch shelf. Owns the I-side
     * cache controller seam, so those ports pass straight through.
     * ================================================================= */
    InstructionIssueUnit #(
        .FETCH_WORDS      (FETCH_WORDS),
        .ADDRESS_SIZE     (ADDRESS_SIZE),
        .NUM_UPDATE_PORTS (EXEC_UNITS)
    ) iiu (
        .clock               (clock),
        .reset_n             (reset_n),
        .dris_entries        (dris_entries),
        .dris_intake_pkts    (dris_intake_pkts),
        .fetch_ptr           (fetch_ptr),
        .update_bus          (update_bus),
        .retire_ptr          (retire_ptr),
        .oldest_branch_id    (oldest_branch_id),
        .branch_fence_valid  (branch_fence_valid),
        .flush_mask          (flush_mask),
        .trap_valid          (trap_valid),
        .trap_pc             (trap_pc),
        .core_req_re         (core_req_re),
        .core_req_addr       (core_req_addr),
        .core_req_cancel     (core_req_cancel),
        .core_req_stall_mem  (core_req_stall_mem),
        .core_rsp_data       (core_rsp_data),
        .core_rsp_addr       (core_rsp_addr),
        .core_rsp_data_valid (core_rsp_data_valid),
        .core_rsp_ready      (core_rsp_ready),
        .core_rsp_excpt      (core_rsp_excpt)
    );

    /* =================================================================
     * Scheduler
     * ================================================================= */
    Scheduler #(
        .EXEC_UNITS (EXEC_UNITS)
    ) scheduler (
        .clock          (clock),
        .reset_n        (reset_n),
        .dris_entries   (dris_entries),
        .retire_ptr     (retire_ptr[DRIS_ID_WIDTH-1:0]),
        .issue_pkts     (issue_pkts),
        .set_dispatched (set_dispatched),
        .read_rf        (sched_read_rf),
        .rs1_addr       (sched_rs1_addr),
        .rs2_addr       (sched_rs2_addr),
        .rs1_data       (sched_rs1_data),
        .rs2_data       (sched_rs2_data)
    );

    issue_pkt_t issue_pkts_reg [EXEC_UNITS-1:0];
    always_ff @(posedge clock, negedge reset_n) begin
        if (!reset_n) begin
            issue_pkts_reg <= '{default: '0};
        end else begin
            issue_pkts_reg <= issue_pkts;
        end
    end

    genvar e;
    generate
        for (e = 0; e < EXEC_UNITS; e++) begin: execute
            ExecutionUnit exec_unit (
                .issue_pkt     (issue_pkts_reg[e]),
                .writeback_pkt (update_bus[e])
            );
        end
    endgenerate

    // Exec writebacks feed both the DRIS write ports and the IIU/shelf
    // snoop (update_bus). The memory writeback ports
    // [WRITEBACK_PORTS-1:EXEC_UNITS] stay idle until the memory unit
    // exists.
    always_comb begin : writeback_wiring
        writeback_pkts = '0;
        for (int w = 0; w < EXEC_UNITS; w++)
            writeback_pkts[w] = update_bus[w];
    end : writeback_wiring

    /* =================================================================
     * Sane State Controller
     * ================================================================= */
    SaneStateController ssc (
        .clock              (clock),
        .reset_n            (reset_n),
        .dris_entries       (dris_entries),
        .retire_ptr         (retire_ptr),
        .oldest_branch_id   (oldest_branch_id),
        .branch_fence_valid (branch_fence_valid),
        .flush_mask         (flush_mask),
        .clear_valid        (clear_valid),
        .reg_commits        (reg_commits),
        .mem_write_valid    (mem_write_valid),
        .mem_write_id       (mem_write_id),
        .trap_valid         (trap_valid),
        .trap_pc            (trap_pc),
        .trap_id            (trap_id)
    );

    // The only trap source today is ECALL (plus illegal instructions,
    // which no passing test generates); real trap/CSR plumbing is TBD,
    // so a syscall reaching the head of the DRIS halts the machine.
    assign halted = trap_valid &&
                    dris_entries[trap_id.id_index].ctrl_signals.syscall;

    /* =================================================================
     * Register file (447src): RF_WAYS write ports for retirement,
     * read pairs [EXEC_UNITS-1:0] for the Scheduler, the rest idle.
     * Write conflicts resolve highest-way-wins = youngest retire slot,
     * matching program order.
     * ================================================================= */
    logic [RF_WAYS-1:0]                     rf_we;
    logic [RF_WAYS-1:0][REG_NUM_WIDTH-1:0]  rf_rs1, rf_rs2, rf_rd;
    logic [RF_WAYS-1:0][XLEN-1:0]           rf_rd_data;
    logic [RF_WAYS-1:0][XLEN-1:0]           rf_rs1_data, rf_rs2_data;

    always_comb begin : rf_read_wiring
        rf_rs1 = '0;
        rf_rs2 = '0;
        for (int e = 0; e < EXEC_UNITS; e++) begin
            rf_rs1[e]         = sched_rs1_addr[e];
            rf_rs2[e]         = sched_rs2_addr[e];
            sched_rs1_data[e] = rf_rs1_data[e];
            sched_rs2_data[e] = rf_rs2_data[e];
        end
    end : rf_read_wiring

    always_comb begin : rf_write_wiring
        for (int i = 0; i < RF_WAYS; i++) begin
            rf_we[i]      = reg_commits[i].valid_C;
            rf_rd[i]      = reg_commits[i].rd_C;
            rf_rd_data[i] = reg_commits[i].rd_data_C;
        end
    end : rf_write_wiring

    /* Write-only commit packets: see the TODO(SSC) note on the commit_pkts
     * port — reg_commits lack pc/insn and non-writing retirements, so
     * packets are emitted only for register-writing retirements (pc/insn
     * report as 0). That is enough for the harness's shadow regfile (and
     * therefore the end-state simulation.reg dump) to track architectural
     * state; the per-commit trace can't align with the refsim until the
     * SSC provides the rest, so verify-trace stays inorder-only. */
    RISCV_Commit::commit_pkt_t [RF_WAYS-1:0] rf_commit_pkts;

    register_file #(
        .WAYS (RF_WAYS)
    ) rf (
        .clk          (clock),
        .rst_l        (reset_n),
        .rd_we        (rf_we),
        .rs1          (rf_rs1),
        .rs2          (rf_rs2),
        .rd           (rf_rd),
        .rd_data      (rf_rd_data),
        .commit_valid (rf_we),
        .commit_pc    ('0),
        .commit_insn  ('0),
        .rs1_data     (rf_rs1_data),
        .rs2_data     (rf_rs2_data),
        .commit_pkts  (rf_commit_pkts)
    );

`ifdef SIMULATION_18447
    always_comb begin : commit_pkt_padding
        commit_pkts = '0;
        for (int i = 0; i < RF_WAYS; i++)
            commit_pkts[i] = rf_commit_pkts[i];
    end : commit_pkt_padding
`endif

endmodule : LightningCore

module ExecutionUnit(
    input issue_pkt_t issue_pkt,
    output dris_writeback_pkt_t writeback_pkt
);

   logic [XLEN-1:0] alu_out, next_pc;
   logic bcond;

    riscv_alu alu (
        .alu_src1 (issue_pkt.op_1_I),
        .alu_src2 (issue_pkt.op_2_I),
        .alu_op   (issue_pkt.ctrl_signals_I.alu_op),
        .alu_out  (alu_out)
    );

    assign bcond = alu_out[0];

    always_comb begin: next_pc_logic
        unique case (issue_pkt.ctrl_signals_I.pc_source)
            PC_cond:     next_pc =
                             bcond
                                 ? issue_pkt.pc_I + issue_pkt.imm_I
                                 : issue_pkt.pc_I + XLEN'(4);
            PC_uncond:   next_pc =
                             issue_pkt.pc_I + issue_pkt.imm_I;
            // op_1_I is the PC here (usePC link setup), so the target's
            // rs1 rides the packet's dedicated rs1_data_I field
            PC_indirect: next_pc =
                             (issue_pkt.rs1_data_I + issue_pkt.imm_I)
                             & ~(XLEN'(1));
            default:     next_pc =
                             issue_pkt.pc_I + XLEN'(4);
        endcase        
    end: next_pc_logic

    always_comb begin: writeback_pkt_generation
        writeback_pkt.valid_W = issue_pkt.ready_I;
        writeback_pkt.id_W = issue_pkt.id_I;
        writeback_pkt.pc_W = issue_pkt.pc_I;
        writeback_pkt.ctrl_signals_W = issue_pkt.ctrl_signals_I;
        writeback_pkt.result_data_W = alu_out;
        writeback_pkt.next_pc_W = next_pc;

        `ifdef DEBUG
                writeback_pkt.debug_instr_dris_W = issue_pkt.debug_instr_I;
        `endif

    end: writeback_pkt_generation

endmodule : ExecutionUnit

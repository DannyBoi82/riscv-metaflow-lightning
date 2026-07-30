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
 * branch shelf), the Scheduler, the MemoryScheduler, the Sane State
 * Controller, the register file (tb/register_file.sv), and the execute
 * ways (per-way IntExecutionUnit, per TODO-IIU.md Phase 4).
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
 * There are two external seams, both cache-controller facing: the
 * I-side (core_req_* / core_rsp_*, owned by the IIU) and the D-side
 * (core_req_*_d / core_rsp_*_d, owned by the MemoryScheduler), plus
 * halted.
 *
 * Memory is two-phase, per the Metaflow spec: an ALU way computes the
 * address (phase 1), then the MemoryScheduler gives loads a second
 * schedule against the D-cache and releases stores to memory at retire.
 *
 * Both halves of the D-side are wired. Requests: the MemoryScheduler's
 * issue packets are arbitrated onto the single cache port by
 * d_request_drive below. Responses: the load return path lives here
 * rather than in the MemoryScheduler (which has no response ports) —
 * core_rsp_*_d drives writeback_pkts[EXEC_UNITS] directly, with
 * get_load_data() doing the byte/half alignment, so a load's data
 * reaches its DRIS entry by id without a second schedule.
 *
 * Instantiated by riscv_core_interface in place of the in-order
 * riscv_core.
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
    input  logic                      core_rsp_excpt,

    /* ============================================================
     * D-side cache controller (core_req_*_d / core_rsp_*_d seam),
     * owned by the MemoryScheduler.
     *
     * The D-cache is single-ported and accepts at most one request
     * per cycle (the controller asserts on re & we together), so the
     * MemoryScheduler's MEM_ISSUE_WAYS issue packets are arbitrated
     * down to one request here.
     * ============================================================ */
    output logic                      core_req_re_d,
    output logic                      core_req_we_d,
    output logic [ADDRESS_SIZE-1:0]   core_req_addr_d,
    output logic [3:0]                core_req_store_mask_d,
    output logic [XLEN-1:0]           core_req_store_data_d,
    output logic                      core_req_cancel_d,
    output logic                      core_req_stall_mem_d,
    output dris_id_t                  core_req_id_d,
    output ctrl_signals_t              core_req_ctrl_signals_d,
    input  logic [XLEN-1:0]           core_rsp_data_d,
    input  logic [ADDRESS_SIZE-1:0]   core_rsp_addr_d,
    input  logic                      core_rsp_data_valid_d,
    input  logic                      core_rsp_ready_d,
    input  logic                      core_rsp_excpt_d,
    input  dris_id_t                  core_rsp_id_d,
    input  ctrl_signals_t              core_rsp_ctrl_signals_d
);

    localparam int WRITEBACK_PORTS = EXEC_UNITS + DRIS_defs::MEMORY_READ_PORTS;
    localparam int RETIRES_PER_CYCLE = DRIS_defs::REG_FILE_WRITE_PORTS;

    // Issue ways the MemoryScheduler presents. The D-cache is single ported
    // and accepts at most one request per cycle, so the MemoryScheduler is
    // given exactly one way and does the load/store arbitration internally
    // (its dispatch loop fills the way with a store before considering a
    // load, so writes win). This must stay equal to the TOTAL_PORTS override
    // on the instance below — the two size the same packet array.
    localparam int MEM_ISSUE_WAYS = 1;

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
    logic [DRIS_NUM_ENTRIES-1:0] retire_vector;
    logic [DRIS_NUM_ENTRIES-1:0] flush_vector;
    reg_file_commit_pkt_t [RETIRES_PER_CYCLE-1:0] reg_commits;
    logic                        trap_valid;
    logic [XLEN-1:0]             trap_pc;
    dris_id_t                    trap_id;
    logic store_ready;
    dris_id_t store_id;

    // MemoryScheduler
    memory_issue_pkt_t           mem_issue_pkts [MEM_ISSUE_WAYS-1:0];
    logic [DRIS_NUM_ENTRIES-1:0] set_dispatched_mem;
    logic [MEM_ISSUE_WAYS-1:0]   mem_read_rf;
    logic [REG_NUM_WIDTH-1:0]    mem_rs1_addr [MEM_ISSUE_WAYS-1:0];
    logic [REG_NUM_WIDTH-1:0]    mem_rs2_addr [MEM_ISSUE_WAYS-1:0];
    logic [XLEN-1:0]             mem_rs1_data [MEM_ISSUE_WAYS-1:0];
    logic [XLEN-1:0]             mem_rs2_data [MEM_ISSUE_WAYS-1:0];

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
        // Two schedulers dispatch into the DRIS: the integer Scheduler
        // (phase 1 / ALU ways) and the MemoryScheduler (phase 2 / D-cache).
        // They pick from disjoint entries, so a plain OR is the merge.
        .set_dispatched   (set_dispatched | set_dispatched_mem),
        .clear_valid      (retire_vector | flush_vector),
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

    /* =================================================================
     * MemoryScheduler — the loads' second schedule (address already
     * computed by an ALU way) plus the store release at retire. Owns
     * the D-side cache seam via the arbiter below.
     * ================================================================= */
    MemoryScheduler #(
        .TOTAL_PORTS (MEM_ISSUE_WAYS) //right now cache is single ported
    )ms (
        .clock              (clock),
        .reset_n            (reset_n),
        .store_ready        (store_ready),
        .store_id           (store_id),
        .dris_entries       (dris_entries),
        .retire_ptr         (retire_ptr[DRIS_ID_WIDTH-1:0]),
        .retire_vector      (retire_vector),
        .mem_issue_pkts     (mem_issue_pkts),
        .set_dispatched_mem (set_dispatched_mem),
        .d_cache_ready      (core_rsp_ready_d),
        .read_rf            (mem_read_rf),
        .rs1_addr           (mem_rs1_addr),
        .rs2_addr           (mem_rs2_addr),
        .rs1_data           (mem_rs1_data),
        .rs2_data           (mem_rs2_data)
    );

    // always_ff @(posedge clock) begin
    //     $display("mem_issue_pkts[0].core_req_ctrl_signals: %b", mem_issue_pkts[0].core_req_ctrl_signals);
    // end

    /* =================================================================
     * D-cache port drive: MEM_ISSUE_WAYS issue packets -> 1 request.
     *
     * This must be combinational, not registered. The controller accepts
     * a request live (same-cycle probe), and the SSC gates a store's
     * retirement on d_cache_ready in the same cycle the MemoryScheduler
     * issues that store — so a registered request would retire the store
     * a cycle before the cache ever saw it. It also has to fall back to
     * an idle request when no way is asking, or the last request would
     * be held and replayed every cycle.
     *
     * The controller asserts if re & we are ever set together, so exactly
     * one packet may drive the port per cycle. With MEM_ISSUE_WAYS = 1
     * the MemoryScheduler has already picked (writes win), and this loop
     * degenerates to a pass-through; it stays a priority select so
     * widening the D-side doesn't silently drive two requests at once.
     *
     * This is the request half only. Responses are consumed further
     * down, where core_rsp_*_d drives writeback_pkts[EXEC_UNITS] into
     * the DRIS's memory-read writeback port.
     * ================================================================= */
    logic d_granted;
    always_comb begin : d_request_drive
        d_granted             = 1'b0;
        core_req_re_d         = 1'b0;
        core_req_we_d         = 1'b0;
        core_req_addr_d       = '0;
        core_req_store_mask_d = '0;
        core_req_store_data_d = '0;
        core_req_id_d         = '0;
        core_req_ctrl_signals_d = '0;
        for (int w = 0; w < MEM_ISSUE_WAYS; w++) begin
            if (!d_granted && (mem_issue_pkts[w].core_req_re ||
                               mem_issue_pkts[w].core_req_we)) begin
                d_granted             = 1'b1;
                core_req_re_d         = mem_issue_pkts[w].core_req_re;
                core_req_we_d         = mem_issue_pkts[w].core_req_we;
                core_req_addr_d       = mem_issue_pkts[w].core_req_addr;
                core_req_store_mask_d = mem_issue_pkts[w].core_req_store_mask;
                core_req_store_data_d = mem_issue_pkts[w].core_req_store_data;
                core_req_id_d         = mem_issue_pkts[w].core_req_id;
                core_req_ctrl_signals_d = mem_issue_pkts[w].core_req_ctrl_signals;
            end
        end
    end : d_request_drive



    // The D-side never cancels (the controller's FSM assumes this: a cancel
    // mid-fill would strand the memory bus), and nothing stalls its FIFO
    // because each response is consumed the cycle it appears.
    assign core_req_cancel_d    = 1'b0;
    assign core_req_stall_mem_d = 1'b0;

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
            IntExecutionUnit exec_unit (
                .issue_pkt     (issue_pkts_reg[e]),
                .writeback_pkt (update_bus[e])
            );
        end
    endgenerate

    always_comb begin : writeback_wiring
        writeback_pkts = '0;
        for (int e = 0; e < EXEC_UNITS; e++)
            writeback_pkts[e] = update_bus[e];

        writeback_pkts[EXEC_UNITS].id_W = core_rsp_id_d;
        writeback_pkts[EXEC_UNITS].valid_W = core_rsp_data_valid_d;
        writeback_pkts[EXEC_UNITS].result_data_W = get_load_data(core_rsp_ctrl_signals_d,
        dris_entries[core_rsp_id_d.id_index].result.result_data[1:0],
        core_rsp_data_d);
        writeback_pkts[EXEC_UNITS].ctrl_signals_W = core_rsp_ctrl_signals_d;

    end : writeback_wiring

    function automatic logic [XLEN-1:0] get_load_data(ctrl_signals_t ctrl_signals,
    logic [1:0] byte_offset,
    logic [XLEN-1:0] data_load);

        if (ctrl_signals.mem2RF === 1'b1) begin
            case (ctrl_signals.ldst_mode)
                LDST_W:  return data_load;
                LDST_H:  return byte_offset[1]
                                 ? {{16{data_load[31]}}, data_load[31:16]}
                                 : {{16{data_load[15]}}, data_load[15:0]};
                LDST_HU: return byte_offset[1]
                                 ? {16'd0, data_load[31:16]}
                                 : {16'd0, data_load[15:0]};
                LDST_B: begin
                    case (byte_offset)
                        2'd0: return {{24{data_load[7]}},  data_load[7:0]};
                        2'd1: return {{24{data_load[15]}}, data_load[15:8]};
                        2'd2: return {{24{data_load[23]}}, data_load[23:16]};
                        2'd3: return {{24{data_load[31]}}, data_load[31:24]};
                    endcase
                end
                LDST_BU: begin
                    case (byte_offset)
                        2'd0: return {24'd0, data_load[7:0]};
                        2'd1: return {24'd0, data_load[15:8]};
                        2'd2: return {24'd0, data_load[23:16]};
                        2'd3: return {24'd0, data_load[31:24]};
                    endcase
                end
                default: return data_load;
            endcase
        end
    endfunction : get_load_data

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
        // A store retires only on a cycle the D-cache can accept its write,
        // so the cache really is committing it when the core believes it is.
        .d_cache_ready      (core_rsp_ready_d),
        .store_ready        (store_ready),
        .store_id           (store_id),
        .retire_vector      (retire_vector),
        .flush_vector       (flush_vector),
        .reg_commits        (reg_commits),
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
     * Register file (tb/register_file.sv): RF_WAYS write ports for
     * retirement, read pairs [EXEC_UNITS-1:0] for the Scheduler,
     * [EXEC_UNITS +: MEM_ISSUE_WAYS] for the MemoryScheduler's store
     * data, the rest idle.
     * Write conflicts resolve highest-way-wins = youngest retire slot,
     * matching program order.
     * ================================================================= */
    logic [RF_WAYS-1:0]                     rf_we;
    logic [RF_WAYS-1:0][REG_NUM_WIDTH-1:0]  rf_rs1, rf_rs2, rf_rd;
    logic [RF_WAYS-1:0][XLEN-1:0]           rf_rd_data;
    logic [RF_WAYS-1:0][XLEN-1:0]           rf_rs1_data, rf_rs2_data;

    // Read ports are split by owner: ways [0, EXEC_UNITS) belong to the
    // integer Scheduler, ways [EXEC_UNITS, EXEC_UNITS+MEM_ISSUE_WAYS) to the
    // MemoryScheduler (store data is read from the regfile at issue, on rs2).
    // With EXEC_UNITS=4 and MEM_ISSUE_WAYS=1 that uses 5 of the RF_WAYS=7
    // read pairs; the remaining pairs read x0 and are ignored.
    always_comb begin : rf_read_wiring
        rf_rs1 = '0;
        rf_rs2 = '0;
        for (int e = 0; e < EXEC_UNITS; e++) begin
            rf_rs1[e]         = sched_rs1_addr[e];
            rf_rs2[e]         = sched_rs2_addr[e];
            sched_rs1_data[e] = rf_rs1_data[e];
            sched_rs2_data[e] = rf_rs2_data[e];
        end
        for (int m = 0; m < MEM_ISSUE_WAYS; m++) begin
            rf_rs1[EXEC_UNITS + m] = mem_rs1_addr[m];
            rf_rs2[EXEC_UNITS + m] = mem_rs2_addr[m];
            mem_rs1_data[m]        = rf_rs1_data[EXEC_UNITS + m];
            mem_rs2_data[m]        = rf_rs2_data[EXEC_UNITS + m];
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

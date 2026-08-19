`default_nettype none

`include "riscv_commit.vh"

/* Performance counters are simulation-only: comment this out before
 * synthesis, same as the in-order core's `PERF (rtl/core/riscv_core.sv
 * line 36). Only the counter block at the bottom of this file is gated by
 * it — the cache-event input ports and the IIU's perf outputs are always
 * present, so the port list has the same shape in every build.
 *
 * Deliberately NOT named `PERF. Macros carry across files on the compiler
 * command line, rtl/core is compiled before rtl/ooo (Makefile
 * RTL_DIR_ORDER), and riscv_core.sv is in every build regardless of CORE —
 * so riscv_core.sv's `define PERF is already in scope here. Sharing the
 * name means commenting this line out does nothing until you also comment
 * out the in-order core's, which is exactly the trap `1DRIS_defs.sv warns
 * about for DEBUG. LTG_PERF is Lightning's own switch, per the LTG_*
 * convention in rtl/include/config.vh.
 *
 * `ifndef-guarded so a `PARAMS='+define+LTG_PERF'` on the command line
 * (scripts/cache_sweep.py does this) isn't a redefinition. */
`ifndef LTG_PERF
`define LTG_PERF
`endif

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
    /* Commit packets for the verify-trace flow (see riscv_commit.vh):
     * one packet per instruction retired this cycle, slot 0 = oldest.
     * Driven from the retirement seam (retire_vector + the DRIS entries)
     * at the bottom of this file, so branches, stores and the halting
     * ecall are reported too, not just register-writing retirements.
     * Outside simulation the port disappears and the commit logic below
     * is dead and gets pruned. */
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
    input  ctrl_signals_t              core_rsp_ctrl_signals_d,

    /* ============================================================
     * Cache-event inputs for the performance counters.
     *
     * These are events the cache controllers raise and the core has no
     * other view of; riscv_core_interface already has every one of them
     * as a local wire and just fans them in here. They are always-present
     * ports, exactly as on the in-order core (rtl/core/riscv_core.sv):
     * only the counters that consume them are `ifdef LTG_PERF, so the
     * list has the same shape in every build.
     * ============================================================ */
    input  logic                      is_eviction_i, read_hit_i, read_miss_i,
    input  logic                      is_eviction_d, read_hit_d, read_miss_d,
    input  logic                      choose_d_cache,
    input  logic                      i_d_conflict
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

    // IIU perf observation (always driven; consumed only under `LTG_PERF)
    logic [$clog2(DRIS_defs::BRANCH_SHELF_ENTRIES+1)-1:0] perf_shelf_occupancy;
    logic perf_branch_resolved, perf_branch_mispredicted, perf_mispredict_valid;
    logic perf_branch_mispredict_squashed;
    logic perf_stall_pc, perf_stall_dris_full, perf_stall_shelf_full;
    logic perf_issue_fire;

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
        .core_rsp_excpt      (core_rsp_excpt),
        .perf_shelf_occupancy     (perf_shelf_occupancy),
        .perf_branch_resolved     (perf_branch_resolved),
        .perf_branch_mispredicted (perf_branch_mispredicted),
        .perf_branch_mispredict_squashed (perf_branch_mispredict_squashed),
        .perf_mispredict_valid    (perf_mispredict_valid),
        .perf_stall_pc        (perf_stall_pc),
        .perf_stall_dris_full     (perf_stall_dris_full),
        .perf_stall_shelf_full    (perf_stall_shelf_full),
        .perf_issue_fire          (perf_issue_fire)
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

`ifdef LTG_DBG_MEM
    /* TEMPORARY debug probe (stale-D-response investigation). Delete me. */
    always_ff @(posedge clock) begin: dbg_mem_probe
        if (reset_n) begin
            if ((core_req_re_d || core_req_we_d) && core_rsp_ready_d)
                $display("DBGREQ %0t %s id=%0d/c%0d addr=%08h",
                         $time, core_req_we_d ? "ST" : "LD",
                         core_req_id_d.id_index, core_req_id_d.id_color,
                         {core_req_addr_d, 2'b00});
            if (core_rsp_data_valid_d)
                $display("DBGRSP %0t id=%0d/c%0d data=%08h rspRD=%0d rspWR=%0d || entry: v=%0d col=%0d RD=%0d WR=%0d addrRdy=%0d disp=%0d exec=%0d pc=%08h insn=%08h",
                         $time, core_rsp_id_d.id_index, core_rsp_id_d.id_color,
                         core_rsp_data_d,
                         core_rsp_ctrl_signals_d.memRead,
                         core_rsp_ctrl_signals_d.memWrite,
                         dris_entries[core_rsp_id_d.id_index].entry_state.valid,
                         dris_entries[core_rsp_id_d.id_index].id.id_color,
                         dris_entries[core_rsp_id_d.id_index].ctrl_signals.memRead,
                         dris_entries[core_rsp_id_d.id_index].ctrl_signals.memWrite,
                         dris_entries[core_rsp_id_d.id_index].entry_state.mem_addr_ready,
                         dris_entries[core_rsp_id_d.id_index].entry_state.dispatched,
                         dris_entries[core_rsp_id_d.id_index].entry_state.executed,
                         dris_entries[core_rsp_id_d.id_index].pc,
                         dris_entries[core_rsp_id_d.id_index].debug_instr);
            if (|flush_vector)
                $display("DBGFLUSH %0t mask=%08h", $time, flush_vector);
        end
    end: dbg_mem_probe
`endif

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

    /* =================================================================
     * Commit packets (the verify-trace seam, rtl/include/riscv_commit.vh).
     *
     * The regfile assembles the packets, but it cannot source them: it
     * only ever sees retirements that *write* a register, and it has no
     * PC. The trace needs one packet per retired instruction — branches,
     * stores and the halting ecall included — in program order. So the
     * retire-slot half of each packet (valid + pc) is driven from the
     * retirement seam here, and the regfile fills in the register-write
     * half from the write-port inputs of the same slot (rd_addr = 0 for
     * a non-writing retirement or a write to x0, per the RVFI contract).
     *
     * Program order within a cycle: the SSC publishes retire_vector
     * entry-indexed (it scattered its slot window onto entry indices),
     * so slot order is recovered the way the SSC built it — slot s is
     * the entry at retire_ptr + s, slot 0 being the oldest. That is also
     * the slot that reg_commits[s] / regfile write port s belongs to, so
     * the two halves of the packet stay aligned by construction.
     *
     * The instruction word is reported only in `DEBUG builds
     * (`PARAMS='+define+DEBUG'`), which is when the DRIS entry carries
     * one. Nothing diffs against it — insn rides the trace inside the
     * `#` comment the checker strips — it only annotates the divergence
     * report, where pc identifies the instruction anyway.
     * ================================================================= */
`ifndef SIMULATION_18447
    // Off-simulation stand-in for the ifdef'd port, so the commit logic
    // below always elaborates (it is dead there and gets pruned).
    RISCV_Commit::commit_pkt_t [RISCV_Commit::COMMIT_WAYS_MAX-1:0] commit_pkts;
`endif

    RISCV_Commit::commit_pkt_t [RF_WAYS-1:0] rf_commit_pkts;
    logic [RF_WAYS-1:0]           rf_commit_valid;
    logic [RF_WAYS-1:0][XLEN-1:0] rf_commit_pc, rf_commit_insn;
    RISCV_Commit::commit_mem_t [RF_WAYS-1:0] rf_commit_mem;

    // DRIS index of the n-th retirement slot, counting from the retire
    // pointer — the same mapping the SSC scatters retire_vector through.
    function automatic logic [DRIS_ID_WIDTH-1:0] retire_slot_index(input int slot);
        return (retire_ptr + slot) % DRIS_NUM_ENTRIES;
    endfunction

    always_comb begin : commit_seam
        for (int s = 0; s < RF_WAYS; s++) begin
            rf_commit_valid[s] = retire_vector[retire_slot_index(s)];
            rf_commit_pc[s]    = dris_entries[retire_slot_index(s)].pc;
`ifdef DEBUG
            rf_commit_insn[s]  = dris_entries[retire_slot_index(s)].debug_instr;
`else
            rf_commit_insn[s]  = '0;
`endif
        end
    end : commit_seam

    /* =================================================================
     * The memory half of the commit packet (verify-mem, riscv_commit.vh).
     *
     * Loads report from the retiring entry: the address is the copy the
     * AGU pass parked in `debug_mem_addr` (result_data has since been
     * clobbered by the load's own data writeback) and the data is the
     * load result, un-extended back into its word lanes so both sides of
     * the diff describe the bus rather than the register.
     *
     * Stores can't report from the entry: the store data never enters the
     * DRIS (the MemoryScheduler reads rs2 at issue) and the mask is built
     * there too. They don't have to — a store issues to the cache in the
     * *same* cycle it retires, by construction (SaneStateController gates
     * a store's retirement on `store_ready & d_cache_ready`), so the live
     * request is still on the wire and can be matched to the retiring
     * entry by DRIS id. That also makes the trace report the actual bus
     * values, so a lane bug in get_store_mask/get_store_data shows up
     * here instead of being re-derived away.
     * ================================================================= */
`ifdef DEBUG
    logic [DRIS_ID_WIDTH-1:0] commit_mem_entry;
    logic [XLEN-1:0]          commit_mem_addr;
    logic [3:0]               commit_size_mask;
`endif

    always_comb begin : commit_mem_seam
        rf_commit_mem = '0;
`ifdef DEBUG
        commit_mem_entry = '0;
        commit_mem_addr  = '0;
        commit_size_mask = '0;
        for (int s = 0; s < RF_WAYS; s++) begin
            commit_mem_entry = retire_slot_index(s);
            commit_mem_addr  = dris_entries[commit_mem_entry].debug_mem_addr;
            commit_size_mask = get_byte_mask(commit_mem_addr,
                    dris_entries[commit_mem_entry].ctrl_signals.ldst_mode);

            if (rf_commit_valid[s] &&
                dris_entries[commit_mem_entry].ctrl_signals.memRead) begin

                rf_commit_mem[s].addr  = commit_mem_addr;
                rf_commit_mem[s].rmask = commit_size_mask;
                /* result_data is the sign/zero-extended load value; shift the
                 * accessed bytes back to their lanes. */
                rf_commit_mem[s].rdata =
                        (dris_entries[commit_mem_entry].result.result_data
                         & expand_byte_mask(commit_size_mask >> commit_mem_addr[1:0]))
                        << (8 * commit_mem_addr[1:0]);
            end
            else if (rf_commit_valid[s] &&
                     dris_entries[commit_mem_entry].ctrl_signals.memWrite) begin

                rf_commit_mem[s].addr = commit_mem_addr;
                for (int w = 0; w < MEM_ISSUE_WAYS; w++) begin
                    if (mem_issue_pkts[w].core_req_we &&
                        (mem_issue_pkts[w].core_req_id.id_index == commit_mem_entry)) begin
                        /* Address off the bus, not the entry: the point is to
                         * report what the cache was actually asked for. (They
                         * agree today — the MemoryScheduler drives
                         * result_data[31:2], the same value the AGU pass
                         * parked — which is exactly what makes it worth
                         * reporting the one the hardware used.) */
                        rf_commit_mem[s].addr  =
                                {mem_issue_pkts[w].core_req_addr, commit_mem_addr[1:0]};
                        rf_commit_mem[s].wmask = mem_issue_pkts[w].core_req_store_mask;
                        rf_commit_mem[s].wdata =
                                mem_issue_pkts[w].core_req_store_data
                                & expand_byte_mask(mem_issue_pkts[w].core_req_store_mask);
                    end
                end
            end
        end
`endif
    end : commit_mem_seam

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
        .commit_valid (rf_commit_valid),
        .commit_pc    (rf_commit_pc),
        .commit_insn  (rf_commit_insn),
        .commit_mem   (rf_commit_mem),
        .rs1_data     (rf_rs1_data),
        .rs2_data     (rf_rs2_data),
        .commit_pkts  (rf_commit_pkts)
    );

    always_comb begin : commit_pkt_padding
        commit_pkts = '0;
        for (int i = 0; i < RF_WAYS; i++)
            commit_pkts[i] = rf_commit_pkts[i];

        /* The halting ecall never retires — the SSC traps on it at the
         * retire head instead, which is what raises `halted` — so no
         * retire slot reports it. The reference simulator does execute
         * it and emits a final trace line, so force one last packet on
         * the halt edge (the in-order core does the same through
         * `valid_W & (~stall_W | halted)`). It writes no register, and
         * slot 0 is free: nothing retires in a cycle whose head entry
         * has trapped. */
        if (halted) begin
            commit_pkts[0]          = '0;
            commit_pkts[0].valid    = 1'b1;
            commit_pkts[0].pc_rdata = trap_pc;
`ifdef DEBUG
            commit_pkts[0].insn     = dris_entries[trap_id.id_index].debug_instr;
`endif
        end
    end : commit_pkt_padding

    /* =================================================================
     * PERFORMANCE COUNTERS (`LTG_PERF only)
     *
     * Same conventions as the in-order core's block (rtl/core/riscv_core.sv,
     * "PERFORMANCE COUNTERS"): plain `int` counters in one always_ff, reset
     * with the core, frozen once `halted`, pretty-printed by a task on the
     * halt edge. Everything here is observation only — no signal below is
     * read by the design.
     *
     * Two things differ from the in-order block, both because this is an
     * out-of-order machine:
     *
     *  - The in-order stall breakdown (FD/EMW, stall run-length histogram)
     *    has no analogue. A "stalled" OoO core shows up instead as low
     *    utilization: few retires per cycle, few issue slots used. Those
     *    are the Part 2 counters below, plus the explicit front-end
     *    blocking counters (DRIS full / shelf full).
     *
     *  - Per-cycle events are counts, not booleans: several instructions
     *    can retire, issue or be fetched in one cycle. Each such counter
     *    is accumulated from a combinational popcount computed just below,
     *    because an NBA inside a for-loop would keep only the last write.
     *
     * Averages are accumulate-now, divide-at-print: no `real` arithmetic
     * outside print_perf_metrics().
     * ================================================================= */
`ifdef LTG_PERF
    // ----- Per-cycle observation vectors -------------------------------
    // $countones needs a packed vector; dris_entries / issue_pkts_reg /
    // mem_issue_pkts are unpacked arrays of structs, so flatten first.
    logic [DRIS_NUM_ENTRIES-1:0] perf_dris_valid;
    logic [FETCH_WORDS-1:0]      perf_fetch_valid;
    logic [EXEC_UNITS-1:0]       perf_int_busy;
    logic [MEM_ISSUE_WAYS-1:0]   perf_mem_busy;

    always_comb begin : perf_vectors
        for (int i = 0; i < DRIS_NUM_ENTRIES; i++)
            perf_dris_valid[i] = dris_entries[i].entry_state.valid;

        // Fetch counts DRIS intakes, so it includes wrong-path instructions
        // by construction — that is the point of the metric: the gap between
        // this and instructions-retired is the speculation tax.
        for (int w = 0; w < FETCH_WORDS; w++)
            perf_fetch_valid[w] = dris_intake_pkts[w].valid_R;

        /* issue_pkts_reg, not issue_pkts: the registered copy is what the
         * exec ways actually chew on this cycle, so an issue group still
         * completing across a flush counts as busy (it really is occupying
         * the slot). Note these slots include the AGU pass of a load/store —
         * memory is two-phase here, so a memory op occupies an integer slot
         * once for its address and then a memory way for the access. */
        for (int e = 0; e < EXEC_UNITS; e++)
            perf_int_busy[e] = issue_pkts_reg[e].ready_I;

        for (int w = 0; w < MEM_ISSUE_WAYS; w++)
            perf_mem_busy[w] = mem_issue_pkts[w].core_req_re |
                               mem_issue_pkts[w].core_req_we;
    end : perf_vectors

    // ----- Per-cycle counts --------------------------------------------
    int perf_retired_now, perf_fetched_now, perf_dris_occ;
    int perf_int_used_now, perf_mem_used_now;
    // Instruction mix, counted at *retirement* (not at issue, where the
    // two-phase memory path would double-count) over the whole DRIS,
    // because retire_vector is entry-indexed.
    int perf_ret_alu, perf_ret_load, perf_ret_store, perf_ret_ct;

    always_comb begin : perf_counts
        perf_retired_now  = $countones(retire_vector);
        perf_fetched_now  = $countones(perf_fetch_valid);
        perf_dris_occ     = $countones(perf_dris_valid);
        perf_int_used_now = $countones(perf_int_busy);
        perf_mem_used_now = $countones(perf_mem_busy);

        perf_ret_alu   = 0;
        perf_ret_load  = 0;
        perf_ret_store = 0;
        perf_ret_ct    = 0;
        for (int i = 0; i < DRIS_NUM_ENTRIES; i++) begin
            if (retire_vector[i]) begin
                if (dris_entries[i].ctrl_signals.pc_source != PC_plus4)
                    perf_ret_ct++;
                else if (dris_entries[i].ctrl_signals.memRead)
                    perf_ret_load++;
                else if (dris_entries[i].ctrl_signals.memWrite)
                    perf_ret_store++;
                else
                    perf_ret_alu++;
            end
        end
    end : perf_counts

    /* Counters that accumulate a per-cycle *count* rather than a 0/1 event
     * are `longint`: their ceiling is cycles x capacity, and capacity is a
     * swept knob. At the defaults (32 DRIS entries, 20M-cycle watchdog)
     * dris_occ_total tops out around 640M, but LTG_DRIS_ENTRIES=128 would
     * push it past a signed 32-bit int and silently wrap. Plain cycle/event
     * counters stay `int` — they can't exceed elapsed_cycles.
     * Both simulators handle longint and %0d on it. */

    // ----- Cycle / instruction counts -----------------------------------
    int     elapsed_cycles;
    longint retired_total;      // $countones(retire_vector) summed
    longint fetched_total;      // DRIS intakes summed (wrong path included)
    int     fetch_groups;       // I$ responses accepted into the DRIS
    int ALU_inst_num, Lx_inst_num, Sx_inst_num, CT_inst_num;

    // ----- Front-end blocking / recovery --------------------------------
    int intake_stall_cycles;    // a fetch group was held at the FIFO head
    int stall_dris_full;        //   ...because the DRIS had no room
    int stall_shelf_full;       //   ...because the branch shelf had none
    int retire_drought_cycles;  // nothing retired at all
    int flush_cycles;           // a flush mask was live
    int mispredict_pulses;      // mispredict redirects taken

    // ----- Branches (resolved at the shelf, not at retirement) ----------
    int branches_resolved, branches_mispredicted, branches_mispredict_squashed;

    // ----- Cache counters (from the always-present wrapper ports) -------
    int eviction_i, hits_i, miss_i;
    int eviction_d, hits_d, miss_d;
    int num_i_cache, num_d_cache, num_conflicts;

    // ----- OoO utilization ----------------------------------------------
    int     retire_hist[RETIRES_PER_CYCLE+1];  // retires-per-cycle distribution
    int     int_issue_hist[EXEC_UNITS+1];      // integer slots used per cycle
    longint dris_occ_total;
    int     dris_occ_max, dris_full_cycles;
    longint shelf_occ_total;
    int     shelf_occ_max, shelf_full_cycles;
    longint int_slots_used, mem_slots_used;

    // Set once the printout has been emitted, so the `final` fallback below
    // doesn't print a second time over a normal halting run. Blocking-
    // assigned and cleared in reset for the same reasons as
    // commit_verifier.sv's `dumped`: the `final` block has to observe it
    // without waiting for an NBA update, and VCS counts a declaration
    // initializer as a second driver.
    logic perf_printed;

    // --------------------------------------------------------------------
    // Pretty-printer
    //
    // halt_reached distinguishes a normal end-of-run from the watchdog
    // fallback, and decides whether the halting ecall counts as retired: it
    // never reaches a retire slot (the SSC traps on it at the head instead),
    // but the reference simulator does execute it, so counting it keeps
    // `instructions retired` equal to the refsim count and to the commit
    // trace's line count.
    //
    // Shared metrics keep the in-order core's exact `$display` strings so
    // one set of scripts/cache_sweep.py PERF_PATTERNS parses both cores.
    // --------------------------------------------------------------------
    function automatic real perf_ratio(input longint num, input longint den);
        return (den == 0) ? 0.0 : real'(num) / real'(den);
    endfunction

    task automatic print_perf_metrics(input logic halt_reached);
        longint total_retired;
        total_retired = retired_total + (halt_reached ? 64'd1 : 64'd0);

        $display("\t\t PERFORMANCE METRICS (Lightning OoO):");
        if (!halt_reached)
            $display({"\t !! run ended without a halting ecall (watchdog or ",
                      "early $finish); counters are the state at the cutoff"});

        $display("\t total cycles:              %0d", elapsed_cycles);
        $display("\t instructions retired:      %0d", total_retired);
        $display("\t instructions fetched:      %0d", fetched_total);
        $display("\t fetch groups accepted:     %0d", fetch_groups);
        $display("\t IPC:                       %0.3f",
                 perf_ratio(total_retired, elapsed_cycles));
        $display("\t CPI:                       %0.3f",
                 perf_ratio(elapsed_cycles, total_retired));
        $display("\t speculation tax (fetched/retired): %0.3f",
                 perf_ratio(fetched_total, total_retired));

        $display("\t Front end:");
        $display("\t  intake stall cycles:      %0d", intake_stall_cycles);
        $display("\t   DRIS full:               %0d", stall_dris_full);
        $display("\t   branch shelf full:       %0d", stall_shelf_full);
        $display("\t  flush cycles:             %0d", flush_cycles);
        $display("\t  mispredict redirects:     %0d", mispredict_pulses);
        $display("\t  cycles with no retire:    %0d", retire_drought_cycles);

        $display("\t Non-Control Flow Types (at retirement):");
        $display("\t  ALU:    %0d", ALU_inst_num);
        $display("\t  Loads:  %0d", Lx_inst_num);
        $display("\t  Stores: %0d", Sx_inst_num);
        $display("\t  Control transfers: %0d", CT_inst_num);

        /* Three numbers, because they are three different things:
         *   resolved     — branches/JALRs the shelf decided
         *   mispredicted — of those, how many had guessed wrong
         *   squashed     — of *those*, how many were themselves wrong-path
         *                  (an older branch's flush reached them first), so
         *                  they never caused a redirect
         * "mispredict redirects" under Front end above is therefore
         * mispredicted - squashed, give or take one still in flight when
         * the run ends. */
        $display("\t Branches (resolved at the shelf):");
        $display("\t  resolved:      %0d", branches_resolved);
        $display("\t  mispredicted:  %0d", branches_mispredicted);
        $display("\t   of which squashed by an older flush: %0d",
                 branches_mispredict_squashed);
        $display("\t  mispredict rate: %0.3f",
                 perf_ratio(branches_mispredicted, branches_resolved));

        $display("\t Retires per cycle:");
        $display("\t  avg: %0.3f  (max %0d/cycle)",
                 perf_ratio(retired_total, elapsed_cycles), RETIRES_PER_CYCLE);
        for (int i = 0; i <= RETIRES_PER_CYCLE; i++)
            $display("\t    [%0d]: %0d", i, retire_hist[i]);

        /* Occupancy here is the count of *valid* entries. The intake stall
         * uses a different quantity — `occupancy = fetch_ptr - retire_ptr`
         * against the incoming group_count — so intake blocks as soon as
         * fewer than a group's worth of slots are free, well before all
         * DRIS_NUM_ENTRIES are valid. "cycles full" below is therefore a
         * strict subset of the "DRIS full" line under Front end, and that
         * line is the one to act on. */
        $display("\t DRIS utilization (of %0d entries, valid-entry count):",
                 DRIS_NUM_ENTRIES);
        $display("\t  avg: %0.3f  max: %0d  cycles at capacity: %0d",
                 perf_ratio(dris_occ_total, elapsed_cycles),
                 dris_occ_max, dris_full_cycles);
        $display({"\t   (intake blocks before this — see \"DRIS full\" ",
                  "under Front end for the actionable number)"});

        $display("\t Branch shelf utilization (of %0d entries):",
                 DRIS_defs::BRANCH_SHELF_ENTRIES);
        $display("\t  avg: %0.3f  max: %0d  cycles full: %0d",
                 perf_ratio(shelf_occ_total, elapsed_cycles),
                 shelf_occ_max, shelf_full_cycles);

        $display("\t Scheduler utilization:");
        $display("\t  integer slots used/cycle: %0.3f of %0d (%0.1f%%)",
                 perf_ratio(int_slots_used, elapsed_cycles), EXEC_UNITS,
                 100.0 * perf_ratio(int_slots_used,
                                    longint'(elapsed_cycles) * EXEC_UNITS));
        $display({"\t   (includes AGU passes: a load/store occupies an ",
                  "integer slot for its address before its memory pass)"});
        for (int i = 0; i <= EXEC_UNITS; i++)
            $display("\t    [%0d]: %0d", i, int_issue_hist[i]);
        $display("\t  memory issues/cycle:      %0.3f of %0d",
                 perf_ratio(mem_slots_used, elapsed_cycles), MEM_ISSUE_WAYS);

        $display("\t Cache Counters:");
        $display("\t  I$ evictions: %0d | hits: %0d | misses: %0d",
                 eviction_i, hits_i, miss_i);
        $display("\t  D$ evictions: %0d | hits: %0d | misses: %0d",
                 eviction_d, hits_d, miss_d);
        $display("\t  I$ accesses:  %0d | D$ accesses: %0d",
                 num_i_cache, num_d_cache);
        /* Same definition (and the same $display string) as the in-order
         * core, which is why the wording is kept — but it is not a probe
         * count and hits+misses will not add up to it. choose_d_cache is
         * the main-memory port arbitration, so "D$ accesses" is cycles the
         * D-side owned the memory bus and "I$ accesses" is every other
         * cycle, idle ones included. Hits/misses above are the real per-
         * cache probe counts. */
        $display({"\t   (accesses = main-memory port arbitration cycles, ",
                  "not cache probes; see hits/misses above)"});
        $display("\t  I$/D$ conflicts: %0d", num_conflicts);
    endtask

    // --------------------------------------------------------------------
    // Counter update logic
    // --------------------------------------------------------------------
    always_ff @(posedge clock, negedge reset_n) begin : perf_metrics
        if (~reset_n) begin
            elapsed_cycles        <= 0;
            retired_total         <= 0;
            fetched_total         <= 0;
            fetch_groups          <= 0;
            ALU_inst_num          <= 0;
            Lx_inst_num           <= 0;
            Sx_inst_num           <= 0;
            CT_inst_num           <= 0;
            intake_stall_cycles   <= 0;
            stall_dris_full       <= 0;
            stall_shelf_full      <= 0;
            retire_drought_cycles <= 0;
            flush_cycles          <= 0;
            mispredict_pulses     <= 0;
            branches_resolved     <= 0;
            branches_mispredicted <= 0;
            branches_mispredict_squashed <= 0;
            eviction_i <= 0; hits_i <= 0; miss_i <= 0;
            eviction_d <= 0; hits_d <= 0; miss_d <= 0;
            num_i_cache <= 0; num_d_cache <= 0; num_conflicts <= 0;
            dris_occ_total <= 0; dris_occ_max <= 0; dris_full_cycles <= 0;
            shelf_occ_total <= 0; shelf_occ_max <= 0; shelf_full_cycles <= 0;
            int_slots_used <= 0; mem_slots_used <= 0;
            foreach (retire_hist[i])    retire_hist[i]    <= 0;
            foreach (int_issue_hist[i]) int_issue_hist[i] <= 0;
        end
        // Freeze on halt exactly like the in-order block: the machine keeps
        // clocking until the testbench's $finish, and those cycles would
        // otherwise pollute every average.
        else if (~halted) begin
            elapsed_cycles <= elapsed_cycles + 1;

            // ----- Part 1: throughput -----
            retired_total <= retired_total + perf_retired_now;
            fetched_total <= fetched_total + perf_fetched_now;
            if (perf_issue_fire) fetch_groups <= fetch_groups + 1;

            ALU_inst_num <= ALU_inst_num + perf_ret_alu;
            Lx_inst_num  <= Lx_inst_num  + perf_ret_load;
            Sx_inst_num  <= Sx_inst_num  + perf_ret_store;
            CT_inst_num  <= CT_inst_num  + perf_ret_ct;

            // ----- Part 1: front-end blocking / recovery -----
            if (perf_stall_pc)     intake_stall_cycles <= intake_stall_cycles + 1;
            if (perf_stall_dris_full)  stall_dris_full     <= stall_dris_full     + 1;
            if (perf_stall_shelf_full) stall_shelf_full    <= stall_shelf_full    + 1;
            if (perf_retired_now == 0) retire_drought_cycles <= retire_drought_cycles + 1;
            /* flush_vector, not clear_valid: clear_valid is retire | flush,
             * and a retirement is not a flush. */
            if (|flush_vector)         flush_cycles      <= flush_cycles      + 1;
            if (perf_mispredict_valid) mispredict_pulses <= mispredict_pulses + 1;

            // ----- Part 1: branches -----
            // Counted where the shelf decides them, not at retirement: a
            // mispredicted branch's wrong-path youngers never retire, and
            // the branch itself resolves cycles before it does.
            if (perf_branch_resolved)     branches_resolved     <= branches_resolved     + 1;
            if (perf_branch_mispredicted) branches_mispredicted <= branches_mispredicted + 1;
            if (perf_branch_mispredict_squashed)
                branches_mispredict_squashed <= branches_mispredict_squashed + 1;

            // ----- Part 1: caches -----
            if (is_eviction_i) eviction_i <= eviction_i + 1;
            if (read_hit_i)    hits_i     <= hits_i     + 1;
            if (read_miss_i)   miss_i     <= miss_i     + 1;
            if (is_eviction_d) eviction_d <= eviction_d + 1;
            if (read_hit_d)    hits_d     <= hits_d     + 1;
            if (read_miss_d)   miss_d     <= miss_d     + 1;
            if (choose_d_cache) num_d_cache <= num_d_cache + 1;
            else                num_i_cache <= num_i_cache + 1;
            if (i_d_conflict)   num_conflicts <= num_conflicts + 1;

            // ----- Part 2a: retires per cycle -----
            // The popcount is bounded by the SSC's retire window, but clamp
            // the histogram index anyway — an out-of-range unpacked write
            // would be silent.
            retire_hist[(perf_retired_now > RETIRES_PER_CYCLE)
                            ? RETIRES_PER_CYCLE : perf_retired_now]
                <= retire_hist[(perf_retired_now > RETIRES_PER_CYCLE)
                            ? RETIRES_PER_CYCLE : perf_retired_now] + 1;

            // ----- Part 2b: DRIS utilization -----
            dris_occ_total <= dris_occ_total + perf_dris_occ;
            if (perf_dris_occ > dris_occ_max) dris_occ_max <= perf_dris_occ;
            if (perf_dris_occ == DRIS_NUM_ENTRIES)
                dris_full_cycles <= dris_full_cycles + 1;

            // ----- Part 2c: branch shelf utilization -----
            // "cycles full" is exactly the condition that makes shelf_room
            // false and blocks intake.
            shelf_occ_total <= shelf_occ_total + int'(perf_shelf_occupancy);
            if (int'(perf_shelf_occupancy) > shelf_occ_max)
                shelf_occ_max <= int'(perf_shelf_occupancy);
            if (int'(perf_shelf_occupancy) == DRIS_defs::BRANCH_SHELF_ENTRIES)
                shelf_full_cycles <= shelf_full_cycles + 1;

            // ----- Part 2d: scheduler utilization -----
            int_slots_used <= int_slots_used + perf_int_used_now;
            mem_slots_used <= mem_slots_used + perf_mem_used_now;
            int_issue_hist[perf_int_used_now]
                <= int_issue_hist[perf_int_used_now] + 1;
        end
    end : perf_metrics

    /* Print on the halt edge. `halted` is the trap-at-retire-head condition,
     * and the testbench $finishes on the same edge after a #0, so this fires
     * before the run ends. Counters read here are their pre-edge values,
     * matching the in-order block. */
    always_ff @(posedge clock, negedge reset_n) begin : perf_print
        if (~reset_n) begin
            perf_printed = 1'b0;
        end
        else if (halted && !perf_printed) begin
            perf_printed = 1'b1;
            print_perf_metrics(1'b1);
        end
    end : perf_print

    /* Fallback for a run that ends any other way — in practice the watchdog
     * killing a core that never reached its halting ecall, which is exactly
     * the case tests/perf can hit. Same `dumped`-flag pattern as
     * commit_verifier.sv, and it works in both simulators. */
    final begin
        if (!perf_printed) print_perf_metrics(1'b0);
    end
`endif /* LTG_PERF */

endmodule : LightningCore

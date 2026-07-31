`default_nettype none

import DRIS_defs::*;
import RISCV_ISA::*;
import RISCV_UArch::*;  // Import microarchitecture parameters and definitions
import internal_defines_pkg::*;     // Control signals struct, ALU ops

/**
@brief DRIS module
@input clock, reset_n
@input fetch_pkts from fetch stage, one per fetch way
@input writeback_pkts from execute stage, one per execute way
@input set_dispatched bit vector from scheduler, one bit per entry to set dispatched bit on DRIS entries being issued
@input clear_valid bit vector from SSC, one bit per entry to clear valid bit on DRIS entries being retired
@input fetch_ptr from fetch stage, pointer to next DRIS entry to write fetched instructions into, includes color bit for wraparound logic
@output dris_entries, the entire DRIS visible to all stages for dependency checking, dispatching, and retirement
*/
module DRIS
 #(
    parameter int ENTRIES = DRIS_defs::DRIS_NUM_ENTRIES,
    parameter int EXEC_UNITS = DRIS_defs::EXECUTE_WAYS,
    parameter int REG_FILE_WRITE_PORTS = DRIS_defs::REG_FILE_WRITE_PORTS,
    parameter int MEMORY_WRITE_PORTS = DRIS_defs::MEMORY_WRITE_PORTS,
    parameter int MEMORY_READ_PORTS = DRIS_defs::MEMORY_READ_PORTS,
    parameter int FETCH_WAYS = DRIS_defs::FETCH_WAYS,
    // No branch-shelf port: the shelf verifies branches but never writes
    // the DRIS — exec ways are the sole producers of register-file-bound
    // data (JAL/JALR links ride result_data_W; next PCs ride next_pc_W).
    localparam int WRITEBACK_PORTS =
    EXEC_UNITS + MEMORY_READ_PORTS
    )(

    input  logic clock, reset_n,

    // fetch writes
    input  dris_intake_pkt_t [FETCH_WAYS-1:0] fetch_pkts,

    // writeback writes (result + executed + locker broadcast)
    input  dris_writeback_pkt_t [WRITEBACK_PORTS-1:0]   writeback_pkts,

    // scheduler writes dispatched bit (not one pointer, can be many disjoint)
    input  logic [DRIS_NUM_ENTRIES-1:0]             set_dispatched,

    // SSC clears valid on retirement
    input  logic [DRIS_NUM_ENTRIES-1:0]             clear_valid,

    //pointer to the DRIS entry to write fetched instructions into, includes color bit for wraparound
    // extra bit long to make color bit math easier
    input logic [DRIS_ID_WIDTH:0] fetch_ptr,

    //everybody needs to be able to see the entire dris
    output dris_entry_t dris_entries [ENTRIES-1:0]
    );

    dris_id_t [FETCH_WAYS-1:0] new_ids;
    logic     [DRIS_ID_WIDTH:0] full_id_tmp [FETCH_WAYS-1:0];
    always_comb begin : full_id_gen
        for (int i = 0; i < FETCH_WAYS; i++) begin
            new_ids[i] = slot_id(fetch_ptr, i);
        end
    end

    // track the lockers for the source registers of incoming instructions
    dris_locker_t [FETCH_WAYS-1:0] locker_1_comb, locker_2_comb;

    always_ff @(posedge clock, negedge reset_n) begin: DRIS_ff
        if (!reset_n) begin: reset_logic
            dris_entries <= '{default: '0};
        end: reset_logic
        
        else begin: array_update_logic

            for (int i = 0; i < FETCH_WAYS; i ++) begin: fetch_writes
                if (fetch_pkts[i].valid_R) begin
                    
                    `ifdef DEBUG
                        dris_entries[new_ids[i].id_index].debug_instr <= fetch_pkts[i].debug_instr_R;
                    `endif

                    // adding the incoming packet data to the dris
                    dris_entries[new_ids[i].id_index].pc    <= fetch_pkts[i].pc_R;
                    dris_entries[new_ids[i].id_index].rd           <= fetch_pkts[i].rd_R;
                    dris_entries[new_ids[i].id_index].rs1          <= fetch_pkts[i].rs1_R;
                    dris_entries[new_ids[i].id_index].rs2          <= fetch_pkts[i].rs2_R;
                    dris_entries[new_ids[i].id_index].ctrl_signals <= fetch_pkts[i].ctrl_signals_R;
                    dris_entries[new_ids[i].id_index].imm          <= fetch_pkts[i].imm_R;
                    
                    dris_entries[new_ids[i].id_index].id.id_index  <= new_ids[i].id_index;
                    dris_entries[new_ids[i].id_index].id.id_color  <= new_ids[i].id_color;
                    dris_entries[new_ids[i].id_index].id.id_valid  <= '1;

                    dris_entries[new_ids[i].id_index].entry_state        <= '0;
                    dris_entries[new_ids[i].id_index].entry_state.valid  <= '1;

                    // a recycled entry must not inherit the previous
                    // occupant's result_valid: compute_lockers reads it to
                    // decide whether dependents need to lock at all
                    dris_entries[new_ids[i].id_index].result <= '0;

                    // spooky locker logic (using the register renaming)
                    dris_entries[new_ids[i].id_index].locker_1 <= locker_1_comb[i];
                    dris_entries[new_ids[i].id_index].locker_2 <= locker_2_comb[i];
                end
            end: fetch_writes

            for (int i = 0; i < WRITEBACK_PORTS; i++) begin: writeback_writes
                // the target must still be valid: with the registered
                // execute stage, a wrong-path instruction can write back
                // the cycle after its entry was flushed — if that index
                // were already reallocated, an unguarded write would mark
                // the newborn entry executed with garbage
                if (writeback_pkts[i].valid_W &&
                    dris_entries[writeback_pkts[i].id_W.id_index].entry_state.valid) begin

                    /* No debug write-back of pc/instr here: intake already
                     * stored both (and neither field exists on the entry
                     * under the names this used to assign — it never
                     * compiled with DEBUG on). Copying them back from the
                     * writeback packet would also *clear* them for loads,
                     * whose data writeback is driven straight from the
                     * cache response and carries no instruction word. */

                    if ((writeback_pkts[i].ctrl_signals_W.memRead || writeback_pkts[i].ctrl_signals_W.memWrite) &&
                    ~dris_entries[writeback_pkts[i].id_W.id_index].entry_state.mem_addr_ready) begin
                        // AGU pass of a load/store: park the address in
                        // result_data for the memory scheduler, but do NOT
                        // publish a result — result_valid stays 0 and the
                        // unlock broadcast is suppressed, so dependents keep
                        // waiting for the load's *data* writeback. Publishing
                        // here hands dependents the address as their operand.
                        dris_entries[writeback_pkts[i].id_W.id_index].result.result_data <= writeback_pkts[i].result_data_W;
                        dris_entries[writeback_pkts[i].id_W.id_index].entry_state.mem_addr_ready <= '1;
                        dris_entries[writeback_pkts[i].id_W.id_index].entry_state.dispatched <= '0;
                    end else begin
                        dris_entries[writeback_pkts[i].id_W.id_index].result.result_data  <= writeback_pkts[i].result_data_W;
                        dris_entries[writeback_pkts[i].id_W.id_index].result.result_valid <= '1;
                        dris_entries[writeback_pkts[i].id_W.id_index].entry_state.executed <= '1;

                        // broadcasting unlock to all lockers watching this result
                        for (int j = 0; j < ENTRIES; j++) begin
                            if (dris_entries[j].entry_state.valid) begin
                                if (dris_entries[j].locker_1.locked         &&
                                    dris_entries[j].locker_1.locker_id      == writeback_pkts[i].id_W.id_index &&
                                    dris_entries[j].locker_1.locker_color   == writeback_pkts[i].id_W.id_color) begin
                                        dris_entries[j].locker_1.locked <= '0;
                                end
                                if (dris_entries[j].locker_2.locked         &&
                                    dris_entries[j].locker_2.locker_id      == writeback_pkts[i].id_W.id_index &&
                                    dris_entries[j].locker_2.locker_color   == writeback_pkts[i].id_W.id_color) begin
                                        dris_entries[j].locker_2.locked <= '0;
                                end
                            end
                        end
                    end

                    if ((writeback_pkts[i].ctrl_signals_W.syscall &&  writeback_pkts[i].result_data_W == 'd10) 
                    || writeback_pkts[i].ctrl_signals_W.illegal_instr) begin
                        dris_entries[writeback_pkts[i].id_W.id_index].entry_state.trap <= '1;
                    end
                end
            end: writeback_writes

            // setting dispatched bit (from schedulers)
            for (int i = 0; i < ENTRIES; i++) begin: dispatched_bit_set
                if (set_dispatched[i]) begin
                    dris_entries[i].entry_state.dispatched <= '1;
                end
            end: dispatched_bit_set

            // clearing valid bit on retirement (from ssc)
            for (int i = 0; i < ENTRIES; i++) begin: valid_bit_clear
                if (clear_valid[i]) begin
                    dris_entries[i].entry_state.valid <= '0;
                    dris_entries[i].id.id_valid <= '0;
                end
            end: valid_bit_clear

        end: array_update_logic
    end: DRIS_ff

    // decides how lockers initialize for entries when they first arrive from fetch
    dris_id_t dep1 [FETCH_WAYS-1:0];
    dris_id_t dep2 [FETCH_WAYS-1:0];
    logic fetch_group_dep1_valid [FETCH_WAYS-1:0];
    logic fetch_group_dep2_valid [FETCH_WAYS-1:0];
    logic dep1_completing_now [FETCH_WAYS-1:0];
    logic dep2_completing_now [FETCH_WAYS-1:0];

    // Same-cycle intake bypass: a dependent arriving from fetch in the exact
    // cycle its producer's completing writeback fires must not lock — the
    // unlock broadcast scans the *old* locker state, so it can't see the
    // newborn entry and the lock would never clear. An AGU-pass writeback
    // (load/store address, mem_addr_ready not yet set) doesn't count: it
    // publishes no result, so the dependent still needs to lock and wait
    // for the data writeback.
    function automatic logic completing_wb(dris_id_t dep);
        for (int p = 0; p < WRITEBACK_PORTS; p++) begin
            if (writeback_pkts[p].valid_W &&
                writeback_pkts[p].id_W.id_index == dep.id_index &&
                writeback_pkts[p].id_W.id_color == dep.id_color &&
                !((writeback_pkts[p].ctrl_signals_W.memRead ||
                   writeback_pkts[p].ctrl_signals_W.memWrite) &&
                  ~dris_entries[dep.id_index].entry_state.mem_addr_ready)) begin
                return 1'b1;
            end
        end
        return 1'b0;
    endfunction

    always_comb begin: locker_init_comb_logic

        for (int q = 0; q < FETCH_WAYS; q++) begin
            dep1[q] = {'0, '0, {DRIS_ID_WIDTH{1'b1}}}; // no dependency on x0
            dep2[q] = {'0, '0, {DRIS_ID_WIDTH{1'b1}}}; // no dependency on x0
            fetch_group_dep1_valid[q] = '0;
            fetch_group_dep2_valid[q] = '0;
        end

        for (int i = 0; i < FETCH_WAYS; i++) begin
            if (fetch_pkts[i].valid_R) begin
                dep1[i] = dependency_in_dris(fetch_pkts[i].rs1_R, new_ids[i], dris_entries);
                // check earlier ways in same fetch group — older than new_ids[i] but younger than anything in dris_entries
                for (int j = 0; j < i; j++) begin
                    if (fetch_pkts[j].valid_R &&
                        fetch_pkts[j].rd_R == fetch_pkts[i].rs1_R &&
                        fetch_pkts[j].rd_R != '0) begin
                            dep1[i] = new_ids[j]; // younger writer wins
                            fetch_group_dep1_valid[i] = '1;
                        end
                end

                dep2[i] = dependency_in_dris(fetch_pkts[i].rs2_R, new_ids[i], dris_entries);
                for (int j = 0; j < i; j++) begin
                    if (fetch_pkts[j].valid_R && 
                        fetch_pkts[j].rd_R == fetch_pkts[i].rs2_R &&
                        fetch_pkts[j].rd_R != '0) begin
                            dep2[i] = new_ids[j]; // younger writer wins
                            fetch_group_dep2_valid[i] = '1;
                    end
                end

                dep1_completing_now[i] = completing_wb(dep1[i]);
                dep2_completing_now[i] = completing_wb(dep2[i]);

                locker_1_comb[i].locker_id      = dep1[i].id_index;
                locker_1_comb[i].locker_color   = dep1[i].id_color;

                locker_1_comb[i].locked         =
                (dep1[i].id_valid &
                dris_entries[dep1[i].id_index].entry_state.valid &
                !dris_entries[dep1[i].id_index].result.result_valid &
                !dep1_completing_now[i]) |
                fetch_group_dep1_valid[i]; // intra-fetch-group dependency always locks

                locker_1_comb[i].locker_valid   = dep1[i].id_valid;

                locker_2_comb[i].locker_id      = dep2[i].id_index;
                locker_2_comb[i].locker_color   = dep2[i].id_color;

                // only lock if there is a valid dependency, the entry is still in flight,
                // and the result isn't already available (or completing this very cycle)
                locker_2_comb[i].locked         =
                (dep2[i].id_valid &
                dris_entries[dep2[i].id_index].entry_state.valid &
                !dris_entries[dep2[i].id_index].result.result_valid &
                !dep2_completing_now[i]) |
                fetch_group_dep2_valid[i]; // intra-fetch-group dependency always locks
                locker_2_comb[i].locker_valid   = dep2[i].id_valid;
            end else begin
                locker_1_comb[i] = '0;
                locker_2_comb[i] = '0;
            end
        end
    end: locker_init_comb_logic

endmodule: DRIS

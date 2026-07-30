`default_nettype none

import DRIS_defs::*;
import RISCV_ISA::*;
import RISCV_UArch::*;  // Import microarchitecture parameters and definitions
import internal_defines_pkg::*;     // Control signals struct, ALU ops

module SaneStateController #(
    parameter int REG_FILE_WRITE_PORTS = DRIS_defs::REG_FILE_WRITE_PORTS,
    parameter int MEMORY_WRITE_PORTS = DRIS_defs::MEMORY_WRITE_PORTS,
    parameter int REG_RETIRES_PER_CYCLE = DRIS_defs::REG_FILE_WRITE_PORTS,
    parameter int MEMORY_RETIRES_PER_CYCLE = DRIS_defs::MEMORY_WRITE_PORTS,

    localparam int RETIRES_PER_CYCLE = REG_RETIRES_PER_CYCLE + MEMORY_RETIRES_PER_CYCLE
    )(
    input  logic clock, reset_n,

    // View of the entire DRIS
    input  dris_entry_t dris_entries [DRIS_NUM_ENTRIES-1:0],

    // Retire pointer is driven by the SSC
    output logic [DRIS_ID_WIDTH:0] retire_ptr,

    // Branch shelf: oldest speculative branch fence
    input  dris_id_t oldest_branch_id,
    input  logic     branch_fence_valid,

    // //in from branch shelf, flush from branch shelf on mispredict
    input  logic [DRIS_NUM_ENTRIES-1:0] flush_mask,

    input logic d_cache_ready,
    //out to dris, clears valid bits of retired or mispredicted instructions
    output logic [DRIS_NUM_ENTRIES-1:0] retire_vector,
    output logic [DRIS_NUM_ENTRIES-1:0] flush_vector,

    //only one store per cycle, is the oldest entry in the dris
    output logic store_ready,
    output dris_id_t store_id,

    // Retirement outputs → register file
    output reg_file_commit_pkt_t  [REG_RETIRES_PER_CYCLE-1:0]  reg_commits,

    // Trap output → CSR/trap handler
    output logic        trap_valid,
    output logic [XLEN-1:0] trap_pc,
    output dris_id_t    trap_id
);

    logic [RETIRES_PER_CYCLE-1:0] retire_ready_vector;

    always_ff @(posedge clock, negedge reset_n) begin
        if (~reset_n) retire_ptr <= '0;
        else begin
            // advance retire pointer by the number of instructions retiring this cycle
            retire_ptr <= retire_ptr + $countones(retire_ready_vector);
        end
    end

    // DRIS index of the n-th retirement slot, counting from the retire pointer.
    function automatic logic [DRIS_ID_WIDTH-1:0] retire_slot_index(input int slot);
        return (retire_ptr + slot) % DRIS_NUM_ENTRIES;
    endfunction

    dris_entry_t entries_checked [RETIRES_PER_CYCLE-1:0];
    genvar entry_check_genvar;
    generate
        for (entry_check_genvar = 0; entry_check_genvar < RETIRES_PER_CYCLE; entry_check_genvar++) begin: entries_checked_gen
            assign entries_checked[entry_check_genvar] =
            dris_entries[retire_slot_index(entry_check_genvar)];
        end
    endgenerate

    // An entry is eligible to retire if it's valid, executed, not trapped,
    // older than the oldest speculative branch (if the fence is up), and not
    // being flushed this cycle. The flush check matters on the exact cycle a
    // branch resolves WRONG: it leaves UNDET so the fence lifts, but its
    // wrong-path youngers are only *being* cleared — without the mask they'd
    // retire (corrupting the register file) and push retire_ptr past the IIU's
    // fetch_ptr rollback point, wrapping occupancy and wedging intake forever.
    function automatic logic entry_eligible(input dris_entry_t entry,
                                            input logic        flushing);
        return entry.entry_state.valid
            && entry.entry_state.executed
            && !entry.entry_state.trap
            && !flushing
            && ~entry.ctrl_signals.memWrite
            && (~branch_fence_valid || is_older(entry.id, oldest_branch_id));
    endfunction

    always_comb begin : retire_scan
        retire_ready_vector = '0;

        for (int slot = 0; slot < RETIRES_PER_CYCLE; slot++) begin
            if (slot == 0) begin
                retire_ready_vector[slot] = entry_eligible(entries_checked[slot], flush_mask[retire_slot_index(slot)])
                //overide the not ready if a store case for only the oldest entry
                | (store_ready & d_cache_ready);
            end
            else begin
                retire_ready_vector[slot] = entry_eligible(entries_checked[slot], flush_mask[retire_slot_index(slot)])
                && retire_ready_vector[slot-1];
            end
        end // for slots
    end: retire_scan


    genvar reg_commit_genvar;
    generate
        for (reg_commit_genvar = 0; reg_commit_genvar < REG_RETIRES_PER_CYCLE; reg_commit_genvar++) begin: reg_commits_gen
            // dris_entry_t entry_to_commit;
            // assign entry_to_commit = entries_checked[reg_commit_genvar];
            // reg_file_commit_pkt_t commit_pkt;
            // assign commit_pkt = reg_commits[reg_commit_genvar];

            always_comb begin
                reg_commits[reg_commit_genvar] = '0; // default to invalid
                if (reg_commit_genvar < REG_RETIRES_PER_CYCLE &&
                    retire_ready_vector[reg_commit_genvar] &&
                    entries_checked[reg_commit_genvar].ctrl_signals.rfWrite) begin
                        // populate reg_commits based on the entry's information

                        `ifdef DEBUG
                            reg_commits[reg_commit_genvar].debug_instr_regfile_C = entries_checked[reg_commit_genvar].instr;
                            reg_commits[reg_commit_genvar].debug_pc_regfile_C = entries_checked[reg_commit_genvar].pc;
                        `endif
                        reg_commits[reg_commit_genvar].valid_C = 1'b1;
                        reg_commits[reg_commit_genvar].rd_C = entries_checked[reg_commit_genvar].rd;
                        reg_commits[reg_commit_genvar].rd_data_C = entries_checked[reg_commit_genvar].result.result_data;
                end
            end
        end
    endgenerate

    //now the ssc dumps the raw retire or flush data and
    //the other modules figure out what to do with it themselves.
    //
    // Both vectors are DRIS-ENTRY-indexed, not slot-indexed: retire_ready_vector
    // is a window counted from retire_ptr, so it has to be scattered back onto
    // entry indices before anyone can use it. Every consumer (DRIS clear_valid,
    // MemoryScheduler's store gate) indexes by entry, and flush_mask already
    // arrives entry-indexed — so a raw slot-indexed retire_vector would clear
    // the wrong entries for any retire_ptr != 0.
    always_comb begin: retire_vector_scatter
        retire_vector = '0;
        for (int slot = 0; slot < RETIRES_PER_CYCLE; slot++)
            retire_vector[retire_slot_index(slot)] |= retire_ready_vector[slot];
    end: retire_vector_scatter

    assign flush_vector = flush_mask;
    
    assign trap_valid =
    entries_checked[0].entry_state.valid &&
    entries_checked[0].entry_state.trap &&
    (is_older(entries_checked[0].id, oldest_branch_id) || ~branch_fence_valid);

    assign trap_pc = entries_checked[0].pc;
    assign trap_id = entries_checked[0].id;

    assign store_ready = dris_entries[retire_ptr[DRIS_ID_WIDTH-1:0]].entry_state.valid &&
                         dris_entries[retire_ptr[DRIS_ID_WIDTH-1:0]].ctrl_signals.memWrite &&
                         dris_entries[retire_ptr[DRIS_ID_WIDTH-1:0]].entry_state.mem_addr_ready;

    assign store_id = dris_entries[retire_ptr[DRIS_ID_WIDTH-1:0]].id;


function automatic dris_id_t get_oldest_trap_id();
    // logic to find the oldest trap among the entries checked for retirement
    dris_id_t oldest_id;
    oldest_id.id_valid = '0; // default to invalid if no traps found

    for (int i = 0; i < RETIRES_PER_CYCLE; i++) begin
        if (entries_checked[i].entry_state.valid && entries_checked[i].entry_state.trap) begin
            if (!oldest_id.id_valid || is_older(entries_checked[i].id, oldest_id)) begin
                oldest_id = entries_checked[i].id;
                oldest_id.id_valid = '1;
            end
        end
    end

    return oldest_id;
endfunction

endmodule: SaneStateController

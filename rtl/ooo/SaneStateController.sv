`default_nettype none

import DRIS_defs::*;
import RISCV_ISA::*;
import RISCV_UArch::*;  // Import microarchitecture parameters and definitions
import internal_defines_pkg::*;     // Control signals struct, ALU ops

module SaneStateController #(
    parameter int REG_FILE_WRITE_PORTS = DRIS_defs::REG_FILE_WRITE_PORTS,
    parameter int MEMORY_WRITE_PORTS = DRIS_defs::MEMORY_WRITE_PORTS,
    parameter int RETIRES_PER_CYCLE = DRIS_defs::REG_FILE_WRITE_PORTS
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
    //out to dris, clears valid bits of retired or mispredicted instructions
    output logic [DRIS_NUM_ENTRIES-1:0] clear_valid,

    // Retirement outputs → register file
    output reg_file_commit_pkt_t  [RETIRES_PER_CYCLE-1:0]  reg_commits,

    //patent states that memory is only allowed to be written
    //when it is the oldest instruction
    output logic mem_write_valid,
    output dris_id_t mem_write_id,

    // Trap output → CSR/trap handler
    output logic        trap_valid,
    output logic [XLEN-1:0] trap_pc,
    output dris_id_t    trap_id
);

    always_ff @(posedge clock, negedge reset_n) begin
        if (~reset_n) retire_ptr <= '0;
        else begin
            // advance retire pointer by the number of instructions retiring this cycle
            retire_ptr <= retire_ptr + $countones(retire_ready_vector);
        end
    end

    dris_entry_t entries_checked [RETIRES_PER_CYCLE-1:0];
    genvar entry_check_genvar;
    generate
        for (entry_check_genvar = 0; entry_check_genvar < RETIRES_PER_CYCLE; entry_check_genvar++) begin: entries_checked_gen
            assign entries_checked[entry_check_genvar] =
            dris_entries[(retire_ptr + entry_check_genvar) % DRIS_NUM_ENTRIES];
        end
    endgenerate

    logic [RETIRES_PER_CYCLE-1:0] retire_ready_vector;
    genvar retire_check_genvar;
    generate
        for (retire_check_genvar = 0; retire_check_genvar < RETIRES_PER_CYCLE; retire_check_genvar++) begin: retire_ready_vector_gen
            // an entry is ready to retire if it's valid, executed, not trapped,
            // older than the oldest speculative branch (if it exists), and not
            // being flushed this cycle. The flush check matters on the exact
            // cycle a branch resolves WRONG: it leaves UNDET so the fence
            // lifts, but its wrong-path youngers are only *being* cleared —
            // without the mask they'd retire (corrupting the register file)
            // and push retire_ptr past the IIU's fetch_ptr rollback point,
            // wrapping occupancy and wedging intake forever.
            /* now this is recursive — genvar-constant condition hoisted to a
             * generate-if so the k==0 instance never elaborates the dead
             * [k-1] select (Verilator SELRANGE). Same logic either way. */
            if (retire_check_genvar == 0) begin : head
                always_comb begin : retire_vector_logic
                    retire_ready_vector[retire_check_genvar] =
                    entries_checked[retire_check_genvar].entry_state.valid &&
                    entries_checked[retire_check_genvar].entry_state.executed &&
                    !entries_checked[retire_check_genvar].entry_state.trap &&
                    !flush_mask[(retire_ptr + retire_check_genvar) % DRIS_NUM_ENTRIES] &&
                    (is_older(entries_checked[retire_check_genvar].id, oldest_branch_id) || ~branch_fence_valid);
                end: retire_vector_logic
            end else begin : chain
                always_comb begin : retire_vector_logic
                    retire_ready_vector[retire_check_genvar] =
                    entries_checked[retire_check_genvar].entry_state.valid &&
                    entries_checked[retire_check_genvar].entry_state.executed &&
                    !entries_checked[retire_check_genvar].entry_state.trap &&
                    !flush_mask[(retire_ptr + retire_check_genvar) % DRIS_NUM_ENTRIES] &&
                    (is_older(entries_checked[retire_check_genvar].id, oldest_branch_id) || ~branch_fence_valid) &&
                    retire_ready_vector[retire_check_genvar - 1]; // previous instruction must also be ready to retire
                end: retire_vector_logic
            end
        end
    endgenerate

    // logic to generate reg_commits and mem_commits based on retire_ready_vector and entries_checked
    // prioritize older instructions for commit
    genvar reg_commit_genvar;
    generate
        for (reg_commit_genvar = 0; reg_commit_genvar < RETIRES_PER_CYCLE; reg_commit_genvar++) begin: reg_commits_gen
            // dris_entry_t entry_to_commit;
            // assign entry_to_commit = entries_checked[reg_commit_genvar];
            // reg_file_commit_pkt_t commit_pkt;
            // assign commit_pkt = reg_commits[reg_commit_genvar];

            always_comb begin
                reg_commits[reg_commit_genvar] = '0; // default to invalid
                if (reg_commit_genvar < RETIRES_PER_CYCLE &&
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

    always_comb begin: clear_valid_logic
        clear_valid = flush_mask;  // start with flush
        for (int i = 0; i < RETIRES_PER_CYCLE; i++)
            clear_valid[(retire_ptr + i) % DRIS_NUM_ENTRIES] |= retire_ready_vector[i]; // add retired instructions to clear mask
    end

    assign mem_write_valid = retire_ready_vector[0] && entries_checked[0].ctrl_signals.memWrite;
    assign mem_write_id = entries_checked[0].id;

    assign trap_valid =
    entries_checked[0].entry_state.valid &&
    entries_checked[0].entry_state.trap &&
    (is_older(entries_checked[0].id, oldest_branch_id) || ~branch_fence_valid);

    assign trap_pc = entries_checked[0].pc;
    assign trap_id = entries_checked[0].id;


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

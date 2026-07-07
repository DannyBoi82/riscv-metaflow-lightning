`default_nettype none

import DRIS_defs::*;
import RISCV_ISA::*;
import RISCV_UArch::*;  // Import microarchitecture parameters and definitions
import internal_defines_pkg::*;     // Control signals struct, ALU ops

module Scheduler #(
    parameter int EXEC_UNITS = DRIS_defs::EXECUTE_WAYS,
    parameter int REG_FILE_WRITE_PORTS = DRIS_defs::REG_FILE_WRITE_PORTS,
    parameter int MEMORY_WRITE_PORTS = DRIS_defs::MEMORY_WRITE_PORTS,
    parameter int ENTRIES_CHECKED = SCHEDULER_ENTRIES_CHECKED
    )(
    input  logic clock, reset_n,

    // scheduler looks at ENTRIES_CHECKED entries to see what to dispatch each cycle
    input  dris_entry_t dris_entries [DRIS_NUM_ENTRIES-1:0],

    //use th retire pointer to figure out where to start looking for the oldest instructions
    input logic [DRIS_ID_WIDTH-1:0] retire_ptr,

    // packets outbound to execution units
    output issue_pkt_t issue_pkts [EXEC_UNITS-1:0],
    
    //need to tell dris which instructions are being dispatched
    output logic [DRIS_NUM_ENTRIES-1:0] set_dispatched,

    //if the locker dependencies arent valid, 
    //we need to read from the register file
    output logic [EXEC_UNITS-1:0] read_rf,
    output logic [REG_NUM_WIDTH-1:0] rs1_addr [EXEC_UNITS-1:0],
    output logic [REG_NUM_WIDTH-1:0] rs2_addr [EXEC_UNITS-1:0],
    input logic [XLEN-1:0] rs1_data [EXEC_UNITS-1:0],
    input logic [XLEN-1:0] rs2_data [EXEC_UNITS-1:0]

);
    
    //number of instructions issuing this cycle
    int unsigned issue_count;

    dris_entry_t entries_checked [ENTRIES_CHECKED-1:0];
    genvar entry_check_genvar;
    generate
        for (entry_check_genvar = 0; entry_check_genvar < ENTRIES_CHECKED; entry_check_genvar++) begin: entries_checked_gen
            assign entries_checked[entry_check_genvar] =
            dris_entries[(retire_ptr + entry_check_genvar) % DRIS_NUM_ENTRIES];
        end
    endgenerate

    logic [ENTRIES_CHECKED-1:0] ready_vector;
    genvar ready_check_genvar;
    generate
        for (ready_check_genvar = 0; ready_check_genvar < ENTRIES_CHECKED; ready_check_genvar++) begin: ready_vector_gen
            // an entry is ready if it's valid, not dispatched, and its lockers are not locked
            assign ready_vector[ready_check_genvar] =
             entries_checked[ready_check_genvar].entry_state.valid &&
            !entries_checked[ready_check_genvar].entry_state.dispatched &&
            !entries_checked[ready_check_genvar].locker_1.locked &&
            !entries_checked[ready_check_genvar].locker_2.locked;
        end
    endgenerate

    /* Selection comes before operand muxing: pick the oldest ready
     * window positions (up to EXEC_UNITS), then mux operands per exec
     * way on the *selected* entry. The operand arrays are way-sized, so
     * indexing them by raw window position — as the dispatch loop once
     * did — walks off the end for any pick past position EXEC_UNITS-1
     * (a silent out-of-bounds read: X operands in the issue packet). */
    logic [$clog2(ENTRIES_CHECKED)-1:0] sel_idx [EXEC_UNITS-1:0];
    logic [EXEC_UNITS-1:0]              sel_valid;

    always_comb begin: selection_logic
        // priority encoder to decide which instructions to issue
        // priority is based on age, which is determined by position in the circular buffer (lower index = older)
        // so we check from the retire pointer up to ENTRIES_CHECKED entries ahead for ready instructions, and issue the oldest ones we find, up to our issue width
        issue_count    = 0;
        sel_idx        = '{default: '0};
        sel_valid      = '0;
        set_dispatched = '0; // default all entries to not dispatched
        for (int i = 0; i < ENTRIES_CHECKED; i++) begin
            if (ready_vector[i] && issue_count < EXEC_UNITS) begin
                sel_idx[issue_count]   = ($clog2(ENTRIES_CHECKED))'(i);
                sel_valid[issue_count] = 1'b1;
                // tell the DRIS entry that it's being dispatched
                set_dispatched[(retire_ptr + i) % DRIS_NUM_ENTRIES] = 1'b1;
                issue_count++;
            end
        end
    end: selection_logic

    dris_entry_t sel_entries [EXEC_UNITS-1:0];
    genvar sel_entry_genvar;
    generate
        for (sel_entry_genvar = 0; sel_entry_genvar < EXEC_UNITS; sel_entry_genvar++) begin: sel_entries_gen
            assign sel_entries[sel_entry_genvar] = entries_checked[sel_idx[sel_entry_genvar]];
        end
    endgenerate

    dris_entry_t operand_source_entries [EXEC_UNITS-1:0][1:0]; // [which entry][which operand]
    genvar operand_source_genvar;
    generate
        for (operand_source_genvar = 0; operand_source_genvar < EXEC_UNITS; operand_source_genvar++) begin: operand_source_gen
            assign operand_source_entries[operand_source_genvar][0]
            = dris_entries[sel_entries[operand_source_genvar].locker_1.locker_id];
            assign operand_source_entries[operand_source_genvar][1]
            = dris_entries[sel_entries[operand_source_genvar].locker_2.locker_id];
        end
    endgenerate

    logic [XLEN-1:0] operand_1 [EXEC_UNITS-1:0];
    logic [XLEN-1:0] operand_2 [EXEC_UNITS-1:0];
    logic [XLEN-1:0] rs1_data_intermed [EXEC_UNITS-1:0];
    genvar operand_mux_genvar;
    generate
        for (operand_mux_genvar = 0; operand_mux_genvar < EXEC_UNITS; operand_mux_genvar++) begin: operand_mux_gen
            always_comb begin: operand_mux_logic

                read_rf[operand_mux_genvar] = '0;
                rs1_addr[operand_mux_genvar] = '0;
                rs2_addr[operand_mux_genvar] = '0;

                //src 1 mux -----------------------------------------------------------------------------
                if (sel_entries[operand_mux_genvar].locker_1.locker_valid) begin
                    operand_1[operand_mux_genvar] = operand_source_entries[operand_mux_genvar][0].result.result_data;
                    rs1_data_intermed[operand_mux_genvar] = operand_source_entries[operand_mux_genvar][0].result.result_data;
                end else begin
                    //get the operand from the register file
                    read_rf[operand_mux_genvar] = '1;
                    rs1_addr[operand_mux_genvar] = sel_entries[operand_mux_genvar].rs1;
                    operand_1[operand_mux_genvar] = rs1_data[operand_mux_genvar];
                    rs1_data_intermed[operand_mux_genvar] = rs1_data[operand_mux_genvar];
                end
                
                // use the PC if the instruction needs it. For JALR this is
                // the link setup: op_1 = PC with ALU_ADD4 makes alu_out the
                // pc+4 link, while the target's rs1 rides the issue packet's
                // dedicated rs1_data_I field (captured above, pre-override).
                if (sel_entries[operand_mux_genvar].ctrl_signals.usePC) begin
                    operand_1[operand_mux_genvar] = sel_entries[operand_mux_genvar].pc;
                end

                //src 2 mux -----------------------------------------------------------------------------
                if (sel_entries[operand_mux_genvar].locker_2.locker_valid) begin
                    operand_2[operand_mux_genvar] = operand_source_entries[operand_mux_genvar][1].result.result_data;
                end else begin
                    //get the operand from the register file
                    read_rf[operand_mux_genvar] = '1;
                    rs2_addr[operand_mux_genvar] = sel_entries[operand_mux_genvar].rs2;
                    operand_2[operand_mux_genvar] = rs2_data[operand_mux_genvar];
                end

                if (sel_entries[operand_mux_genvar].ctrl_signals.useImm) begin
                // if the instruction uses an immediate, we need to mux that in as the second operand instead of reading from the register file or the locker
                    operand_2[operand_mux_genvar] = sel_entries[operand_mux_genvar].imm;
                end

            end: operand_mux_logic

        end
    endgenerate

    always_comb begin: dispatch_logic
        issue_pkts = '{default: '0}; // default all fields to 0

        for (int e = 0; e < EXEC_UNITS; e++) begin
            if (sel_valid[e]) begin

                `ifdef DEBUG
                    issue_pkts[e].debug_instr_I = sel_entries[e].debug_instr;
                `endif

                issue_pkts[e].pc_I = sel_entries[e].pc;
                issue_pkts[e].imm_I = sel_entries[e].imm;
                issue_pkts[e].rs1_data_I = rs1_data_intermed[e];
                issue_pkts[e].ready_I = '1;
                issue_pkts[e].id_I = sel_entries[e].id;
                issue_pkts[e].ctrl_signals_I = sel_entries[e].ctrl_signals;
                issue_pkts[e].op_1_I = operand_1[e];
                issue_pkts[e].op_2_I = operand_2[e];
            end
        end

    end: dispatch_logic

endmodule: Scheduler

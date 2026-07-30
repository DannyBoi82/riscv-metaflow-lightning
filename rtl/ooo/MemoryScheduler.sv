`default_nettype none
`define UNIFIED_RW_PORTS

import DRIS_defs::*;
import RISCV_ISA::*;
import RISCV_UArch::*;  // Import microarchitecture parameters and definitions
import internal_defines_pkg::*;     // Control signals struct, ALU ops

module MemoryScheduler #(
    parameter int CACHE_READ_PORTS = DRIS_defs::MEMORY_READ_PORTS,
    parameter int CACHE_WRITE_PORTS = DRIS_defs::MEMORY_WRITE_PORTS,
    parameter int REG_FILE_WRITE_PORTS = DRIS_defs::REG_FILE_WRITE_PORTS,
    parameter int MEMORY_WRITE_PORTS = DRIS_defs::MEMORY_WRITE_PORTS,
    parameter int ENTRIES_CHECKED = DRIS_defs::SCHEDULER_ENTRIES_CHECKED,
    
    parameter int TOTAL_PORTS = CACHE_READ_PORTS + CACHE_WRITE_PORTS
    )(

    input logic clock, reset_n,

    input logic d_cache_ready,

    // scheduler looks at ENTRIES_CHECKED entries to see what to dispatch each cycle
    input  dris_entry_t dris_entries [DRIS_NUM_ENTRIES-1:0],

    //use th retire pointer to figure out where to start looking for the oldest instructions
    input logic [DRIS_ID_WIDTH-1:0] retire_ptr,
    input logic [DRIS_NUM_ENTRIES-1:0] retire_vector,

    input logic store_ready,
    input dris_id_t store_id,

    // packets outbound to execution units
    output  memory_issue_pkt_t  mem_issue_pkts [TOTAL_PORTS-1:0],
    
    //need to tell dris which instructions are being dispatched
    output logic [DRIS_NUM_ENTRIES-1:0] set_dispatched_mem,

    //if the locker dependencies arent valid,
    //we need to read from the register file
    output logic [TOTAL_PORTS-1:0] read_rf,
    output logic [REG_NUM_WIDTH-1:0] rs1_addr [TOTAL_PORTS-1:0],
    output logic [REG_NUM_WIDTH-1:0] rs2_addr [TOTAL_PORTS-1:0],
    input logic [XLEN-1:0] rs1_data [TOTAL_PORTS-1:0],
    input logic [XLEN-1:0] rs2_data [TOTAL_PORTS-1:0]

);

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

            //read entry ready case
            (entries_checked[ready_check_genvar].ctrl_signals.memRead &&
            entries_checked[ready_check_genvar].entry_state.valid &&
            !entries_checked[ready_check_genvar].entry_state.dispatched &&
            !entries_checked[ready_check_genvar].entry_state.executed &&
            entries_checked[ready_check_genvar].entry_state.mem_addr_ready)
            
            ||

            //write entry ready case
            (entries_checked[ready_check_genvar].id == store_id &&
            store_ready);
        end
    endgenerate

    /* Selection comes before operand muxing: pick the oldest ready
     * window positions (up to TOTAL_PORTS), then mux operands per exec
     * way on the *selected* entry. The operand arrays are way-sized, so
     * indexing them by raw window position — as the dispatch loop once
     * did — walks off the end for any pick past position TOTAL_PORTS-1
     * (a silent out-of-bounds read: X operands in the issue packet). */
    logic [$clog2(ENTRIES_CHECKED)-1:0] sel_idx [TOTAL_PORTS-1:0];
    logic [TOTAL_PORTS-1:0]              sel_valid;

    //TODO: needs to be modified for the memory invariants
    always_comb begin: selection_logic
        // priority encoder to decide which instructions to issue
        // priority is based on age, which is determined by position in the circular buffer (lower index = older)
        // so we check from the retire pointer up to ENTRIES_CHECKED entries ahead for ready instructions, and issue the oldest ones we find, up to our issue width
        issue_count    = 0;
        sel_idx        = '{default: '0};
        sel_valid      = '0;
        set_dispatched_mem = '0; // default all entries to not dispatched
        for (int i = 0; i < ENTRIES_CHECKED; i++) begin
            if (ready_vector[i] && issue_count < TOTAL_PORTS && d_cache_ready) begin

                if (entries_checked[i].ctrl_signals.memRead) begin
                   if (~check_older_writes(entries_checked[i].id)) begin
                        //cant dispatch, older writes exist that are not yet retired
                        continue;
                   end
                end else if (entries_checked[i].ctrl_signals.memWrite) begin
                    if (~retire_vector[(retire_ptr + i) % DRIS_NUM_ENTRIES]) begin
                        //either the cache is busy or there are younger instructions not yet retiried/retiring,
                        //so we cant dispatch this write yet
                        continue;
                    end
                end
                sel_idx[issue_count]   = ($clog2(ENTRIES_CHECKED))'(i);
                sel_valid[issue_count] = 1'b1;
                // tell the DRIS entry that it's being dispatched
                set_dispatched_mem[(retire_ptr + i) % DRIS_NUM_ENTRIES] = 1'b1;
                issue_count++;
            end
        end
    end: selection_logic

    function automatic logic check_older_writes(dris_id_t id);
        // logic to check if there are any older writes in the window that are not yet retired
        for (int i = 0; i < ENTRIES_CHECKED; i++) begin
            if (entries_checked[i].entry_state.valid &&
                entries_checked[i].ctrl_signals.memWrite &&
                is_older(entries_checked[i].id, id)) begin
                    if (~entries_checked[i].entry_state.mem_addr_ready) begin
                        //cant dispatch, impercise case 
                        //(an older write might write to the same address as this read)
                        return 1'b0;
                    end 
                    else if (entries_checked[i].entry_state.mem_addr_ready &&
                    entries_checked[i].result.result_data == dris_entries[id.id_index].result.result_data) begin
                        //cant dispatch, unsafe case
                        //(an older write is writing to the same address as this read)
                        return 1'b0;
                    end
            end
        end
        return 1'b1; //no older writes found, safe to dispatch

    endfunction

    // the window entry each issue slot actually picked (same pattern as
    // Scheduler.sv: select first, then read the selected entry — never index
    // a way-sized array by raw window position)
    dris_entry_t sel_entries [TOTAL_PORTS-1:0];
    genvar sel_entry_genvar;
    generate
        for (sel_entry_genvar = 0; sel_entry_genvar < TOTAL_PORTS; sel_entry_genvar++) begin: sel_entries_gen
            assign sel_entries[sel_entry_genvar] = entries_checked[sel_idx[sel_entry_genvar]];
        end
    endgenerate

    logic [XLEN-1:0] store_data [CACHE_WRITE_PORTS-1:0];

    `ifdef UNIFIED_RW_PORTS

        int unsigned issue_idx;
        always_comb begin: dispatch_logic
            mem_issue_pkts = '{default: '0}; // default all fields to 0
            read_rf  = '0;
            // The memory path never reads rs1: the address was already computed
            // by an ALU way in phase 1 and rides the entry's result field. Only
            // store data comes from the register file, on rs2.
            rs1_addr = '{default: '0};
            rs2_addr = '{default: '0};
            issue_idx = 0;
            for (int i = 0; i < TOTAL_PORTS; i++) begin
                if (sel_valid[i] && sel_entries[i].ctrl_signals.memWrite && issue_idx < TOTAL_PORTS) begin
                    
                    read_rf[issue_idx] = 1'b1;
                    rs2_addr[issue_idx] = sel_entries[i].rs2;
                    mem_issue_pkts[issue_idx].core_req_addr = sel_entries[i].result.result_data[31:2];
                    mem_issue_pkts[issue_idx].core_req_we = 1'b1;
                    mem_issue_pkts[issue_idx].core_req_re = 1'b0;
                    mem_issue_pkts[issue_idx].core_req_store_mask = get_store_mask(sel_entries[i].result.result_data, sel_entries[i].ctrl_signals);
                    mem_issue_pkts[issue_idx].core_req_store_data = get_store_data(rs2_data[issue_idx], sel_entries[i].result.result_data[1:0], sel_entries[i].ctrl_signals);
                    mem_issue_pkts[issue_idx].core_req_id = sel_entries[i].id;
                    mem_issue_pkts[issue_idx].core_req_ctrl_signals = sel_entries[i].ctrl_signals;
                    issue_idx++;
                end
            end

            for (int i = 0; i < TOTAL_PORTS; i++) begin
                if (sel_valid[i] && sel_entries[i].ctrl_signals.memRead && issue_idx < TOTAL_PORTS) begin
    
                    mem_issue_pkts[issue_idx].core_req_re = 1'b1;
                    mem_issue_pkts[issue_idx].core_req_addr = sel_entries[i].result.result_data[31:2];
                    mem_issue_pkts[issue_idx].core_req_we = 1'b0;
                    mem_issue_pkts[issue_idx].core_req_store_mask = 4'b0000;
                    mem_issue_pkts[issue_idx].core_req_store_data = '0;
                    mem_issue_pkts[issue_idx].core_req_id = sel_entries[i].id;
                    mem_issue_pkts[issue_idx].core_req_ctrl_signals = sel_entries[i].ctrl_signals;
                    issue_idx++;
                end
            end
        end

    `elsif SEPARATE_RW_PORTS
        /* Ports are split by direction: [0, CACHE_WRITE_PORTS) carry stores,
         * [CACHE_WRITE_PORTS, TOTAL_PORTS) carry loads. The read base is the
         * fixed CACHE_WRITE_PORTS, not the running write_idx — using the
         * latter would slide the load ports around as stores issue. */
        int unsigned read_idx;
        int unsigned write_idx;
        always_comb begin: dispatch_logic
            mem_issue_pkts = '{default: '0}; // default all fields to 0
            read_rf  = '0;
            rs1_addr = '{default: '0};   // memory path never reads rs1, see above
            rs2_addr = '{default: '0};
            read_idx = 0;
            write_idx = 0;
            for (int i = 0; i < TOTAL_PORTS; i++) begin
                if (sel_valid[i] && sel_entries[i].ctrl_signals.memWrite && write_idx < CACHE_WRITE_PORTS) begin

                    read_rf[write_idx] = 1'b1;
                    rs2_addr[write_idx] = sel_entries[i].rs2;
                    mem_issue_pkts[write_idx].core_req_addr = sel_entries[i].result.result_data[31:2];
                    mem_issue_pkts[write_idx].core_req_we = 1'b1;
                    mem_issue_pkts[write_idx].core_req_re = 1'b0;
                    mem_issue_pkts[write_idx].core_req_store_mask = get_store_mask(sel_entries[i].result.result_data, sel_entries[i].ctrl_signals);
                    mem_issue_pkts[write_idx].core_req_store_data = get_store_data(rs2_data[write_idx], sel_entries[i].result.result_data[1:0], sel_entries[i].ctrl_signals);
                    mem_issue_pkts[write_idx].core_req_id = sel_entries[i].id;
                    write_idx++;
                end else if (sel_valid[i] && sel_entries[i].ctrl_signals.memRead && read_idx < CACHE_READ_PORTS) begin

                    mem_issue_pkts[CACHE_WRITE_PORTS + read_idx].core_req_re = 1'b1;
                    mem_issue_pkts[CACHE_WRITE_PORTS + read_idx].core_req_addr = sel_entries[i].result.result_data[31:2];
                    mem_issue_pkts[CACHE_WRITE_PORTS + read_idx].core_req_we = 1'b0;
                    mem_issue_pkts[CACHE_WRITE_PORTS + read_idx].core_req_store_mask = 4'b0000;
                    mem_issue_pkts[CACHE_WRITE_PORTS + read_idx].core_req_store_data = '0;
                    mem_issue_pkts[CACHE_WRITE_PORTS + read_idx].core_req_id = sel_entries[i].id;
                    read_idx++;
                end
            end
        end: dispatch_logic
    `else
        // Fail elaboration rather than leave the D-side seam silently undriven.
        initial $fatal(1, "MemoryScheduler: must define either UNIFIED_RW_PORTS or SEPARATE_RW_PORTS");
    `endif

    function automatic logic [3:0] get_store_mask(logic [XLEN-1:0] addr, ctrl_signals_t ctrl_signals);
        if (~ctrl_signals.memWrite) begin
            return 4'b0000; //no store
        end else begin
            ldst_mode_t ldst_mode = ctrl_signals.ldst_mode;
            case (ldst_mode)
                LDST_B, LDST_BU:  return 4'b0001 << addr[1:0];
                LDST_H, LDST_HU:  return addr[1] ? 4'b1100 : 4'b0011;
                LDST_W:           return 4'b1111;
                default:          return 4'b0000; //invalid
            endcase
        end
    endfunction

    function automatic logic [XLEN-1:0] get_store_data(logic [XLEN-1:0] rs2_data, logic [1:0] byte_offset, ctrl_signals_t ctrl_signals);
        if (~ctrl_signals.memWrite) begin
            return '0; //no store
        end else begin
            ldst_mode_t ldst_mode = ctrl_signals.ldst_mode;
            logic [XLEN-1:0] data_store;
            if ((ldst_mode === LDST_B) || (ldst_mode === LDST_BU)) begin
                case (byte_offset)
                    2'd0: data_store = {24'd0, rs2_data[7:0]};
                    2'd1: data_store = {16'd0, rs2_data[7:0], 8'd0};
                    2'd2: data_store = {8'd0,  rs2_data[7:0], 16'd0};
                    2'd3: data_store = {       rs2_data[7:0], 24'd0};
                endcase
            end else if ((ldst_mode === LDST_H) || (ldst_mode === LDST_HU)) begin
                data_store = byte_offset[1]
                        ? {rs2_data[15:0], 16'd0}
                        : {16'd0,          rs2_data[15:0]};
            end else begin
                data_store = rs2_data;
            end
            return data_store;
        end
    endfunction

endmodule : MemoryScheduler

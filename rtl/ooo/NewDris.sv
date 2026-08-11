// `default_nettype none

// mport DRIS_defs::*;
// import RISCV_ISA::*;
// import RISCV_UArch::*;  // Import microarchitecture parameters and definitions
// import internal_defines_pkg::*;     // Control signals struct, ALU ops

// /**
// @brief DRIS module
// @input clock, reset_n
// @input fetch_pkts from fetch stage, one per fetch way
// @input writeback_pkts from execute stage, one per execute way
// @input set_dispatched bit vector from scheduler, one bit per entry to set dispatched bit on DRIS entries being issued
// @input clear_valid bit vector from SSC, one bit per entry to clear valid bit on DRIS entries being retired
// @input fetch_ptr from fetch stage, pointer to next DRIS entry to write fetched instructions into, includes color bit for wraparound logic
// @output dris_entries, the entire DRIS visible to all stages for dependency checking, dispatching, and retirement
// */
// module DRIS
//  #(
//     parameter int ENTRIES = DRIS_defs::DRIS_NUM_ENTRIES,
//     parameter int EXEC_UNITS = DRIS_defs::EXECUTE_WAYS,
//     parameter int REG_FILE_WRITE_PORTS = DRIS_defs::REG_FILE_WRITE_PORTS,
//     parameter int MEMORY_WRITE_PORTS = DRIS_defs::MEMORY_WRITE_PORTS,
//     parameter int MEMORY_READ_PORTS = DRIS_defs::MEMORY_READ_PORTS,
//     parameter int FETCH_WAYS = DRIS_defs::FETCH_WAYS,
//     // No branch-shelf port: the shelf verifies branches but never writes
//     // the DRIS — exec ways are the sole producers of register-file-bound
//     // data (JAL/JALR links ride result_data_W; next PCs ride next_pc_W).
//     localparam int WRITEBACK_PORTS =
//     EXEC_UNITS + MEMORY_READ_PORTS
//     )(

//     input  logic clock, reset_n,

//     // fetch writes
//     input  dris_intake_pkt_t [FETCH_WAYS-1:0] fetch_pkts,

//     // writeback writes (result + executed + locker broadcast)
//     input  dris_writeback_pkt_t [WRITEBACK_PORTS-1:0]   writeback_pkts,

//     // scheduler writes dispatched bit (not one pointer, can be many disjoint)
//     input  logic [DRIS_NUM_ENTRIES-1:0]             set_dispatched,

//     // SSC clears valid on retirement
//     input  logic [DRIS_NUM_ENTRIES-1:0]             clear_valid,

//     //pointer to the DRIS entry to write fetched instructions into, includes color bit for wraparound
//     // extra bit long to make color bit math easier
//     input logic [DRIS_ID_WIDTH:0] fetch_ptr,

//     //everybody needs to be able to see the entire dris
//     output dris_entry_t dris_entries [ENTRIES-1:0]
//     );

//     dris_id_t [FETCH_WAYS-1:0] new_ids;
//     always_comb begin : full_id_gen
//         for (int i = 0; i < FETCH_WAYS; i++) begin
//             new_ids[i] = slot_id(fetch_ptr, i);
//         end
//     end

//     dris_entry_t next_dris_entries [ENTRIES-1:0];

//     always_ff @(posedge clock or negedge reset_n) begin : dris_ff
//         if (!reset_n) begin
//             for (int i = 0; i < ENTRIES; i++) begin
//                 dris_entries[i] <= '0;
//             end
//         end else begin
//             for (int i = 0; i < ENTRIES; i++) begin
//                 dris_entries[i] <= next_dris_entries[i];
//             end
//         end
//     end

//     logic [WRITEBACK_PORTS-1:0] is_lw, is_sw;
//     dris_id_t [WRITEBACK_PORTS-1:0] wb_ids;
//     always_comb begin : wb_id_gen
//         for (int i = 0; i < WRITEBACK_PORTS; i++) begin
//             wb_ids[i] = writeback_pkts[i].id_W;
//             is_lw[i] = writeback_pkts[i].ctrl_signals.memRead;
//             is_sw[i] = writeback_pkts[i].ctrl_signals.memWrite;
//         end
//     end

//     genvar d;
//     generate
//         for (d = 0; d < ENTRIES; d++) begin : gen_dris_entries
//             dris_id_t entry_id = dris_entries[d].id;

//             always_comb begin : dris_entry_logic
//                 // default to current state
//                 next_dris_entries[d] = dris_entries[d];

//                 // SSC clears valid on retirement
//                 if (clear_valid[d]) next_dris_entries[d] = EMPTY_DRIS_ENTRY;

//                 //writeback writes
//                 for (int w = 0; w < WRITEBACK_PORTS; w++) begin
//                     if (wb_valid(w) && wb_ids[w] == entry_id) begin
                        
//                         if ((is_lw[w] || is_sw[w]) &&
//                         ~dris_entries[d].entry_state.mem_addr_ready) begin
//                             next_dris_entries[d].entry_state.mem_addr_ready = 1'b1;

//                             `ifdef DEBUG
//                                 dris_entries[d].debug_mem_addr = writeback_pkts[w].result.result_data_W;
//                             `endif
//                         end else begin
                            
//                             next_dris_entries[d].result_data = writeback_pkts[w].result.result_data_W;
//                             dris_entries[d].result.result_valid = 1'b1;
//                             next_dris_entries[d].entry_state.executed = 1'b1;
//                         end
//                     end
//                 end


//             end: dris_entry_logic
//         end: gen_dris_entries
//     endgenerate

//     function automatic logic wb_valid (int p);
//         automatic logic [DRIS_ID_WIDTH-1:0] idx = writeback_pkts[p].id_W.id_index;

//         if (!writeback_pkts[p].valid_W)                return 1'b0;
//         if (!dris_entries[idx].entry_state.valid)      return 1'b0;

//         // ports [EXEC_UNITS, WRITEBACK_PORTS) are the memory-read returns
//         if (p >= EXEC_UNITS)
//             return dris_entries[idx].ctrl_signals.memRead       &&
//                    dris_entries[idx].entry_state.mem_addr_ready &&
//                    dris_entries[idx].entry_state.dispatched     &&
//                    !dris_entries[idx].entry_state.executed;

//         return 1'b1;
//     endfunction

// endmodule : DRIS

// //list of things that a dris entry needs to react to:
// // 1. fetch writes (new instructions being fetched into the DRIS)
// // 2. writeback writes (instructions being executed and results being written back to the DRIS)
// // 3. scheduler writes (instructions being dispatched, set dispatched bit)
// // 4. SSC writes (instructions being retired, clear valid bit)

// //priority:
// // 1. SSC writes
// // 2. writeback writes
// // 3. scheduler writes
// // 4. fetch writes
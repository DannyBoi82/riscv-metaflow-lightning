// Local Includes
`include "riscv_isa.vh"                // Definition of word width and bytes
`include "riscv_uarch.vh"
`include "config.vh"                   // Centralized hardware configuration


//stages:
// fetch = F
// rename = R
// issue = I
// execute = E
// dris writeback = W
// commit = C

package DRIS_defs;

    import RISCV_ISA::XLEN, RISCV_ISA::REG_NUM_WIDTH;
    import internal_defines_pkg::*;

    // All values below come from the central config (rtl/include/config.vh)
    localparam int DRIS_NUM_ENTRIES  = `LTG_DRIS_ENTRIES;
    localparam int DRIS_ID_WIDTH     = $clog2(DRIS_NUM_ENTRIES);
    localparam int EXECUTE_WAYS = `LTG_EXECUTE_WAYS;
    localparam int FETCH_WAYS = `LTG_FETCH_WAYS;
    localparam int REG_FILE_WRITE_PORTS = `LTG_REG_FILE_WRITE_PORTS;   // wider than issue, per Lightning
    localparam int MEMORY_WRITE_PORTS   = `LTG_MEMORY_WRITE_PORTS;   // stores serialized by oldest constraint
    localparam int MEMORY_READ_PORTS    = `LTG_MEMORY_READ_PORTS;   // for load-store queue, not DRIS, but needed to size writeback array
    localparam int BRANCH_WAYS = `LTG_BRANCH_WAYS;         // how many branches can be in-flight at once, determines size of branch mask in issue unit and predictor
    localparam int BRANCH_SHELF_ENTRIES = `LTG_BRANCH_SHELF_ENTRIES;   // unresolved speculative branches the shelf can hold

    // how many entries the scheduler checks for ready-ness each cycle
    localparam int SCHEDULER_ENTRIES_CHECKED = `LTG_SCHED_ENTRIES_CHECKED;

    // Cache-seam widths. parameters.vh declares ADDRESS_SIZE/WORD_SIZE at
    // $unit scope, which a package cannot see, and including it here would
    // fire its L1_POLICIES guard before riscv_core_interface gets it. Derive
    // them from XLEN instead: the memory bus is word-addressed, so the
    // address drops the 2 byte-offset bits. Must track parameters.vh.
    localparam int MEM_WORD_SIZE    = XLEN;      // == WORD_SIZE (32)
    localparam int MEM_ADDRESS_SIZE = XLEN - 2;  // == ADDRESS_SIZE (30)


    typedef struct packed {
        logic valid;        // slot is occupied
        logic dispatched;   // sent to an execution unit
        logic executed;     // result field contains valid data
        logic trap;         // instruction raised a trap
        logic mem_addr_ready; // memory address has been computed (for loads/stores)
    } dris_entry_state_t;

    // no stage suffixes because they are used by all stages
    typedef struct packed {

        //1 if the dris id exists in the dris, 0 otherwise
        //used by some combinational logic to differentiate between finding something
        //and finding nothing
        logic id_valid;
        logic id_color;                                  // helps determine age (see comment at the end of this file)
        logic [DRIS_ID_WIDTH-1:0] id_index;         // Unique identifier for the DRIS index, pretty much register renaming
    } dris_id_t;

    typedef struct packed {
        logic locked;                                  // Indicates if the locker is currently locked
        logic locker_color;                                  // helps determine age (see comment at the end of this file)
        logic locker_valid;
        logic [DRIS_ID_WIDTH-1:0] locker_id;         // Unique identifier for the DRIS index, pretty much register renaming
    } dris_locker_t;

    typedef struct packed {
        logic [XLEN-1:0] result_data;                  // result of the instruction
        logic            result_valid;            // indicates if the result is valid
    } dris_result_t;

    typedef struct packed {
        `ifdef DEBUG
            logic [XLEN-1:0] debug_instr_R;
        `endif

        logic [XLEN-1:0] pc_R;
        logic [REG_NUM_WIDTH-1:0] rd_R, rs1_R, rs2_R;
        ctrl_signals_t             ctrl_signals_R;
        logic [XLEN-1:0]           imm_R;
        logic valid_R;
    } dris_intake_pkt_t;

    //patent uses 106 bits (pg 9, diagram
    typedef struct packed {

        `ifdef DEBUG
            logic [XLEN-1:0] debug_instr;
        `endif
        
        //not in the patent, but the metaflow paper 
        //says that the PC is in there
        logic [XLEN-1:0] pc;
        logic [REG_NUM_WIDTH-1:0] rd, rs1, rs2;        // destination and source registers
        dris_entry_state_t entry_state;           // state of the entry
        dris_id_t id;                       // DRIS ID for register renaming
        dris_locker_t locker_1, locker_2;   // DRIS lockers for source registers (locker1 = rs1, locker2 = rs2)
        dris_result_t result;
        ctrl_signals_t ctrl_signals;              // control signals for the instruction
        logic [XLEN-1:0] imm;                    // immediate value for the instruction

    } dris_entry_t;
    localparam int DRIS_ENTRY_WIDTH = $bits(dris_entry_t);

    typedef struct packed {
        `ifdef DEBUG
            logic [XLEN-1:0] debug_instr_I;
        `endif
        
        logic [XLEN-1:0] pc_I;
        logic [XLEN-1:0] imm_I;             // raw immediate; CT target computation in the exec way (op_2 holds rs2 for branches)
        logic [XLEN-1:0] rs1_data_I;       //jalr needs both this and the pc
        ctrl_signals_t ctrl_signals_I;              // control signals for the instruction
        logic [XLEN-1:0] op_1_I, op_2_I;    // source operand values
        dris_id_t id_I;                       // DRIS ID for register renaming
        logic ready_I;                        // indicates if the instruction is ready to be dispatched (operands are ready)
    } issue_pkt_t;

    //core -> cache controller request side interface
    typedef struct packed {
        `ifdef DEBUG
            logic [XLEN-1:0] debug_instr_I;
            logic [XLEN-1:0] debug_pc_I;
        `endif

        logic                          core_req_we;
        logic                          core_req_re;
        logic [MEM_ADDRESS_SIZE-1:0]   core_req_addr;
        logic [MEM_WORD_SIZE-1:0]      core_req_store_data;
        logic                          core_req_cancel;
        logic                          core_req_stall_mem;
        logic [3:0]                    core_req_store_mask;
        dris_id_t                      core_req_id;
        ctrl_signals_t                  core_req_ctrl_signals;
        logic [1:0]                    byte_offset;

    } memory_issue_pkt_t;

    //things the processor needs for a load request
    // id, ctrl_signals, byte_offset

    typedef struct packed {

        `ifdef DEBUG
            logic [XLEN-1:0] debug_instr_dris_W;
        `endif
        
        logic [XLEN-1:0] pc_W;
        dris_id_t        id_W;
        logic [XLEN-1:0] result_data_W;     // register-file-bound value (pc+4 link for JAL/JALR); the DRIS result
        logic [XLEN-1:0] next_pc_W;         // computed next PC; PC-bound, consumed only by the branch shelf snoop
        logic            valid_W;
        ctrl_signals_t   ctrl_signals_W;              // control signals for the instruction, needed for retirement
    } dris_writeback_pkt_t;

    typedef struct packed {

        `ifdef DEBUG
            logic [XLEN-1:0] debug_pc_regfile_C;
            logic [XLEN-1:0] debug_instr_regfile_C;
        `endif
        
        logic                        valid_C;
        logic [REG_NUM_WIDTH-1:0]    rd_C;            // destination register for the instruction being retired
        logic [XLEN-1:0]             rd_data_C;       // data to be written back to the register file at commit time, needed for precise exceptions and CSR writes
    } reg_file_commit_pkt_t;

    typedef struct packed {

        `ifdef DEBUG
            logic [XLEN-1:0] debug_pc_memory_C;
            logic [XLEN-1:0] debug_instr_memory_C;
        `endif
        
        logic                        mem_write_C;    // true for stores, false for loads
        logic                        valid_C;        // indicates if the commit packet is valid
        logic [XLEN-1:0]             mem_addr_C;
        logic [REG_NUM_WIDTH-1:0]    rs2_C;           // source register for store data, ignored for loads
        dris_id_t                    id_C;            // so the DRIS knows which entry to free
    } memory_commit_pkt_t;

     // returns true if a is older than b
    function automatic logic is_older(dris_id_t a, dris_id_t b);
        // same color: same lap, lower index was fetched first
        // different color: a wrapped, so despite higher index a is older
        if (a.id_color == b.id_color)
            return a.id_index < b.id_index;
        else
            return a.id_index > b.id_index;
    endfunction

    function automatic dris_id_t dependency_in_dris(
        input logic [REG_NUM_WIDTH-1:0]           src_reg,
        input dris_id_t                           new_id,
        input dris_entry_t                        dris_entries [DRIS_NUM_ENTRIES-1:0]
        );
        dris_id_t youngest;
        logic     found;
        found = '0;
        youngest = '0;

        if (src_reg == '0) begin
            return {1'b0, 1'b0, {DRIS_ID_WIDTH{1'b1}}}; // no dependency on x0
        end

        for (int i = 0; i < DRIS_NUM_ENTRIES; i++) begin
            if (dris_entries[i].entry_state.valid   &&
                dris_entries[i].rd == src_reg        &&
                is_older(dris_entries[i].id, new_id)) begin

                if (!found || is_older(youngest, dris_entries[i].id)) begin
                    // this entry is older than new_id
                    // and younger than our current best candidate
                    youngest = dris_entries[i].id;
                    found = '1;
                end
            end
        end

        // locker validity determined by valid bit of entry returned
        return found ? youngest : {1'b0, 1'b0, {DRIS_ID_WIDTH{1'b1}}};
    endfunction

    // A potential forwarding source from earlier in the same fetch group.
    typedef struct packed {
        logic                     valid;
        logic [REG_NUM_WIDTH-1:0] rd;
        dris_id_t                 id;
    } fwd_source_t;

    // Both lockers for one instruction, returned as a unit.
    typedef struct packed {
        dris_locker_t locker_1;
        dris_locker_t locker_2;
    } locker_pair_t;

    function automatic dris_id_t slot_id(input logic [DRIS_ID_WIDTH:0] base,
                                         input int w);
        automatic logic [DRIS_ID_WIDTH:0] full = base + (DRIS_ID_WIDTH+1)'(w);
        return '{id_valid: 1'b1,
                 id_color: full[DRIS_ID_WIDTH],
                 id_index: full[DRIS_ID_WIDTH-1:0]};
    endfunction

endpackage: DRIS_defs

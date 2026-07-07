//this file is only here to appease the 
//compilier
//it does nothing
//actual internal defines is in 0internal_defines_pkg.sv

// /**
//  * internal_defines.vh
//  *
//  * RISC-V 32-bit Processor
//  *
//  * ECE 18-447
//  * Carnegie Mellon University
//  *
//  * This contains the definitions of constants and types that are used by the
//  * core of the RISC-V processor, such as control signals and ALU operations.
// **/

// /*----------------------------------------------------------------------------*
//  *  You may edit this file and add or change any files in the src directory.  *
//  *----------------------------------------------------------------------------*/

// `ifndef INTERNAL_DEFINES_VH_
// `define INTERNAL_DEFINES_VH_

// // 2nd operand immediate mode
// typedef enum logic [2:0] {
//     IMM_I,
//     IMM_S,
//     IMM_SB,
//     IMM_U,
//     IMM_UJ,
//     IMM_DC = 'bx            // Don't care value
// } imm_mode_t;

// // Constants that specify which operation the ALU should perform
// typedef enum logic [5:0] {
//     ALU_ADD,                // Addition operation
//     ALU_ADD4,  
//     ALU_SUB,                // Subtraction/Compare operation
//     ALU_SLL,                //SLL operation
//     ALU_SLLI,               //SLLI operation
//     ALU_SRL,                //SRL op
//     ALU_SRA,                //SRA op
//     ALU_BEQ,                //BEQ op, shows what next PC should be
//     ALU_BNE,                //BNE op
//     ALU_BLT,                //BLT op
//     ALU_BGE,                //BGE op
//     ALU_BLTU,               //BLTU op
//     ALU_BGEU,               //BGEU op
//     ALU_XOR,
//     ALU_OR,
//     ALU_AND,
//     ALU_SLT,    
//     ALU_SLTU,
//     ALU_PASS,               //for LUI, lets imm through without changing it
//     ALU_DC = 'bx            // Don't care value
// } alu_op_t;

// // Load/store partial word mode
// typedef enum logic [2:0] {
//     LDST_W,
//     LDST_H,
//     LDST_HU,
//     LDST_B,
//     LDST_BU,
//     LDST_DC = 'bx            // Don't care value
// } ldst_mode_t;

// // Next PC source
// typedef enum logic [1:0] {
//     PC_plus4,               // non-control flow
//     PC_cond,                // Branch
//     PC_uncond,              // JAL
//     PC_indirect,            // indirect jump (JALR)
//     PC_DC = 'bx		    
// } pc_source_t;

// /* The definition of the control signal structure, which contains all
//  * microarchitectural control signals for controlling the MIPS datapath. */
// typedef struct packed {
//     logic useImm;           // 2nd ALU input from immediate else GPR port
//     logic usePC;            // 1st ALU input is the PC
//     logic rfWrite;          // write GPR
//     logic mem2RF;           // memory load result write to GPR
//     logic pc2RF;            // PC+4 write to GPR (link)
//     logic pc_plus_imm2RF;   // PC+imm write to GPR(AUIPC)
//     logic memRead;          // load instruction
//     logic memWrite;         // store instruction
//     imm_mode_t imm_mode;    // immediate mode applied
//     alu_op_t alu_op;        // The ALU operation to perform
//     ldst_mode_t ldst_mode;  // load/store partial word mode;
//     pc_source_t pc_source;  // next PC source

//     logic uses_rs1;         //for stalling logic
//     logic uses_rs2;         //for stalling logic

//     logic [2:0] btype;      // branch FUNCT3
//     logic syscall;          // Indicates if the current instruction is a syscall
//     logic illegal_instr;    // Indicates if the current instruction is illegal
// } ctrl_signals_t;

// //ctrl signals when halted
// //27 bits?
// localparam ctrl_signals_t CTRL_SIGNALS_NOOP = '{
//     useImm:          1'b0,
//     usePC:           1'b0,
//     rfWrite:         1'b0,
//     mem2RF:          1'b0,
//     pc2RF:           1'b0,
//     pc_plus_imm2RF:  1'b0,
//     memRead:         1'b0,
//     memWrite:        1'b0,
//     imm_mode:        IMM_DC, // Use your specific enum defaults
//     alu_op:          ALU_PASS,
//     ldst_mode:       LDST_DC,
//     pc_source:       PC_plus4,
//     uses_rs1:        1'b0,
//     uses_rs2:        1'b0,
//     btype:           3'b0,
//     syscall:         1'b0,
//     illegal_instr:   1'b0
// };

// localparam logic [3:0] pc_mispredict_flush = 4'd11;
// localparam logic [3:0] pc_stall_bubble = 4'd13;

// typedef enum logic [2:0] {
//         FWD_RF  = 3'd0,   // take regfile value
//         FWD_E   = 3'd1,   // forward from Execute stage result
//         FWD_M1  = 3'd2,   // forward from Mem1 stage result
//         FWD_M2  = 3'd3,   // forward from Mem2 stage result
//         FWD_W   = 3'd4    // forward from Writeback stage result (rf_wdata_W)
// } fwd_sel_t;


// `endif /* INTERNAL_DEFINES_VH_ */
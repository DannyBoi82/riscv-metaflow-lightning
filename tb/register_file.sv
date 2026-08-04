/**
 * register_file.sv
 *
 * RISC-V 32-bit Processor
 *
 * ECE 18-447
 * Carnegie Mellon University
 *
 * This is the architectural register file used by the processor cores.
 *
 * The register file is a standard register file, with synchronous writes and
 * combinational reads. It has two read ports and a single write port per way
 * for instructions to access it.
 *
 * Verification role: the register file assembles the per-slot commit packets
 * (RISCV_Commit::commit_pkt_t) consumed by the testbench's commit_verifier.
 * The core tells it which slots retire a real instruction this cycle
 * (commit_valid, with the instruction's PC and encoding); the write-port
 * inputs of the same slot supply the register-write half of the packet.
 * That is this module's only verification duty — register dumps and trace
 * checking live in tb/commit_verifier.sv, driven purely by the packets, so
 * a core that does not use this module (e.g. a physical-register-file
 * design with no architectural regfile) can emit packets itself; see
 * rtl/include/riscv_commit.vh and README "verify-trace".
 *
 * Authors:
 *  - 2016 - 2017: Brandon Perez
 *  - 2025 - 2026: Kaitlyn Vitkin
 **/

// RISC-V Includes
`include "riscv_isa.vh"                 // Default number of registers and width
`include "riscv_abi.vh"                 // Definition of the SP and GP registers
`include "riscv_uarch.vh"               // Default number of superscalar ways
`include "memory_segments.vh"           // Memory segment addresses
`include "riscv_commit.vh"              // Commit packet definition

// Force the compiler to throw an error if any variables are undeclared
`default_nettype none

/*------------------------------------------------------------------------------
 * Register File Module
 *----------------------------------------------------------------------------*/

/**
 * The register file used by the RISC-V processor.
 *
 * This is a synchronous write, combinational (asynchronous) read register file.
 * The register file has two read ports and a single write port for each way, or
 * pipeline. The value of register 0 is guaranteed to always be 0.  The register
 * file does not have internal forwarding. Thus, if a read and write occur to
 * the same location on a clock cycle, the read will get the value of the
 * register from the previous clock cycle.
 *
 * The register file is parameterized by the number of superscalar ways
 * (or pipelines) in the design, the number of registers, the width of the
 * registers. If there is a write conflict between the different ways, then the
 * highest numbered way will be the one to update the register, which
 * should correspond to the youngest instruction in the processor.
 *
 * Parameters:
 *  - WAYS      The number of superscalar ways, or pipelines, that access the
 *              register file.
 *  - NUM_REGS  The number of registers in the register file.
 *  - WIDTH     The number of bits that each register holds.
 *  - FORWARD   Combinational write to read forwading (1 to enable)
 *
 * Inputs:
 *  - clk       The clock to use for the registers in the register file.
 *  - rst_l     The asynchronous, active-low reset for the registers.
 *  - rd_we     Indicates that the rd_data should be written to register(s) rd.
 *  - rs1       The first source register(s) to read from the register file.
 *  - rs2       The second source register(s) to read from the register file.
 *  - rd        The destination register(s) to write to in the register file.
 *  - rd_data   The data to write into register rd if rd_we is asserted.
 *  - commit_valid  Per way: a real (non-bubble, non-wrong-path) instruction
 *                  retires in this slot this cycle. Writes land on the same
 *                  clock edge on which the packet is sampled.
 *  - commit_pc     Per way: PC of the retiring instruction.
 *  - commit_insn   Per way: encoding of the retiring instruction.
 *  - commit_mem    Per way: the data-memory access the retiring instruction
 *                  performed, '0 if it touched no memory (verify-mem seam;
 *                  cores drive it only in `DEBUG builds).
 *
 * Outputs:
 *  - rs1_data  The data read from the rs1 register(s).
 *  - rs2_data  The data read from the rs2 register(s).
 *  - commit_pkts   Per way: assembled commit packet (see riscv_commit.vh).
 **/
module register_file
    // Import the default values for the parameters
    import RISCV_UArch::SUPERSCALAR_WAYS;
    import RISCV_ISA::XLEN;
    import RISCV_Commit::commit_pkt_t, RISCV_Commit::commit_mem_t;

    #(parameter WAYS=SUPERSCALAR_WAYS, NUM_REGS=RISCV_ISA::NUM_REGS, WIDTH=XLEN, FORWARD=0)
    (input  logic                               clk, rst_l,
     input  logic [WAYS-1:0]                    rd_we,
     input  logic [WAYS-1:0][$clog2(WIDTH)-1:0] rs1, rs2, rd,
     input  logic [WAYS-1:0][WIDTH-1:0]         rd_data,
     input  logic [WAYS-1:0]                    commit_valid,
     input  logic [WAYS-1:0][WIDTH-1:0]         commit_pc, commit_insn,
     input  commit_mem_t [WAYS-1:0]             commit_mem,
     output logic [WAYS-1:0][WIDTH-1:0]         rs1_data, rs2_data,
     output commit_pkt_t [WAYS-1:0]             commit_pkts);

    // Import the stack and global pointer register, and the segments addresses
    import RISCV_ABI::SP, RISCV_ABI::GP;
    import MemorySegments::STACK_END, MemorySegments::USER_DATA_START;

    // The registers in the register file
    logic [NUM_REGS-1:0][WIDTH-1:0] registers;

    // Handle initialization and writing to the registers
    always_ff @(posedge clk, negedge rst_l) begin
       if (!rst_l) begin
           registers <= 'b0;

           // Set SP to the top of the stack, GP to the data section
           registers[SP] <= STACK_END;
           registers[GP] <= USER_DATA_START;
       end else begin
           register_write_loop: for (int i = 0; i < $size(rd, 1); i++) begin
               if (rd_we[i] && (rd[i] != 'd0)) begin
                   registers[rd[i]] <= rd_data[i];
               end
           end
       end
    end

    // Handle reading from the registers
    always_comb begin
        register_read_loop: for (int i = 0; i < $size(rs1, 1); i++) begin
            rs1_data[i] = registers[rs1[i]];
            rs2_data[i] = registers[rs2[i]];
            if (FORWARD) begin
                register_rs1_forward_loop: for (int j = 0; j < $size(rd, 1); j++) begin
                    if (rd_we[j] && (rd[j] != 'd0)) begin
                        if (rd[j]==rs1[i]) begin
                            rs1_data[i]=rd_data[j];
                        end
                        if (rd[j]==rs2[i]) begin
                            rs2_data[i]=rd_data[j];
                        end
                    end
                end
            end
        end
    end

    /* Commit packet assembly. Pure renaming of the write-port and commit
     * inputs — no state, no simulation-time cost. Per the RVFI convention,
     * rd_addr = 0 encodes "no architectural write", which also covers real
     * writes to x0 (architectural no-ops). */
    always_comb begin
        commit_pkt_loop: for (int i = 0; i < WAYS; i++) begin
            commit_pkts[i]          = '0;
            commit_pkts[i].valid    = commit_valid[i];
            commit_pkts[i].pc_rdata = commit_pc[i];
            commit_pkts[i].insn     = commit_insn[i];
            commit_pkts[i].mem      = commit_valid[i] ? commit_mem[i] : '0;
            if (commit_valid[i] && rd_we[i] && (rd[i] != 'd0)) begin
                commit_pkts[i].rd_addr  = rd[i];
                commit_pkts[i].rd_wdata = rd_data[i];
            end
        end
    end

endmodule: register_file

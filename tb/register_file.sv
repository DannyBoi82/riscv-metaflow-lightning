/**
 * register_file.sv
 *
 * RISC-V 32-bit Processor
 *
 * ECE 18-447
 * Carnegie Mellon University
 *
 * This is the register file used by the main processor.
 *
 * The register file is a standard register file, with synchronous writes and
 * combinational reads. It has two read ports and a single write port for
 * instructions to access it.
 *
 * The register file also handles producing register dumps for simulation.
 * Whenever simulation finishes (indicated by the halted signal), the register
 * file dumps the values of all registers out to stdout and to file. This file
 * is then used by the build system to run verification of the results against
 * the reference register dump.
 *
 * Authors:
 *  - 2016 - 2017: Brandon Perez
 *  - 2025 - 2026: Kaitlyn Vitkin
 **/

/*----------------------------------------------------------------------------*
 *                          DO NOT MODIFY THIS FILE!                          *
 *          You should only add or change files in the src directory!         *
 *----------------------------------------------------------------------------*/

// RISC-V Includes
`include "riscv_isa.vh"                 // Default number of registers and width
`include "riscv_abi.vh"                 // Definition of the SP and GP registers
`include "riscv_uarch.vh"               // Default number of superscalar ways
`include "memory_segments.vh"           // Memory segment addresses

// Local Includes
`include "riscv_register_names.vh"      // Names for the RISC-V registers
`ifdef DEBUG_RFWRTRACE
`include "reg_defs.vh"                  // Used for cycle level register verification
`endif
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
 *  - halted    Indicates that the processor has stopped due to a syscall or an
 *              exception. This is used by the register file to trigger a dump
 *              of the registers to stdout and to file.
 *  - rd_we     Indicates that the rd_data should be written to register(s) rd.
 *  - rs1       The first source register(s) to read from the register file.
 *  - rs2       The second source register(s) to read from the register file.
 *  - rd        The destination register(s) to write to in the register file.
 *  - rd_data   The data to write into register rd if rd_we is asserted.
 *
 * Outputs:
 *  - rs1_data  The data read from the rs1 register(s).
 *  - rs2_data  The data read from the rs2 register(s).
 **/
module register_file
    // Import the default values for the parameters
    import RISCV_UArch::SUPERSCALAR_WAYS;
    import RISCV_ISA::XLEN;

    #(parameter WAYS=SUPERSCALAR_WAYS, NUM_REGS=RISCV_ISA::NUM_REGS, WIDTH=XLEN, FORWARD=0)
    (input  logic                               clk, rst_l, halted,
     input  logic [WAYS-1:0]                    rd_we,
     input  logic [WAYS-1:0][$clog2(WIDTH)-1:0] rs1, rs2, rd,
     input  logic [WAYS-1:0][WIDTH-1:0]         rd_data,
     output logic [WAYS-1:0][WIDTH-1:0]         rs1_data, rs2_data);

    // Import the stack and global pointer register, and the segments addresses
    import RISCV_ABI::SP, RISCV_ABI::GP;
    import MemorySegments::STACK_END, MemorySegments::USER_DATA_START;

`ifdef DEBUG_RFWRTRACE
    // Import what is needed for the verbose register checking
    import reg_changes_pkg::*;
    localparam int unsigned ways_bits = $clog2(WAYS);
`endif

    // The file handle number for stdout
    localparam STDOUT = 32'h8000_0002;

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

     // Verbose cycle by cycle register checking
`ifdef DEBUG_RFWRTRACE
        logic [31:0] curr_cnt;
        logic [31:0] num_wr;
        logic [WAYS-1:0] rd_we_buf;
        logic [WAYS-1:0][WIDTH-1:0]         rd_data_buf;
        logic [WAYS-1:0][$clog2(WIDTH)-1:0]  rd_buf;
        // Number of reg writes already checked this cycle
        logic [31:0] curr_cycle_wr_cnt;
        // Current index in "changes" that should be checked
        logic [31:0] changes_idx;

        assign num_wr = $countones(rd_we);

        always_ff @(posedge clk, negedge rst_l) begin
            if(~rst_l) begin
                curr_cnt <= '0;
                rd_we_buf <= '0;
                rd_data_buf <= '0;
                rd_buf <= '0;
            end else begin
                //increment the index of the current register write
                curr_cnt <= curr_cnt + curr_cycle_wr_cnt;
                rd_we_buf <= rd_we;
                rd_data_buf <= rd_data;
                rd_buf <= rd;
            end
        end

        always_comb begin
            curr_cycle_wr_cnt = '0;
            changes_idx = curr_cnt;
            register_check_loop: for(int i = 0; i < WAYS; i++) begin
                // A RF write has been detected
                if(rd_we_buf[i] && (rd_buf[i]!=0) ) begin
                    assert((rd_buf[i] === changes[changes_idx].name) && (rd_data_buf[i] === changes[changes_idx].val ))
                        else $fatal ("At cycle %0d and register write %d, data of %h was written, when expected data was %h. Data went to register %d but was supposed to go to register %d", $time, changes_idx, rd_data_buf[i], changes[changes_idx].val, rd_buf[i], changes[changes_idx].name);

                    curr_cycle_wr_cnt = curr_cycle_wr_cnt + 1;
                    changes_idx = changes_idx + 1;
                end

            end
        end
`endif

`ifdef SIMULATION_18447

    // Import the names of all the registers
    import RISCV_RegisterNames::*;

    // When simulation finishes, dump the register state to stdout and file
    int fd;
    always_ff @(posedge clk) begin
        if (rst_l && halted) begin
            $display("\n18-447 Register File Dump at Cycle %0d, Mem Accesses: %0d", $time, top.mem_access);
            $display("---------------------------------------------\n");
            print_cpu_state(STDOUT, registers);

            fd = $fopen("simulation.reg");
            print_cpu_state(fd, registers);
            $display();
            $fclose(fd);

            fd = $fopen("simulation.reg2");
            $fdisplay(fd, "\n18-447 Register File Dump at Cycle %0d, Mem Accesses: %0d", $time, top.mem_access);
            $fdisplay(fd, "---------------------------------------------\n");
            print_cpu_state(fd, registers);
            $fclose(fd);
        end
    end

    // Prints out the information for a single register to the given file.
    function void print_register(int fd, int i, register_name_t reg_name,
            const ref logic [NUM_REGS-1:0][WIDTH-1:0] registers);

        // Format the ABI alias name for the register
        string abi_name, reg_hex_value, reg_uint_value, reg_int_value;
        abi_name = {"(", reg_name.abi_name, ")"};

        /* Format the hex/signed/unsigned views of the register. The hex value
         * is formatted separately because Verilator (<= 5.048 at least) leaks
         * the '-' (left-justify) flag from earlier %-Ns specifiers into a
         * later %x in the same format string, dropping its zero-padding. */
        $sformat(reg_hex_value, "0x%x", registers[i]);
        $sformat(reg_uint_value, "(%0d)", registers[i]);
        $sformat(reg_int_value, "(%0d)", signed'(registers[i]));

        // Print out the register's names and values
        $fdisplay(fd, "%-8s %-8s = %-10s %-12s %-13s", reg_name.isa_name,
                abi_name, reg_hex_value, reg_uint_value, reg_int_value);
    endfunction: print_register

    // Prints the CPU state to the given file.
    function void print_cpu_state(int fd,
            const ref logic [NUM_REGS-1:0][WIDTH-1:0] registers);

        /* Print out the instructions fetched and the current pc value. Don't
         * print this to the register dump file. */
        if (fd == STDOUT) begin
            $fdisplay(fd, "Current CPU State and Register Values:");
            $fdisplay(fd, "--------------------------------------");
            $fdisplay(fd, "%-20s = %0d", "Cycle Count",
                    $root.top.cycle_count);
            $fdisplay(fd, "%-20s = 0x%x\n", "Program Counter (PC)",
                    $root.top.pc);
        end

        // Display the header for the table of register values
        $fdisplay(fd, "%-8s %-8s   %-10s %-12s %-13s", "ISA Name", "ABI Name",
                "Hex Value", "Uint Value", "Int Value");
        /* The explicit %s keeps Verilator from printing the replication as a
         * decimal number; VCS treats the bare replication as a format string. */
        $fdisplay(fd, "%s", {(8+1+8+3+10+1+12+1+13){"-"}});

        // Display the register and its values for each register
        foreach (REGISTER_NAMES[i]) begin
            print_register(fd, i, REGISTER_NAMES[i], registers);
        end
    endfunction: print_cpu_state

`endif /* SIMULATION_18447 */

endmodule: register_file

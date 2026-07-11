/**
 * testbench.sv
 *
 * RISC-V 32-bit Processor
 *
 * ECE 18-447
 * Carnegie Mellon University
 *
 * This is the testbench (top module) used for processor simulation.
 *
 * This top module is intended only for simulation, and is not synthesizable. It
 * is responsible for running and managing the riscv_core module. See top.sv for
 * the synthesizable top module.
 *
 * The top module handles connecting the memory simulation model to the
 * processor core, and terminating simulation when requested by the core. It
 * also generates the clock, and keeps track of basic information, such as
 * the cycle count and PC value.
 *
 * Authors:
 *  - 2016 - 2017: Brandon Perez
 *  - 2026: Elisa Mayer and Feya Epel
 **/

/*----------------------------------------------------------------------------*
 *                          DO NOT MODIFY THIS FILE!                          *
 *          You should only add or change files in the src directory!         *
 *----------------------------------------------------------------------------*/

// This module is only included when we are running simulation
`ifdef SIMULATION_18447

// Force the compiler to throw an error if any variables are undeclared
`default_nettype none

// RISC-V Includes
`include "riscv_isa.vh"             // Definition of XLEN
`include "riscv_uarch.vh"           // Definition of main memory parameters
`include "memory_segments.vh"       // Definition of memory segments array
`include "riscv_commit.vh"          // Commit packet definition (verify-trace)

/*----------------------------------------------------------------------------
 * Simulation Top Module
 *----------------------------------------------------------------------------*/

/**
 * The top module for the RISC-V core used for simulation.
 *
 * For simulation, a non-synthesizable, but behaviorally accurate model is
 * used for memory. Additionally, the top module for simulation handles
 * clock generation, resetting the processor, keeping track of cycles, and
 * terminating the simulation when prompted.
 **/
module top;

    // Import the parameters needed to define main memory
    import RISCV_ISA::XLEN, RISCV_ISA::XLEN_BYTES;
    import RISCV_UArch::MEMORY_NUM_PORTS, RISCV_UArch::MEMORY_ADDR_WIDTH;
    import RISCV_UArch::SUPERSCALAR_WAYS;
    import RISCV_UArch::MEMORY_READ_WIDTH;
    import RISCV_UArch::IMEMORY_READ_DELAY;
    import RISCV_UArch::DMEMORY_READ_DELAY;
    import MemorySegments::SEGMENTS, MemorySegments::SEGMENT_WORDS;

    // Import the clock to use for the processor in simulation
    import RISCV_UArch::CLOCK_HALF_PERIOD;
    import RISCV_UArch::MAX_SIM_CYCLES;

    // Internal variables
    int                                     cycle_count;

    // Processor and memory interface signals

    logic clk, rst_l, mem_excpt_M, mem_excpt;
    logic mem_load_en, mem_stall, halted;
    logic [XLEN_BYTES-1:0] mem_store_mask;
    logic [MEMORY_ADDR_WIDTH-1:0] mem_req_addr, mem_resp_addr;
    logic [XLEN-1:0] mem_store_data, pc;
    logic [MEMORY_READ_WIDTH-1:0][XLEN-1:0] mem_data_load_M, mem_load_data;
    logic mem_resp_valid;

    // Commit packets emitted by the core at retirement (verify-trace)
    RISCV_Commit::commit_pkt_t [RISCV_Commit::COMMIT_WAYS_MAX-1:0] commit_pkts;

    /* Handle resetting the processor when simulation begins. Start rst_l
     * high and drop it after one time unit so `negedge rst_l` fires in
     * 2-state simulation as well: in 4-state simulators the X->0 transition
     * at time zero counts as a negedge, but in Verilator rst_l would start
     * at 0 and the async resets in the design would never trigger. */
    initial begin
        rst_l = 1;
        #1 rst_l = 0;
        rst_l <= #(CLOCK_HALF_PERIOD - 1) 1;
    end

    // The global clock for the design
    clock #(.HALF_PERIOD(CLOCK_HALF_PERIOD)) Clock(.clk);

    assign mem_stall = 1'b0;

    // The RISC-V core
    riscv_core_interface RISCV_Core_interface (
        .clk                 (clk),
        .rst_l               (rst_l),
        .mem_data_load       (mem_load_data),
        .mem_data_addr       (mem_req_addr),
        .mem_data_load_valid (mem_resp_valid),
        .mem_excpt           (mem_excpt),
        .mem_data_load_en    (mem_load_en),
        .halted              (halted),
        .mem_data_store_mask (mem_store_mask),
        .mem_data_store      (mem_store_data),
        .mem_data_load_addr  (mem_resp_addr),
        .commit_pkts         (commit_pkts)
    );

    /* Consumes the commit packet stream: shadow architectural regfile,
     * optional per-commit state trace (+commit_trace), and the end-of-run
     * register dump. See tb/commit_verifier.sv. */
    commit_verifier CommitVerifier (
        .clk,
        .rst_l,
        .halted,
        .commit_pkts
    );

    // Delay buffer to simulate multi-cycle pipelined memory
    delay_buffer #(
        .DATA_WIDTH(MEMORY_ADDR_WIDTH + 2 + MEMORY_READ_WIDTH * XLEN),
        .DELAY     (DMEMORY_READ_DELAY),
        .RESET_VAL (({{MEMORY_ADDR_WIDTH{1'h0}}, 1'b0, 1'b0, {MEMORY_READ_WIDTH{32'h0}}}))
    ) DataDelayBuffer (
        .clk,
        .rst_l,
        .stall   (mem_stall),
        .data_in ({mem_req_addr,  mem_load_en,    mem_excpt_M, mem_data_load_M}),
        .data_out({mem_resp_addr, mem_resp_valid, mem_excpt,   mem_load_data})
    );

    // The main memory for the processor
    main_memory #(
        .NUM_PORTS    (MEMORY_NUM_PORTS),
        .LOAD_WORDS   (MEMORY_READ_WIDTH),
        .WORD_BYTES   (XLEN_BYTES),
        .ADDR_WIDTH   (MEMORY_ADDR_WIDTH),
        .SEGMENT_WORDS(SEGMENT_WORDS)
    ) Memory (
        .clk,
        .rst_l,
        .load_ens   (mem_load_en),
        .store_masks(mem_store_mask),
        .addrs      (mem_req_addr),
        .store_data (mem_store_data),
        .mem_excpts (mem_excpt_M),
        .load_data  (mem_data_load_M)
    );

    // Keep a count of the cycles that have passed, and the current PC value
    assign pc = 'bx; // {instr_addr, 2'b00};
    always_ff @(posedge clk) begin
        if (!rst_l) begin
            cycle_count = 0;
        end else begin
            cycle_count += 1;
        end
    end
    // check number of memory cycles
    logic [63:0] mem_access;
    always_ff @(posedge clk) begin
        if (!rst_l) begin
            mem_access <= '0;
        end
        else if(mem_load_en | (mem_store_mask != 0)) begin
            mem_access <= mem_access + 64'b1;
        end
    end

    // Handle terminating simulation whenever halted is asserted
    always @(posedge clk) begin
        #0;                 // Allow all other tasks to finish
        if (rst_l && halted) begin
            $finish;
        end
    end

    /* Watchdog: a test that never reaches its halting ecall (e.g. the core
     * livelocks) would otherwise simulate — and print — forever. No register
     * dump is produced, so verify fails as it should. */
    always @(posedge clk) begin
        if (rst_l && cycle_count >= MAX_SIM_CYCLES) begin
            $display("TIMEOUT: %0d cycles elapsed without the core halting.",
                    cycle_count);
            $finish;
        end
    end

`ifdef VERILATOR
    // Optional FST waveform dump, enabled by `make waves` (+waves plusarg).
    // VCS uses the DVE flow (`make sim-gui`) instead.
    initial begin
        if ($test$plusargs("waves")) begin
            $dumpfile("waves.fst");
            $dumpvars(0, top);
        end
    end
`endif

endmodule: top

/*----------------------------------------------------------------------------
 * Clock Module
 *----------------------------------------------------------------------------*/

/**
 * The generator for the global clock used for the processor.
 *
 * This outputs the global clock for the design, and is parameterized by
 * the clock's half period, so the actual period is double that.
 *
 * Parameters:
 *  - HALF_PERIOD   Half of the generated clock's period.
 *
 * Outputs:
 *  - clk           The global clock for the design, with a period of
 *                  2*HALF_PERIOD.
 **/
module clock
    #(parameter HALF_PERIOD=0)
    (output logic clk);

    initial begin
        clk = 1;

        forever #HALF_PERIOD clk = ~clk;
    end

endmodule: clock

/**
 * Delay data_in to data_out by parameterized number of clock edges.
 * Data_out is 0 during reset.  DELAY=0 means combinational.
 *
 * Parameters:
 *  - DATA_WIDTH    width of data value
 *  - DELAY         number of clock edges; 0 means combinational
 *
 * Input:
 *  - data_in       input data
 *  - clk           clock
 *  - rst_l         active low reset
 *
 * Outputs:
 *  - data_out      output data
 **/
module delay_buffer #(parameter DATA_WIDTH=0, DELAY=0, RESET_VAL=0)
    (clk, rst_l, stall, data_in, data_out);

    output [DATA_WIDTH-1:0] data_out;
    reg [DATA_WIDTH-1:0] data_out;

    input  [DATA_WIDTH-1:0] data_in;
    input  clk, rst_l, stall;
    reg    [DATA_WIDTH-1:0]        data_q[DELAY:0];  // only upto data_q[DELAY-1] is used

    integer       i;

    always@(posedge clk) begin
        if (!rst_l) begin
            for (i = 0; i < DELAY; i=i+1) begin
                data_q[i]<=RESET_VAL;
            end
        end else begin
            if (!stall) begin
                data_q[0]<=data_in;

                for (i = 1; i < DELAY; i=i+1) begin
                    data_q[i]<=data_q[i-1];
                end
            end
        end
    end // always@ (posedge clk)

   always@(*) begin
       if (!rst_l) begin
           data_out=RESET_VAL;
       end else if (DELAY==0) begin
           data_out=data_in;
       end else begin
           data_out=data_q[(DELAY!=0)?DELAY-1:0];
       end
   end

endmodule


`endif  /* SIMULATION_18447 */

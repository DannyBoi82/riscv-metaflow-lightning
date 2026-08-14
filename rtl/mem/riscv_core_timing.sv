/**
 * riscv_core_timing.sv
 *
 * RISC-V 32-bit Processor
 *
 * The top module used when the design is synthesized (`make synth`).
 *
 * This module is intended only for synthesis; it is not behaviorally
 * accurate and must never be simulated. It wraps `riscv_core_interface`
 * (whichever core config.mk's CORE selects — both files define that module
 * name) and hangs a synthesizable-but-fake main memory off its memory port,
 * so that the reported critical path includes a realistic combinational
 * delay for a memory read instead of a free constant.
 *
 * The whole file is compiled out under `SIMULATION_18447`, exactly like
 * sram_synthesis.sv, so it costs nothing in the simulation flow and needs no
 * Makefile changes on either side.
 *
 * The design's memory port is exposed at the top level (including the
 * signals the fake memory drives back into the core) so DC has real
 * endpoints to constrain and cannot optimize the memory model away.
 *
 * Authors:
 *  - 2017: James Hoe
 *  - 2017: Brandon Perez
 *  - 2026: ported to the Lightning memory interface
 **/

// These modules are only compiled when we are running synthesis
`ifndef SIMULATION_18447

// Force the compiler to throw an error if any variables are undeclared
`default_nettype none

// RISC-V Includes
`include "riscv_isa.vh"             // Definition of XLEN parameters
`include "riscv_uarch.vh"           // Definition of delay and other parameters

/*----------------------------------------------------------------------------
 * Synthesis Top Module
 *----------------------------------------------------------------------------*/

/**
 * The top module for the RISC-V core used for synthesis.
 *
 * Inputs:
 *  - clk                   The global clock for the processor.
 *  - rst_l                 The asynchronous, active low reset.
 *  - mem_excpt             Indicates that an invalid address was given to
 *                          main memory. Left as a top-level input so that the
 *                          core's exception handling is not optimized away by
 *                          constant propagation.
 *
 * Outputs (the core's main-memory port, plus the fake memory's responses):
 *  - halted                The processor has stopped (syscall or exception).
 *  - mem_data_load_en      A main-memory read is requested.
 *  - mem_data_store_mask   Byte enables for a main-memory write.
 *  - mem_data_addr         The word address of the request.
 *  - mem_data_stall        The core is stalling the memory pipeline.
 *  - mem_data_store        The data to write to mem_data_addr.
 *  - mem_data_load         The (fake) data returned by main memory.
 *  - mem_data_load_addr    The address the returning data belongs to.
 *  - mem_data_load_valid   The returning data is valid this cycle.
 **/
module riscv_core_timing
    // Import the width of signals and the memory read width
    import RISCV_ISA::XLEN, RISCV_ISA::XLEN_BYTES;
    import RISCV_UArch::MEMORY_ADDR_WIDTH, RISCV_UArch::MEMORY_READ_WIDTH,
           RISCV_UArch::DMEMORY_READ_DELAY;

    (input  logic                                   clk, rst_l,
     input  logic                                   mem_excpt,
     output logic                                   halted,
     output logic                                   mem_data_load_en,
     output logic [XLEN_BYTES-1:0]                  mem_data_store_mask,
     output logic [MEMORY_ADDR_WIDTH-1:0]           mem_data_addr,
     output logic                                   mem_data_stall,
     output logic [XLEN-1:0]                        mem_data_store,
     output logic [MEMORY_READ_WIDTH-1:0][XLEN-1:0] mem_data_load,
     output logic [MEMORY_ADDR_WIDTH-1:0]           mem_data_load_addr,
     output logic                                   mem_data_load_valid);

    // Import the parameter used to control memory's combinational delay
    import RISCV_UArch::MEMORY_DELAY_WIDTH;

    // Signal to encapsulate the load/store enable signals for main memory
    logic dmem_data_en;

    /* The core, with its caches and cache controllers. Instance name kept as
     * RISCV_Core and the core instance inside it as core_inst: dc_synth.tcl's
     * per-pipeline-stage timing report keys off that hierarchy. */
    riscv_core_interface RISCV_Core (
        .clk                 (clk),
        .rst_l               (rst_l),
        .mem_excpt           (mem_excpt),
        .mem_data_load       (mem_data_load),
        .mem_data_load_addr  (mem_data_load_addr),
        .mem_data_load_valid (mem_data_load_valid),
        .mem_data_load_en    (mem_data_load_en),
        .halted              (halted),
        .mem_data_store_mask (mem_data_store_mask),
        .mem_data_addr       (mem_data_addr),
        .mem_data_stall      (mem_data_stall),
        .mem_data_store      (mem_data_store)
    );

    /* Model for the delay through the data port of main memory. */
    assign dmem_data_en = ^({mem_data_store_mask, mem_data_load_en});
    fake_memory_delay #(.LOAD_WORDS(MEMORY_READ_WIDTH), .WORD_WIDTH(XLEN),
                        .ADDR_WIDTH(MEMORY_ADDR_WIDTH),
                        .DELAY_WIDTH(MEMORY_DELAY_WIDTH),
                        .PIPELINED(DMEMORY_READ_DELAY))
    Fake_DMem_Delay(.clk, .addr(mem_data_addr), .stall(mem_data_stall),
                    .en(dmem_data_en), .data(mem_data_load));

    /* The response address and valid bit that go with that data. The
     * testbench returns them through an DMEMORY_READ_DELAY-deep shift
     * register (tb/testbench.sv, delay_buffer); for timing purposes only the
     * last stage matters, so a single register stage is modeled here, which
     * is also what fake_memory_delay does to the data itself (PIPELINED).
     * Without this the response port would be a constant and DC would delete
     * the core's fill and response-matching logic. */
    always_ff @(posedge clk, negedge rst_l) begin
        if (!rst_l) begin
            mem_data_load_addr  <= '0;
            mem_data_load_valid <= 1'b0;
        end else if (!mem_data_stall) begin
            mem_data_load_addr  <= mem_data_addr;
            mem_data_load_valid <= mem_data_load_en;
        end
    end

endmodule: riscv_core_timing

/*----------------------------------------------------------------------------
 * Model for Combinational Memory Delay
 *----------------------------------------------------------------------------*/

/**
 * A synthesizable, but behaviorally inaccurate model for main memory.
 *
 * This gives the combinational reads from memory a delay, so that the
 * synthesized design has a realistic critical path. dc_synth.tcl marks every
 * instance of this module dont_touch so the delay chain survives compile.
 *
 * Parameters:
 *  - DELAY_WIDTH   An ad-hoc parameter to control the combinational delay
 *                  between the input and output. The delay is directly
 *                  proportional to this parameter. This parameter must be
 *                  between 2 and ADDR_WIDTH/2.
 *  - PIPELINED     Nonzero registers the returned data (the memory read is
 *                  multi-cycle); zero returns it combinationally.
 *
 * Inputs:
 *  - clk           The global clock for the design.
 *  - en            A memory access is being made this cycle.
 *  - addr          The address of the data to interact with in memory.
 *  - stall         Read stall signal (if multicycle).
 * Outputs:
 *  - data          The data loaded from the addr address in memory.
 **/
module fake_memory_delay
    #(parameter LOAD_WORDS=0, WORD_WIDTH=0, ADDR_WIDTH=0, DELAY_WIDTH=0, PIPELINED=0)
    (input  logic                                   clk, en,
     input  logic [ADDR_WIDTH-1:0]                  addr,
     input  logic                                   stall,
     output logic [LOAD_WORDS-1:0][WORD_WIDTH-1:0]  data);

    // Variables for generating combinational delay
    logic                     carry0, carry1, carry2, carry3;
    logic [DELAY_WIDTH-1:0]   input_sample, mem;
    logic [2*DELAY_WIDTH-1:0] prod;   // note double-length prod

    logic [LOAD_WORDS-1:0][WORD_WIDTH-1:0]  data_comb, data_ff;

    // Create a long combinational circuit to generate delay
    assign input_sample = {addr[ADDR_WIDTH-1:ADDR_WIDTH-DELAY_WIDTH+1], en};
    assign prod         = (input_sample ^ addr[DELAY_WIDTH-1:0]) * mem;

    // Sample various values from the product to generate the data signal
    assign carry0       = prod[2*DELAY_WIDTH - 1];
    assign carry1       = prod[2*DELAY_WIDTH - 2];
    assign carry2       = prod[2*DELAY_WIDTH - 3];
    assign carry3       = prod[2*DELAY_WIDTH - 4];
    assign data_comb    = {(LOAD_WORDS*WORD_WIDTH/4){carry3, carry2, carry1, carry0}};

    // Create a register to create an endpoint inside of memory
    always @(posedge clk) begin
        mem <= (mem << 1) | addr;
        data_ff <= stall ? data_ff : data_comb;
    end

    assign data = (PIPELINED!=0) ? data_ff : data_comb;

endmodule: fake_memory_delay

`endif /* !SIMULATION_18447 */

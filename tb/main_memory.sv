/**
 * main_memory.sv
 *
 * RISC-V 32-bit Processor
 *
 * This is the main memory used by the processor (simulation model).
 *
 * The processor's main memory is a slightly non-standard DRAM. The memory is a
 * synchronous write, combinational (asynchronous) read DRAM. The memory is
 * word-addressable, and there is a write mask that allows users to selectively
 * update certain bytes of a memory word. Multi-word reads are supported via
 * the LOAD_WORDS parameter.
 *
 * The main memory is a segmented memory, divided into 5 segments by default:
 * text and data segments for both user and kernel code, and a shared stack
 * segment. The module loads the data for each segment from the corresponding
 * binary file (mem.<segment>.bin in the simulation directory).
 *
 * This model is not synthesizable, and is intended only for simulation.
 *
 * Portability notes (Verilator + VCS):
 *  - Segment metadata comes straight from the MemorySegments package instead
 *    of a module parameter, because Verilator cannot specialize modules on
 *    parameters whose type contains a string.
 *  - Storage is a flat array-per-segment rather than an array of structs, and
 *    file loading happens in an initial block rather than on the reset edge.
 *    The original relied on the X->0 transition of rst_l at time zero to fire
 *    `negedge rst_l`; that edge does not exist in 2-state simulation.
 *
 * Authors:
 *  - 2016 - 2017: Brandon Perez
 *  - 2026: lightning port (Verilator-compatible rewrite)
 **/

// This module is only included when we are running simulation.
`ifdef SIMULATION_18447

// RISC-V Includes
`include "riscv_isa.vh"             // Definition of BYTE_WIDTH
`include "memory_segments.vh"       // Definition of memory segment types

// Force the compiler to throw an error if any variables are undeclared
`default_nettype none

/*----------------------------------------------------------------------------
 * Main Memory Module
 *----------------------------------------------------------------------------*/

/**
 * A behaviorally correct, but non-synthesizable model for main memory.
 *
 * Parameters:
 *  - NUM_PORTS     The number of ports that the memory has.
 *  - LOAD_WORDS    The number of consecutive memory words read on a load.
 *  - WORD_BYTES    The number of bytes in a memory word.
 *  - ADDR_WIDTH    The number of bits used for memory addresses.
 *  - SEGMENT_WORDS The size of the memory segments in number of words.
 *
 * Inputs:
 *  - clk           The clock to use for the main memory.
 *  - rst_l         The asynchronous active-low reset for the main memory.
 *  - load_ens      Read enable for each port.
 *  - store_masks   Byte-enable bit mask indicating which bytes of store_data
 *                  should be written to the addrs address, for each port.
 *  - addrs         The address to read from and/or write to for each port.
 *  - store_data    The data to store at the given address for each port.
 *
 * Outputs:
 *  - mem_excpts    Indicates an invalid memory address was specified, per
 *                  port. Only asserted when a load or store occurs.
 *  - load_data     The data at the given address in memory for each port.
 **/
module main_memory
    // Import the memory segments type
    import MemorySegments::mem_segments_t;

    #(parameter                 NUM_PORTS=0, LOAD_WORDS=0, WORD_BYTES=0,
      parameter                 ADDR_WIDTH=0, SEGMENT_WORDS=0,
      localparam mem_segments_t SEGMENTS = MemorySegments::SEGMENTS,
      localparam                BYTE_WIDTH = RISCV_ISA::BYTE_WIDTH,
      localparam                WORD_WIDTH = WORD_BYTES * BYTE_WIDTH)
    (input  logic                                                   clk, rst_l,
     input  logic [NUM_PORTS-1:0]                                   load_ens,
     input  logic [NUM_PORTS-1:0][WORD_BYTES-1:0]                   store_masks,
     input  logic [NUM_PORTS-1:0][ADDR_WIDTH-1:0]                   addrs,
     input  logic [NUM_PORTS-1:0][WORD_WIDTH-1:0]                   store_data,
     output logic [NUM_PORTS-1:0]                                   mem_excpts,
     output logic [NUM_PORTS-1:0][LOAD_WORDS-1:0][WORD_WIDTH-1:0]   load_data);

    /*------------------------------------------------------------------------
     * Definitions
     *------------------------------------------------------------------------*/

    // The parameter to $fseek that indicates to seek from the end of file
    localparam SEEK_END                             = 2;

    // The prefix for the segment data files to which extensions are appended
    localparam string SEGMENT_FILE_PREFIX           = "mem";

    // The number of segments
    localparam NUM_SEGMENTS                         = $size(SEGMENTS);

    // The amount to shift addresses, or the alignment of memory addresses
    localparam ADDR_SHIFT                           = $clog2(WORD_BYTES);

    // Convenient typedefs for various types used by the memory system
    typedef logic  [ADDR_WIDTH-1:0]                 addr_t;
    typedef logic  [$clog2(NUM_SEGMENTS)-1:0]       index_t;
    typedef logic  [WORD_BYTES-1:0][BYTE_WIDTH-1:0] word_t;

    /* The representation of a segment index, used to determine which segment
     * to use for an operation on a given address. */
    typedef struct packed {
        logic valid;            // Indicates this is a valid index
        index_t index;          // Index of the segment in the array
    } segment_index_t;

    // The physical memory and word-aligned base address for each segment
    word_t                      seg_mem [NUM_SEGMENTS][SEGMENT_WORDS];
    addr_t                      seg_base [NUM_SEGMENTS];

    // The segment index for each memory port's address
    segment_index_t             segment_indices [NUM_PORTS];

    /* Place the segment parameters into a module variable. This allows them to
     * be seen in waveform viewers, as parameters do not show up. */
    const mem_segments_t        segment_params = SEGMENTS;

    /*------------------------------------------------------------------------
     * Core Logic
     *------------------------------------------------------------------------*/

    // Handle finding the corresponding segment for each port's address
    always_comb begin
        segment_index_loop: for (int i = 0; i < NUM_PORTS; i++) begin
            segment_indices[i] = '{valid: 1'b0, index: '0};
            if (load_ens[i] || (store_masks[i] != '0)) begin
                for (int s = 0; s < NUM_SEGMENTS; s++) begin
                    if ((seg_base[s] <= addrs[i]) &&
                        (addrs[i] < seg_base[s] + addr_t'(SEGMENT_WORDS))) begin
                        segment_indices[i] = '{valid: 1'b1, index: index_t'(s)};
                    end
                end
            end
        end
    end

    /* Handle writing to memory, merging in bytes as per the write mask.
     * Plain `always` rather than `always_ff`: seg_mem is also written by
     * the initialization `initial` block below, and VCS rejects any
     * always_ff variable driven by another process (Error-[ICPD]). */
    always @(posedge clk) begin
        data_store_loop: for (int i = 0; i < NUM_PORTS; i++) begin
            if (rst_l && segment_indices[i].valid &&
                    (store_masks[i] != '0)) begin
                automatic index_t s = segment_indices[i].index;
                automatic addr_t offset = addrs[i] - seg_base[s];
                /* View the flat store word as bytes; store_data[i][b] would
                 * select a single bit, not byte lane b. */
                automatic word_t wdata = store_data[i];
                for (int b = 0; b < WORD_BYTES; b++) begin
                    if (store_masks[i][b]) begin
                        seg_mem[s][offset][b] <= wdata[b];
                    end
                end
            end
        end
    end

    // Handle reading from memory
    always_comb begin
        load_data = 'x;
        data_load_loop: for (int i = 0; i < NUM_PORTS; i++) begin
            for (int j = 0; j < LOAD_WORDS; j++) begin
                if (segment_indices[i].valid) begin
                    automatic index_t s = segment_indices[i].index;
                    automatic addr_t offset = (addrs[i] + addr_t'(j)) - seg_base[s];
                    if (offset < addr_t'(SEGMENT_WORDS)) begin
                        load_data[i][j] = seg_mem[s][offset];
                    end
                end
            end
        end
    end

    // Handle generating memory exceptions if the address is invalid
    always_comb begin
        memory_exception_loop: for (int i = 0; i < NUM_PORTS; i++) begin
            mem_excpts[i] = rst_l & ((store_masks[i] != 'b0) | load_ens[i]) &
                ~segment_indices[i].valid;
        end
    end

    /*------------------------------------------------------------------------
     * Initialization
     *------------------------------------------------------------------------*/

    /* Initialize each segment to a bad value for debugging, then load its
     * contents from the corresponding binary file, one byte at a time to
     * ensure little-endian ordering ($fread reads big-endian). */
    initial begin
        for (int s = 0; s < NUM_SEGMENTS; s++) begin
            string segment_path;
            int segment_fd, file_size;
            int word_index, byte_index, bytes_read;
            logic [BYTE_WIDTH-1:0] data_byte;

            seg_base[s] = addr_t'(segment_params[s].base_addr >> ADDR_SHIFT);
            for (int w = 0; w < SEGMENT_WORDS; w++) begin
                seg_mem[s][w] = {WORD_BYTES{8'hde}};
            end

            // Segments without a data file (the stack) are left as-is
            if (segment_params[s].extension.len() != 0) begin
                segment_path = {SEGMENT_FILE_PREFIX,
                        segment_params[s].extension};
                segment_fd = $fopen(segment_path, "rb");
                if (segment_fd == 0) begin
                    $fatal(1, "Error: %s: Unable to open file.", segment_path);
                end

                // Check that the file fits in the memory segment
                void'($fseek(segment_fd, 0, SEEK_END));
                file_size = $ftell(segment_fd);
                void'($rewind(segment_fd));
                if (file_size > SEGMENT_WORDS * WORD_BYTES) begin
                    $fatal(1, "Error: %s: File is too large for memory segment.",
                            segment_path);
                end

                word_index = 0;
                byte_index = 0;
                while (1) begin
                    bytes_read = $fread(data_byte, segment_fd);
                    if (bytes_read == 0) begin
                        break;
                    end

                    seg_mem[s][word_index][byte_index] = data_byte;
                    byte_index += 1;
                    if (byte_index == WORD_BYTES) begin
                        byte_index = 0;
                        word_index += 1;
                    end
                end
                $fclose(segment_fd);
            end
        end
    end

endmodule: main_memory

`endif /* SIMULATION_18447 */

/**
 * memory_segments.vh
 *
 * RISC-V 32-bit Processor
 *
 * ECE 18-447
 * Carnegie Mellon University
 *
 * This file contains the definitions for the segments in the processor memory.
 *
 * This defines the metadata about each segment in memory, namely its starting
 * address and maximum size. This also defines an array that contains all the
 * segments that are present in the processor's memory.
 *
 * Authors:
 *  - 2017: Brandon Perez
 **/

/*----------------------------------------------------------------------------*
 *                          DO NOT MODIFY THIS FILE!                          *
 *          You should only add or change files in the src directory!         *
 *----------------------------------------------------------------------------*/

`ifndef MEMORY_SEGMENTS_VH_
`define MEMORY_SEGMENTS_VH_

`include "riscv_isa.vh"             // Definition of XLEN_BYTES

package MemorySegments;

/*----------------------------------------------------------------------------
 * Memory Segment Addresses
 *----------------------------------------------------------------------------*/

    // Import the number of bytes in a word/register
    import RISCV_ISA::XLEN_BYTES;

    // The number of memory segments in the processor
    parameter NUM_SEGMENTS          = 5;

    /* The size of each segment in bytes. The size of each segment is kept
     * fixed, so that its size is known at elaboration-time, allowing for memory
     * dumps for the DVE GUI. */
    parameter SEGMENT_SIZE          = 512 * 2 ** 10;
    localparam SEGMENT_WORDS        = SEGMENT_SIZE / XLEN_BYTES;

    // The starting addresses of the user's data and text segments
    parameter USER_TEXT_START       = 'h0040_0000;
    parameter USER_DATA_START       = 'h1000_0000;

    // The starting and ending addresses of the stack segment, and its size
    parameter STACK_END             = 'h7ff0_0000;
    localparam STACK_START          = STACK_END - SEGMENT_SIZE;

    // The starting addresses and sizes of the kernel's data, and text segments
    parameter KERNEL_TEXT_START     = 'h8000_0000;
    parameter KERNEL_DATA_START     = 'h9000_0000;

/*----------------------------------------------------------------------------
 * Memory Segment Definitions
 *----------------------------------------------------------------------------*/

// These definitions are only needed for simulation
`ifdef SIMULATION_18447

    // The representation of a memory segment's parameters
    typedef struct {
        longint base_addr;          // Start of the segment in memory
        string extension;           // Extension for the segment's data file
        string name;                // Name of the segment for debugging
    } mem_segment_t;

    /* An array of parameters for several memory segments. This typedef is
     * needed because VCS throws a syntax error if an unbounded array is used as
     * a parameter to a module. */
    typedef mem_segment_t           mem_segments_t[NUM_SEGMENTS];

    // The user text memory segment, containing user code
    parameter mem_segment_t USER_TEXT_SEGMENT = '{
        base_addr:                  USER_TEXT_START,
        extension:                  ".text.bin",
        name:                       "User Text"
    };

    // The user data memory segment, containing user global variables
    parameter mem_segment_t USER_DATA_SEGMENT = '{
        base_addr:                  USER_DATA_START,
        extension:                  ".data.bin",
        name:                       "User Data"
    };

    /* The stack memory segment, containing local values in the program. This is
     * shared by kernel and user code. */
    parameter mem_segment_t STACK_SEGMENT = '{
        base_addr:                  STACK_START,
        extension:                  "",
        name:                       "Stack"
    };

    // The kernel text segment, containing kernel code
    parameter mem_segment_t KERNEL_TEXT_SEGMENT = '{
        base_addr:                  KERNEL_TEXT_START,
        extension:                  ".ktext.bin",
        name:                       "Kernel Text"
    };

    // The kernel data segment, containing kernel global variables
    parameter mem_segment_t KERNEL_DATA_SEGMENT = '{
        base_addr:                  KERNEL_DATA_START,
        extension:                  ".kdata.bin",
        name:                       "Kernel Data"
    };

    // Array containing metadata for all the segments in the processor's memory
    parameter mem_segments_t SEGMENTS = '{
        USER_TEXT_SEGMENT, USER_DATA_SEGMENT, STACK_SEGMENT,
        KERNEL_TEXT_SEGMENT, KERNEL_DATA_SEGMENT
    };

`endif /* SIMULATION_18447 */

endpackage: MemorySegments

`endif /* MEMORY_SEGMENTS_VH_ */

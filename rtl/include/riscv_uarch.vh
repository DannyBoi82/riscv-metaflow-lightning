/**
 * riscv_uarch.vh
 *
 * RISC-V 32-bit Processor
 *
 * ECE 18-447
 * Carnegie Mellon University
 *
 * This file contains definitions for the RISC-V microarchitecture
 * implemented by this processor. Namely, this defines parameters that determine
 * the processor's underlying architecture.
 *
 * Authors:
 *  - 2017: Brandon Perez
 **/

/*----------------------------------------------------------------------------*
 *                          DO NOT MODIFY THIS FILE!                          *
 *          You should only add or change files in the src directory!         *
 *----------------------------------------------------------------------------*/

`ifndef RISCV_UARCH_VH_
`define RISCV_UARCH_VH_

// Local Includes
`include "riscv_isa.vh"                 // Definition of word width and bytes
`include "config.vh"                    // Centralized hardware configuration

/*----------------------------------------------------------------------------
 * Definitions
 *----------------------------------------------------------------------------*/

package RISCV_UArch;

    // Import the width of addresses in the architecture and byte per word
    import RISCV_ISA::XLEN, RISCV_ISA::XLEN_BYTES;

    // Half of the period of the clock for the processor (simulation only)
    parameter CLOCK_HALF_PERIOD         = `LTG_CLOCK_HALF_PERIOD;

    // Simulation watchdog limit; the testbench $finishes past this cycle
    parameter MAX_SIM_CYCLES            = `LTG_MAX_SIM_CYCLES;

    // Execution processing width (multiplies the number of regfile ports)
    parameter SUPERSCALAR_WAYS          = `LTG_SUPERSCALAR_WAYS;

    // Number of consecutive words returned by memory read
    parameter MEMORY_READ_WIDTH         = `LTG_MEM_READ_WIDTH;

    // Number of clock edges in memory read delay
    parameter IMEMORY_READ_DELAY        = `LTG_IMEM_READ_DELAY;

    parameter DMEMORY_READ_DELAY        = `LTG_DMEM_READ_DELAY;

    // The width of words in the SRAM used for the branch target buffer (BTB)
    parameter BTB_WORD_WIDTH            = 62;

    // The number of words (entries) in the SRAM used for the BTB, by default
    parameter BTB_NUM_WORDS             = 128;

    /* The width of the addresses used by main memory. The addresses only need
     * to be wide enough to address words in memory. */
    localparam MEMORY_ADDR_WIDTH        = XLEN - $clog2(XLEN_BYTES);

    // The number of ports that the processor's main memory has
    parameter MEMORY_NUM_PORTS          = 1;

    /* The ad-hoc parameter used to control the combinational delay in model for
     * main memory (synthesis only). */
    parameter MEMORY_DELAY_WIDTH        = 8;

endpackage: RISCV_UArch

`endif /* RISCV_UARCH_VH_ */

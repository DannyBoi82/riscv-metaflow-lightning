/**
 * sim.h
 *
 * RISC-V 32-bit Instruction Level Simulator
 *
 * ECE 18-447
 * Carnegie Mellon University
 *
 * This file contains the interface to the core part of the simulator. The core
 * simulator handles carrying out the actions required by instructions.
 *
 * Authors:
 *  - 2016 - 2017: Brandon Perez
 **/

/*----------------------------------------------------------------------------*
 *                          DO NOT MODIFY THIS FILE!                          *
 *          You should only add or change files in the src directory!         *
 *----------------------------------------------------------------------------*/

#ifndef SIM_H_
#define SIM_H_

// Standard Includes
#include <stdbool.h>                    // Boolean type and definitions
#include <stdint.h>                     // Fixed-size integral types
#include <stdio.h>

// Local Includes
#include "riscv_isa.h"                  // RISC-V ISA, the number of registers
#include "memory.h"                     // Interface to the processor memory

/*----------------------------------------------------------------------------
 * Definitions
 *----------------------------------------------------------------------------*/

// A structure representing all of the state in a processor.
typedef struct cpu_state {
    bool verbose_mode;                  // Indicates if verbose mode is active
    bool trace_mode;                    // Indicates if trace mode is active
    FILE *trace_fd;                     // Trace file descriptor
    bool statetrace_mode;               // Indicates if state-trace mode is active
    FILE *statetrace_fd;                // State-trace file descriptor
    bool memtrace_mode;                 // Indicates if memory-op tracing is active
    FILE *memtrace_fd;                  // Memory-op trace file descriptor
    bool halted;                        // Indicates if the CPU is halted
    int cycle;                          // Number of processor cycles
    uint32_t pc;                        // Current program counter
    char *program;                      // Name of the currently loaded program
    memory_t memory;                    // Processor memory segments
    uint32_t registers[RISCV_NUM_REGS]; // CPU register file
} cpu_state_t;

/*----------------------------------------------------------------------------
 * Interface
 *----------------------------------------------------------------------------*/

/**
 * Simulates a single cycle on the CPU, updating the CPU's state as needed.
 *
 * This is the core part of the simulator. This simulates the current
 * instruction pointed to by the PC. This performs the necessary actions for the
 * instruction, and updates the CPU state appropriately.
 *
 * You implement this function.
 *
 * Inputs:
 *  - cpu_state     The current state of the CPU being simulated.
 *
 * Outputs:
 *  - cpu_state     The next state of the CPU being simulated. This function
 *                  updates the fields of the state as needed by the current
 *                  instruction to simulate it.
 **/
void process_instruction(cpu_state_t *cpu_state);

/**
 * Records one committed memory operation to the memory-op trace.
 *
 * This is the reference half of the verify-mem flow (see the 'memtrace' shell
 * command and scripts/check_mem_trace.py): one line per load/store the program
 * architecturally performs, which the RTL's committed memory ops are diffed
 * against. It is a no-op unless memtrace mode is active, so the load/store
 * cases in process_instruction() can call it unconditionally.
 *
 * Inputs:
 *  - cpu_state     The state of the CPU being simulated.
 *  - pc            PC of the load/store instruction (*before* it is advanced).
 *  - is_store      True for a store, false for a load.
 *  - addr          Byte address of the access, unaligned low bits included.
 *  - mask          Byte enables of the access within its containing word,
 *                  i.e. size and lane: 0xf/0x3/0xc/0x1/0x2/0x4/0x8.
 *  - data          The bytes transferred, positioned in their word lanes
 *                  (bytes outside `mask` must be zero). No sign extension:
 *                  this is the value on the memory bus, not in the register.
 **/
void memtrace_record(cpu_state_t *cpu_state, uint32_t pc, bool is_store,
        uint32_t addr, uint32_t mask, uint32_t data);

#endif /* SIM_H_ */

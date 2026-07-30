/**
 * config.vh
 *
 * Lightning — centralized hardware configuration.
 *
 * Every tunable hardware parameter in the design lives here as an
 * `ifndef`-guarded LTG_* macro. The RTL derives its parameters from these
 * macros (see rtl/include/parameters.vh, rtl/include/riscv_uarch.vh, and
 * rtl/ooo/1DRIS_defs.sv), so this is the one file to edit for persistent
 * changes.
 *
 * Because every macro is `ifndef`-guarded, any knob can also be overridden
 * per build without editing this file, identically under Verilator and VCS:
 *
 *     make verify TEST=tests/asm/additest.S PARAMS='+define+LTG_DRIS_ENTRIES=32'
 *
 * scripts/cache_sweep.py rewrites the cache macros in this file when
 * sweeping configurations.
 **/

`ifndef LIGHTNING_CONFIG_VH_
`define LIGHTNING_CONFIG_VH_

/*----------------------------------------------------------------------------
 * L1 caches (consumed by rtl/include/parameters.vh)
 *----------------------------------------------------------------------------*/

// Instruction cache: ways, index bits (sets = 2**index), replacement policy
// (1 = LRU), and block offset bits (words per block = 2**offset)
`ifndef LTG_ICACHE_WAYS
`define LTG_ICACHE_WAYS 2
`endif
`ifndef LTG_ICACHE_INDEX_BITS
`define LTG_ICACHE_INDEX_BITS 5
`endif
`ifndef LTG_ICACHE_POLICY
`define LTG_ICACHE_POLICY 1
`endif
`ifndef LTG_ICACHE_BLOCK_OFFSET_BITS
`define LTG_ICACHE_BLOCK_OFFSET_BITS 2
`endif

// Data cache: same knobs as the instruction cache
`ifndef LTG_DCACHE_WAYS
`define LTG_DCACHE_WAYS 2
`endif
`ifndef LTG_DCACHE_INDEX_BITS
`define LTG_DCACHE_INDEX_BITS 5
`endif
`ifndef LTG_DCACHE_POLICY
`define LTG_DCACHE_POLICY 1
`endif
`ifndef LTG_DCACHE_BLOCK_OFFSET_BITS
`define LTG_DCACHE_BLOCK_OFFSET_BITS 2
`endif

/*----------------------------------------------------------------------------
 * Out-of-order engine (consumed by rtl/ooo/1DRIS_defs.sv)
 *----------------------------------------------------------------------------*/

// DRIS (Deferred-scheduling Register Instruction Shelf) entries
`ifndef LTG_DRIS_ENTRIES
`define LTG_DRIS_ENTRIES 32
`endif

// Instructions fetched/renamed per cycle
`ifndef LTG_FETCH_WAYS
`define LTG_FETCH_WAYS 4
`endif

// Execution units / instructions issued per cycle
`ifndef LTG_EXECUTE_WAYS
`define LTG_EXECUTE_WAYS 4
`endif

// Register file write ports (wider than issue, per Lightning)
`ifndef LTG_REG_FILE_WRITE_PORTS
`define LTG_REG_FILE_WRITE_PORTS 7
`endif

// Memory write ports (stores serialized by oldest constraint)
`ifndef LTG_MEMORY_WRITE_PORTS
`define LTG_MEMORY_WRITE_PORTS 1
`endif

// Memory read ports (for load-store queue; sizes the writeback array)
`ifndef LTG_MEMORY_READ_PORTS
`define LTG_MEMORY_READ_PORTS 1
`endif

// Branches in flight at once (sizes branch mask in issue unit and predictor)
`ifndef LTG_BRANCH_WAYS
`define LTG_BRANCH_WAYS 1
`endif

// Unresolved speculative branches the branch shelf can hold
`ifndef LTG_BRANCH_SHELF_ENTRIES
`define LTG_BRANCH_SHELF_ENTRIES 8
`endif

// DRIS entries the scheduler checks for readiness each cycle
`ifndef LTG_SCHED_ENTRIES_CHECKED
`define LTG_SCHED_ENTRIES_CHECKED 16
`endif

/*----------------------------------------------------------------------------
 * Memory model timing and clock (consumed by rtl/include/riscv_uarch.vh)
 *----------------------------------------------------------------------------*/

// Number of clock edges of instruction / data memory read delay
`ifndef LTG_IMEM_READ_DELAY
`define LTG_IMEM_READ_DELAY 2
`endif
`ifndef LTG_DMEM_READ_DELAY
`define LTG_DMEM_READ_DELAY 8
`endif

// Consecutive words returned by a memory read
`ifndef LTG_MEM_READ_WIDTH
`define LTG_MEM_READ_WIDTH 4
`endif

// Execution processing width (multiplies the number of regfile ports)
`ifndef LTG_SUPERSCALAR_WAYS
`define LTG_SUPERSCALAR_WAYS 1
`endif

// Half of the clock period for the processor (simulation only)
`ifndef LTG_CLOCK_HALF_PERIOD
`define LTG_CLOCK_HALF_PERIOD 50
`endif

/* Simulation watchdog: force $finish after this many cycles if the core
 * never halts (a livelocked test otherwise runs — and logs — forever; the
 * per-cycle unknown-opcode $displays once produced an 18 GB log). The
 * largest legitimate class test retires in ~7.2M cycles, so 20M is ~3x
 * headroom; raise per run via PARAMS if a workload needs more. */
`ifndef LTG_MAX_SIM_CYCLES
`define LTG_MAX_SIM_CYCLES 20000000
`endif

`endif /* LIGHTNING_CONFIG_VH_ */

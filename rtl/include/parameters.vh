/**
 * parameters.vh
 *
 * Lightning — cache parameter declarations.
 *
 * These parameters are derived from the central configuration in
 * rtl/include/config.vh; edit the LTG_* macros there (or override them with
 * PARAMS='+define+...' on the make command line) rather than editing the
 * values here.
 **/

`ifndef L1_POLICIES
`define L1_POLICIES

`include "config.vh"

parameter INSTR_CACHE_WAYS              = `LTG_ICACHE_WAYS;
parameter INSTR_CACHE_INDEX_BITS        = `LTG_ICACHE_INDEX_BITS;
parameter INSTR_CACHE_POLICY            = `LTG_ICACHE_POLICY;
parameter INSTR_CACHE_BLOCK_OFFSET_BITS = `LTG_ICACHE_BLOCK_OFFSET_BITS;
parameter INSTR_CACHE_BLOCK_SIZE        = 2 ** INSTR_CACHE_BLOCK_OFFSET_BITS;

parameter DATA_CACHE_WAYS               = `LTG_DCACHE_WAYS;
parameter DATA_CACHE_INDEX_BITS         = `LTG_DCACHE_INDEX_BITS;
parameter DATA_CACHE_POLICY             = `LTG_DCACHE_POLICY;
parameter DATA_CACHE_BLOCK_OFFSET_BITS  = `LTG_DCACHE_BLOCK_OFFSET_BITS;
parameter DATA_CACHE_BLOCK_SIZE         = 2 ** DATA_CACHE_BLOCK_OFFSET_BITS;

parameter ADDRESS_SIZE = 30;
parameter WORD_SIZE    = 32;

`endif

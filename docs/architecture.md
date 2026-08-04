# Architecture & file map

What every file/module does and how they fit together, so a new session
doesn't have to re-explore the tree. Companion docs: `docs/porting-log.md`
(migration history + gotchas, **read before touching harness/build**),
`docs/TODO-verify-trace.md` (commit-trace design), `docs/TODO-IIU.md`,
`docs/new-repo.md` (original migration plan), `docs/TODO-memory.md` (memory
unit design + working notes), `docs/memorable-bugs.md`. Last updated:
2026-07-31.

## Big picture

Two RISC-V RV32I cores share one simulation harness and one build system:

- **Lightning** (`rtl/ooo/`, `CORE=lightning`, default) — the OoO
  DRIS/Metaflow-style core being built. The memory unit (`MemoryScheduler`
  + the D-side cache seam) landed 2026-07-30, so loads and stores now
  work: all of `tests/asm` passes except the 3 mul tests (no M extension
  anywhere), under `make verify` and `make verify-trace` alike — the
  commit seam landed 2026-07-31.
- **In-order core** (`rtl/core/riscv_core.sv`, `CORE=inorder`) — the blessed
  8-stage class core (passes the full autograder suite). Used as a known-good
  rig for harness work (e.g. the verify-trace flow) so harness bugs are never
  confused with Lightning bugs.

Both are wrapped by a module named `riscv_core_interface` (one file per
core in `rtl/mem/`; the Makefile compiles exactly one, selected by `CORE`
in config.mk). The testbench only ever sees that module name.

Simulation stack, top to bottom:

    tb/testbench.sv (module top)
      ├─ clock generator, reset, cycle counter, watchdog, $finish-on-halt
      ├─ main_memory (behavioral, loads mem.*.bin sections)
      ├─ delay_buffer (models multi-cycle pipelined memory latency)
      └─ riscv_core_interface          <- CORE knob picks the file
           ├─ [lightning] LightningCore + 2x cache_controller2 (I + D)
           └─ [inorder]   riscv_core   + 2x cache_controller_ref
                                (each core instantiates register_file inside
                                 itself as instance `rf`)

Verification chain: `tools/refsim` (C instruction-level simulator) generates
`.reg` register-dump oracles; `make verify` diffs the RTL's end-of-run dump
against them. The **verify-trace** flow (`make verify-trace`, blessed on
CORE=inorder) additionally compares full architectural register state per
committed instruction: cores emit `commit_pkt_t` packets at retirement
(defined in `rtl/include/riscv_commit.vh`, assembled by `register_file` —
but any core can emit them directly, see README), the tb-side
`commit_verifier` reconstructs/prints state per commit (and produces the
end-of-run dump from the same shadow state), and
`scripts/check_commit_trace.py` diffs that against the refsim's
per-instruction trace (`statetrace` command).

## Build system

- `Makefile` — single entry point. Targets: `verify` (sim + diff vs .reg
  oracle), `verify-trace` (per-commit state compare vs refsim: reftrace +
  sim with `+commit_trace` + checker), `reftrace`, `regress` (all tests
  with oracles, or `TESTS=glob`), `sim`, `waves` (FST+gtkwave / DVE),
  `build`, `lint` (verilator -Wall + lint.vlt waivers), `assemble`,
  `toolchain`, `refsim`/`refdump` (C reference sim), `synth` (DC, AFS
  only). SV sources are auto-discovered from `rtl/core rtl/ooo rtl/mem tb`
  (sorted per dir; `0`/`1` filename prefixes put packages first). CORE
  selection filters out the non-selected `riscv_core_interface*.sv`.
  A flags stamp (`.buildflags`) forces rebuild when
  SIM/CORE/PARAMS/SEED/WAVES/TRACE change; `PLUSARGS=` passes extra
  runtime plusargs (no rebuild).
- `config.mk` — build knobs: `SIM` (verilator|vcs), `CORE`
  (lightning|inorder), `RISCV_PREFIX`/`RISCV_ARCH` (toolchain, rv32im),
  `OPT`, `PARAMS` (+define+LTG_* passthrough), `SEED` (X-shakeout),
  output dirs, `REFSIM_EXECUTABLE`, `VERILATOR` (pinned to ~/.local v5.048
  -O1 build — stock -O3 builds segfault, see porting log).
- `rtl/include/config.vh` — every hardware knob as `ifndef`-guarded `LTG_*`
  macro (cache geometry, DRIS sizing, fetch/superscalar ways, memory
  latencies, `LTG_MAX_SIM_CYCLES` watchdog). Override per run via
  `PARAMS='+define+LTG_...=N'`.
- `lint.vlt` — documented Verilator waivers (style categories global-off +
  targeted waivers). Keep `make lint` at zero warnings.
- `synth/dc_synth.tcl` — broken AFS symlink; synthesis is AFS-host-only.

## rtl/include — shared packages & macros (all `.vh`, include-guarded)

| File | Contents |
|---|---|
| `config.vh` | All `LTG_*` hardware knobs (the design's config space). |
| `riscv_isa.vh` | `package RISCV_ISA`: XLEN, NUM_REGS, opcode/funct enums. |
| `riscv_abi.vh` | `package RISCV_ABI`: register aliases (SP, GP, RA...), `ECALL_ARG_HALT`. |
| `riscv_uarch.vh` | `package RISCV_UArch`: harness-facing uarch params derived from LTG_* (SUPERSCALAR_WAYS, memory port/latency params, CLOCK_HALF_PERIOD, MAX_SIM_CYCLES). |
| `memory_segments.vh` | `package MemorySegments`: memory map (USER_TEXT_START 0x400000, USER_DATA_START 0x10000000, STACK_END 0x7ff00000, segment table used by main_memory). |
| `riscv_commit.vh` | `package RISCV_Commit`: `commit_pkt_t` (RVFI-subset: valid, pc_rdata, insn, rd_addr with 0="no write", rd_wdata) + `COMMIT_WAYS_MAX` — the design-independent retirement contract for verify-trace. |
| `internal_defines.vh` | Class-era control-signal typedefs used by the in-order core (`ctrl_signals_t` etc. — the `.vh` twin of `0internal_defines_pkg.sv`). |
| `parameters.vh` | Cache geometry/word-size localparams used by the core interfaces (derives from config.vh). |

## rtl/core — in-order core (+ decode shared with Lightning)

- `0internal_defines_pkg.sv` — `package internal_defines_pkg`:
  `ctrl_signals_t`, ALU-op/imm-mode/pc-source enums, `CTRL_SIGNALS_NOOP`,
  bubble PC tags (`pc_mispredict_flush`=4'd11, `pc_stall_bubble`=4'd13).
  Imported by Lightning and the in-order core alike.
- `riscv_decode.sv` — one-instruction combinational decoder
  (instr → `ctrl_signals_t`). Used by the in-order core's D stage **and**
  instantiated per fetch slot inside Lightning's IIU. ECALL decodes with
  `uses_rs1`/`uses_rs2` set and both source registers forced to a0, with
  `alu_op = ALU_PASS`, so a0 flows to the ALU result — Lightning needs it
  there to tell a halting ecall (a0 == 10) from any other syscall. Shared
  with the in-order core; verified no regression there.
- `riscv_core.sv` — the 8-stage in-order pipeline
  (F1→F2→F3→D→E→M1→M2→W; 3 fetch stages cover the 2-cycle I$, M1/M2 the
  2-cycle D$). BTB branch prediction resolved in M1; D-stage forwarding;
  bubbles are injected as NOPs with tagged PCs (see pkg above) or
  `CTRL_SIGNALS_NOOP`. Halt = ecall with a0=ECALL_ARG_HALT reaching W (or
  exception). Quirk to know: on a mispredict the resolved control-flow op
  is latched from M1 into M2 **twice** (M1 doesn't refill that cycle) — an
  architecturally invisible replay handled by the commit valid chain, which
  tracks real instructions (`valid_F2..valid_W`) and marks the stale copy
  invalid. Commit seam: `commit_fire = valid_W & ~stall_W`; pc/insn ride
  the pipe to W and feed `register_file`'s commit inputs; packets exit
  through a `SIMULATION_18447`-guarded `commit_pkts` port. `TRACE`/`PERF`
  ifdefs enable a per-cycle $display trace and performance counters.
- `lib.sv` — small structural pieces used by riscv_core: `mux`, `adder`,
  `register`, `RDDataMux` (load-align/writeback select), `DataMasker`
  (store lane shift), `DataStoreMaskGenerator`, `riscv_alu`,
  `ImmediateGenerator`, `BTBPredictor`, forwarding/stall controllers.

## rtl/ooo — Lightning (DRIS/Metaflow OoO core)

**Memory is two-phase**, per the Metaflow spec, and that shapes most of
what follows: phase 1 is an ordinary ALU dispatch that computes the
address (parked in the entry's `result_data`, marked `mem_addr_ready`,
*no* result published); phase 2 is a second schedule by the
`MemoryScheduler` against the D-cache. Loads write back their data
through a dedicated DRIS writeback port; stores are released to the cache
only at retirement.

- `1DRIS_defs.sv` — `package DRIS_defs`: sizes derived from LTG_*
  (DRIS_NUM_ENTRIES=32, FETCH_WAYS=4, EXECUTE_WAYS=4,
  REG_FILE_WRITE_PORTS=7, MEMORY_READ_PORTS=1, MEMORY_WRITE_PORTS=1...)
  and every inter-unit packet/struct type (`dris_entry_t` — including the
  `mem_addr_ready` entry-state bit, `dris_intake_pkt_t`, `issue_pkt_t`,
  `memory_issue_pkt_t` (the D-side request: addr/re/we/store mask+data,
  plus the DRIS id and ctrl_signals that ride through the cache),
  `dris_writeback_pkt_t`, `reg_file_commit_pkt_t`, `dris_id_t` with wrap
  bit, lockers). Also `MEM_WORD_SIZE`/`MEM_ADDRESS_SIZE`, derived from
  XLEN because a package can't see `parameters.vh`'s $unit-scope decls.
- `DRIS.sv` — the Deferred-scheduling Register Instruction Shelf: the
  central instruction/result buffer (unified ROB+RS+rename via "lockers").
  Intake from IIU, writeback ports from exec ways + the load return, entry
  array read by Scheduler/MemoryScheduler/SSC. Drops writebacks whose entry
  was flushed. Two subtleties worth knowing:
  - **AGU-pass writebacks don't publish.** A load/store writeback arriving
    while `mem_addr_ready` is still 0 is the address phase: it stores
    `result_data`, sets `mem_addr_ready`, and *clears* `dispatched` (so the
    MemoryScheduler can pick it up), but leaves `result_valid`/`executed` at
    0 and suppresses the unlock broadcast. Publishing there would hand
    dependents the address as their operand.
  - **Same-cycle intake bypass** (`completing_wb()`): a dependent renamed in
    the same cycle its producer's completing writeback fires must not lock —
    the unlock broadcast scans the *old* locker state and can't see the
    newborn entry, so the lock would never clear. AGU passes are excluded
    from the bypass for the reason above.
  - The syscall trap bit is set only for `syscall && result_data == 10`
    (a0 == `ECALL_ARG_HALT`); other ecalls retire normally. That is what
    makes `syscalltest` pass.
- `InstructionIssueUnit.sv` — front end: drives the I-cache controller
  seam (request/cancel), receives FETCH_WORDS-wide fetch groups,
  per-slot `riscv_decode`, renames against DRIS lockers, emits
  prefix-contiguous intake groups (slot w gets DRIS ID fetch_ptr+w);
  contains `BranchShelf` (verifies branches/JALRs, fences retirement via
  oldest-branch id, triggers flush masks on mispredict, trains the BTB).
- `Scheduler.sv` — the integer/phase-1 scheduler: scans a window of DRIS
  entries from the retire pointer for ready instructions, reads operands
  (DRIS lockers or regfile read ports), issues up to EXEC_UNITS
  packets/cycle, marks entries dispatched. Loads/stores go through here
  too, for their address computation.
- `MemoryScheduler.sv` — phase 2. Scans the same window for (a) loads whose
  address is ready and (b) the one store the SSC has declared releasable,
  and drives up to `TOTAL_PORTS` `memory_issue_pkt_t`s. Ordering rules:
  - A load may not issue past an older store whose address isn't computed
    yet (*imprecise* case) or whose address matches (*unsafe* case) —
    `check_older_writes()`.
  - A store may only issue in a cycle where its entry is in `retire_vector`,
    i.e. it is actually retiring — memory is written only by the oldest
    instruction, per the patent.
  - Store data (and only store data) is read from the regfile at issue, on
    rs2; the address already rides the entry's `result_data`.
  - `UNIFIED_RW_PORTS` (the default, set at the top of the file) shares one
    port set between loads and stores, filling stores first so writes win;
    `SEPARATE_RW_PORTS` splits them by direction. Elaboration fails if
    neither is defined.
- `IntExecutionUnit.sv` — one ALU way: `riscv_alu` + next-PC calc
  (`PC_cond`/`PC_uncond`/`PC_indirect`) → `dris_writeback_pkt_t`. Was an
  inline `ExecutionUnit` module inside LightningCore until the memory work
  split it out.
- `LightningCore.sv` — top: wires IIU → DRIS → Scheduler → registered
  issue stage → per-way `IntExecutionUnit` → writeback/update bus → DRIS;
  MemoryScheduler and SSC beside all of it; instantiates `register_file`
  (RF_WAYS = retire slots) written by the SSC's `reg_commits`. Also owns:
  - **The D-cache port drive** (`d_request_drive`): `MEM_ISSUE_WAYS` issue
    packets arbitrated down to the single cache request. Must stay
    combinational — the controller probes live and the SSC gates a store's
    retirement on `d_cache_ready` in the same cycle the store issues, so a
    registered request would retire the store before the cache saw it. It
    also must fall back to idle, or the last request replays forever.
  - **The load return path**: `writeback_pkts[EXEC_UNITS]` is driven
    straight from `core_rsp_*_d` (id, valid, ctrl_signals), with
    `get_load_data()` doing the sign/zero-extending byte/half alignment
    using the byte offset from the entry's parked address.
  - Regfile read ports are split by owner: ways `[0, EXEC_UNITS)` to the
    integer Scheduler, `[EXEC_UNITS, EXEC_UNITS+MEM_ISSUE_WAYS)` to the
    MemoryScheduler; leftover pairs read x0.
  - Exec stage is a real pipeline stage — never clear `issue_pkts_reg` on
    flush (older in-flight instructions must complete). `halted` =
    trapping entry (halting ecall / illegal) reaching the retire head.
  - **The commit seam** (bottom of the file): drives `commit_pkts` for
    verify-trace. The SSC's `reg_commits` can't source them (no pc, and
    no packet at all for a retirement that writes no register), so slot
    s's valid/pc come straight off the retirement seam — `retire_vector`
    indexed at `retire_ptr + s`, the inverse of the SSC's scatter — while
    `register_file` fills the register-write half from write port s, the
    same slot. `insn` is reported only in `DEBUG builds (that is when the
    DRIS entry keeps the instruction word; it is a stripped comment field
    in the trace, so the diff does not depend on it). A halting
    ecall never retires, so `halted` forces one final packet at slot 0
    (pc = `trap_pc`, no register write) to match the refsim, which does
    execute it.
- `SaneStateController.sv` — retirement: walks the DRIS from the retire
  pointer, retires completed entries in program order up to the branch
  fence, drives `reg_commits` to the regfile write ports (highest way =
  youngest wins on WAW), raises `trap_valid` on halting-syscall/illegal
  (= halt). Memory-related duties:
  - It no longer computes `clear_valid`; it publishes raw
    `retire_vector` and `flush_vector` (both **entry-indexed**, not
    slot-indexed — `retire_ready_vector` is a window counted from
    `retire_ptr` and gets scattered back onto entry indices) and lets each
    consumer decide. The DRIS ORs them into its valid-clear; the
    MemoryScheduler uses `retire_vector` as the store-release gate.
  - `store_ready`/`store_id` name the entry at the retire head when it is a
    valid store with its address computed. Retire slot 0 additionally
    treats `store_ready & d_cache_ready` as eligible, so a store retires
    exactly in the cycle the cache accepts its write.
  - `RETIRES_PER_CYCLE` = `REG_RETIRES_PER_CYCLE` (regfile write ports) +
    `MEMORY_RETIRES_PER_CYCLE` (memory write ports).

## rtl/mem — cache controllers, caches, core interfaces

- `riscv_core_interface.sv` — **lightning** wrapper: LightningCore +
  I-side `cache_controller2` (FETCH_WORDS-wide responses) + D-side
  `cache_controller2` driven by the core's MemoryScheduler; arbitration
  mux between I/D controllers onto the single testbench memory port. The
  I-side ties off the id/ctrl_signals request fields (id = 6'hF) and
  leaves the matching response fields unconnected — only the D-side uses
  them.
- `riscv_core_interface_inorder.sv` — **inorder** wrapper (the old class
  seam): riscv_core + two `cache_controller_ref` (instances `tony`/
  `tony_d`), same outer port list as the lightning wrapper.
- `cache_controller_ref.sv` — refactored class write-through controller
  (1-word responses, 2-deep response FIFO, live request acceptance).
- `cache_controller2.sv` — writeback / write-allocate controller, same
  seam and timing contract as ref; used by Lightning (I-side widened to
  FETCH_WORDS). Carries a `dris_id_t` + `ctrl_signals_t` alongside each
  request: latched with the in-process request, pushed through the
  response FIFO with the data, and returned as `core_rsp_id`/
  `core_rsp_ctrl_signals` — that's how an out-of-order load response finds
  its DRIS entry and knows its load width.
- `cache3.sv` — the cache array behind the controllers (ways/sets/policy
  parameterized, eviction/hit/miss counters exported).
- `fifo.sv` — response FIFO used by the controllers (deq_data split into
  its own always_comb — do not re-merge, see porting log UNOPTFLAT).
- `sram_simulation.sv` / `sram_synthesis.sv` — SRAM models (1r1w, 1rw,
  1rw1r, 2rw) — sim behavioral vs synthesis-mapped; cache3/BTB use them.

## tb — simulation harness (single SV top, valid for Verilator AND VCS)

- `testbench.sv` — `module top`: clock gen, the 1→0→1 reset dance (needed
  so `negedge rst_l` fires in 2-state sim), `riscv_core_interface`
  instantiation, `delay_buffer` (DMEMORY_READ_DELAY-cycle memory latency),
  `main_memory`, cycle/mem-access counters, `$finish` on `halted`,
  watchdog `$finish` + TIMEOUT print past MAX_SIM_CYCLES (livelocked cores
  otherwise log forever; the register dump is still written, and the
  Makefile keys off the TIMEOUT line to fail `verify`), Verilator-only
  `+waves` FST dump block.
- `main_memory.sv` — behavioral memory: flat per-segment byte-lane arrays,
  loads `mem.{text,data,ktext,kdata}.bin` at time 0, word-wide load port
  (MEMORY_READ_WIDTH words per response), byte-masked stores (store_data
  must be reinterpreted via a word_t temp — bit-vs-byte-select bug bit
  once, see porting log).
- `register_file.sv` — architectural regfile module instantiated *inside
  each core* (instance `rf`): sync write/comb read, WAYS write ports
  (youngest way wins), optional FORWARD. Verification role: assembles
  `commit_pkt_t` per retire slot from its write-port inputs + the core's
  `commit_valid/commit_pc/commit_insn` inputs. Dump/trace machinery lives
  in the tb verifier, not here.
- `riscv_register_names.vh` — ISA/ABI register name table for pretty
  register dumps.
- `commit_verifier.sv` — consumes `commit_pkts` at top level: shadow
  architectural regfile (packets applied slot-serialized through a
  blocking temp so halt-edge commits are dump-visible), one full-state
  line per commit to `commit_trace.txt` under the `+commit_trace`
  plusarg (line = pc + x1..x31 hex + `#cycle=N time=T insn=X` comment,
  `time` being `$time` so a divergence maps straight onto a waveform),
  initial
  anchor line, and the end-of-run `simulation.reg`/`simulation.reg2`/
  stdout dump — **the dump comes from the shadow**, so `make verify`
  depends on faithful commit packets (shadow-vs-flops cross-check is a
  planned guard, see TODO-verify-trace.md). The dump fires on the halt
  edge; a `final` block (guarded by a `dumped` flag) covers a run that
  ends any other way, so a watchdog-killed run still leaves a
  `simulation.reg` to look at.

## tools/refsim — C instruction-level reference simulator

Vendored lab1a-otters simulator (class shell + student core), 4 real ISA
bugs fixed (JAL imm[11], R-type SLL operand swap, SB/SH masking, JALR
rd==rs1 — see porting log). RV32I only, no M — mul tests can't be oracled.
- `sim.c` — `process_instruction()`: decode+execute one instruction.
- `shell/shell.c` — interactive command loop (`go`, `step`, `rdump`,
  `trace`, `statetrace`, `verbose`, ...; commands come from stdin, so
  Makefile targets pipe scripts in). Dispatch: `process_long_command()`.
- `shell/commands.c` — command implementations; `run_simulator()` is the
  per-instruction step loop — both trace hooks live there (`statetrace`
  prints its full-state line right after `process_instruction()`;
  `command_statetrace()` opens the file + prints the anchor line).
- `shell/register_file.c` — refsim register array + the class write-event
  `trace` output; `shell/memory.c` + `include/*.h` — memory model, state
  struct (`sim.h`: `statetrace_mode`/`statetrace_fd` fields), ABI/ISA
  tables. Initial state (pc=USER_TEXT_START, SP, GP) is set at the end of
  `mem_load_program()` in `shell/memory.c` — must stay identical to
  `tb/register_file.sv`'s reset and the verifier's `reset_state()`.
- Builds on demand (`tools/refsim/Makefile`; needs `-fcommon`, readline
  from system or ~/miniforge3). `scripts/gen_ref_reg.sh` uses it to write
  `.reg` oracles next to tests.

## scripts, runtime, tests

- `scripts/gen_ref_reg.sh` — assemble a test + run refsim → `<test>.reg`
  oracle. `scripts/cache_sweep.py` — sweeps LTG_* cache geometry via
  PARAMS over tests/perf, parses PERF counters.
- `scripts/check_commit_trace.py` — the verify-trace comparator (RTL
  commit_trace.txt vs refsim statetrace; strips `#` comments, reports
  first divergent commit with pc/insn/regs/cycle; exit 1 on divergence).
  `scripts/view_commit_trace.py` — pretty-printer for either trace
  (per-commit register deltas; `--full` for whole-state dumps).
- `runtime/crt0.S` + `runtime/test_program.ld` — startup + linker script
  for C tests (entry `main`, sections → memory segments).
- `tests/asm` (class asm suite + oracles), `tests/c` (benchmarks; .reg
  oracles are class-toolchain-coupled — local GCC leaves different
  caller-saved residue, so local runs mismatch on junk registers),
  `tests/perf` (dhrystone etc.), `tests/custom`. `.O3.reg` variants are
  used when `OPT=-O3`. Per-test `.vh` files are the superseded class
  write-event trace oracles (verify-trace is green on inorder — deletion
  now unblocked; class scripts vendored in `~/stuff-from-ece447-folder/`,
  and the in-repo refsim's `trace` command can regenerate them).

## Verification flows

1. **End-state** (`make verify TEST=...`): run to halt, dump all 32
   registers (`simulation.reg`), sdiff vs `<test>.reg` oracle. A run the
   watchdog cuts off still dumps (state at the cutoff, for debugging) but
   is failed outright — verify greps the sim log for `TIMEOUT:` before
   diffing, so a livelock can never be reported as a pass.
2. **verify-trace** (`make verify-trace TEST=...`): per-commit full-state
   trace compare vs refsim — blessed on the in-order core (full asm suite
   + fault-injection check, 2026-07-11) and green on Lightning since the
   commit seam landed 2026-07-31 (all of `tests/asm` bar the mul tests,
   plus `tests/c/fibi.c` at 22.5k commits). See README "verify-trace" for
   the flow and the commit-packet contract, `docs/TODO-verify-trace.md`
   for design rationale + remaining items.
3. **Ground truth**: VCS on AFS is the semantics oracle. Expected
   failures as of 2026-07-31 (`make regress SIM=vcs`, full `tests/asm`):
   - **lightning** — 53/56: only `multest`, `dependMul`, `dependMulLow`
     fail (no M extension anywhere, refsim included), and they fail the
     same way under verify-trace. Loads, stores, `memtest2` and
     `syscalltest` all pass. `tests/c/fibi.c` passes; `tests/c/fibm.c`
     hangs (watchdog fires) — same behavior as the pre-port repo, not a
     regression.
   - **inorder** — everything except the same 3 mul tests.

## Lookup reference (fine-grained pointers found the hard way)

- In-order core stalls: `EMW_stall` (back half) + front-half stall truth
  table live right above the FORWARDING section in `riscv_core.sv`;
  `stall_W = EMW_stall`. Halt detection (`syscall_halt`/`halted`) is just
  below it. Commit seam (`commit_fire`, rf_commit_* wiring) sits between
  the writeback mux and STALL & FLUSH CONTROL.
- Lightning regfile write wiring (`rf_we` from SSC `reg_commits`) and the
  commit seam (`retire_slot_index`, `commit_seam`, `commit_pkt_padding`):
  bottom of `LightningCore.sv`, around the rf instantiation.
- Memory path, in dispatch order: address phase is an ordinary
  `Scheduler.sv` dispatch; the AGU-pass special case is in `DRIS.sv`'s
  writeback loop (`mem_addr_ready` branch); phase-2 selection is
  `MemoryScheduler.sv` `selection_logic` + `check_older_writes()`; the
  request reaches the cache through `d_request_drive` in
  `LightningCore.sv`; the response comes back at
  `writeback_pkts[EXEC_UNITS]` in the same file (`get_load_data()`); the
  store release is `store_ready`/`store_id` at the bottom of
  `SaneStateController.sv`.
- Byte/half handling lives in three places that must agree: store mask +
  store data in `MemoryScheduler.sv` (`get_store_mask`/`get_store_data`),
  load extension in `LightningCore.sv` (`get_load_data`), and
  `ldst_mode` decode in `riscv_decode.sv`.
- Old class dump/trace code (print_cpu_state, DEBUG_RFWRTRACE checker):
  deleted from `tb/register_file.sv` — recover with
  `git show 00c8ebb:tb/register_file.sv`.
- Makefile anchors: test binary vars (`TEST_NAME`/`TEST_BIN`/
  `TEST_OUTPUT_BIN`) ~line 141; `SIM_RUN_ARGS`/plusargs in the Simulate
  section; verify/regress in the Verify section; refsim/reftrace/
  verify-trace at the bottom. Sim runs with cwd = `$(OUTPUT)`, so
  commit_trace.txt etc. land there; refsim runs from repo root (reftrace
  passes an abspath).
- Verilator v5.048 quirk: lint.vlt `-file` waivers are ignored for some
  files (rtl/core, riscv_core_interface_inorder.sv) — use inline
  `// verilator lint_off` metacomments there.
- refsim: memory images are found by stripping the extension off the
  passed test path and appending `.text.bin` etc. (`init_cpu_state` →
  `mem_load_program`), which is why targets pass `$(TEST)` and depend on
  `$(TEST_BIN)`.

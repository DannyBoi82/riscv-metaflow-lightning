# Architecture & file map

What every file/module does and how they fit together, so a new session
doesn't have to re-explore the tree. Companion docs: `docs/porting-log.md`
(migration history + gotchas, **read before touching harness/build**),
`docs/TODO-verify-trace.md` (commit-trace design), `docs/TODO-IIU.md`,
`docs/new-repo.md` (original migration plan). Last updated: 2026-07-11.

## Big picture

Two RISC-V RV32I cores share one simulation harness and one build system:

- **Lightning** (`rtl/ooo/`, `CORE=lightning`, default) — the OoO
  DRIS/Metaflow-style core being built. No memory unit yet: loads/stores
  produce wrong results by design (D-side tied off), so only ALU/branch/jump
  asm tests pass.
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
           ├─ [lightning] LightningCore + 2x cache_controller2 (D-side idle)
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
  instantiated per fetch slot inside Lightning's IIU.
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

- `1DRIS_defs.sv` — `package DRIS_defs`: sizes derived from LTG_*
  (FETCH_WAYS=4, EXECUTE_WAYS, DRIS_NUM_ENTRIES, REG_FILE_WRITE_PORTS...)
  and every inter-unit packet/struct type (`dris_entry_t`,
  `dris_intake_pkt_t`, `issue_pkt_t`, `dris_writeback_pkt_t`,
  `reg_file_commit_pkt_t`, `dris_id_t` with wrap bit, lockers).
- `DRIS.sv` — the Deferred-scheduling Register Instruction Shelf: the
  central instruction/result buffer (unified ROB+RS+rename via "lockers").
  Intake from IIU, writeback ports from exec ways, entry array read by
  Scheduler/SSC. Drops writebacks whose entry was flushed.
- `InstructionIssueUnit.sv` — front end: drives the I-cache controller
  seam (request/cancel), receives FETCH_WORDS-wide fetch groups,
  per-slot `riscv_decode`, renames against DRIS lockers, emits
  prefix-contiguous intake groups (slot w gets DRIS ID fetch_ptr+w);
  contains `BranchShelf` (verifies branches/JALRs, fences retirement via
  oldest-branch id, triggers flush masks on mispredict, trains the BTB).
- `Scheduler.sv` — scans a window of DRIS entries from the retire pointer
  for ready instructions, reads operands (DRIS lockers or regfile read
  ports), issues up to EXEC_UNITS packets/cycle, marks entries dispatched.
- `LightningCore.sv` — top: wires IIU → DRIS → Scheduler → registered
  issue stage → per-way `ExecutionUnit` (riscv_alu + next-PC calc) →
  writeback/update bus → DRIS; SSC beside all of it; instantiates
  `register_file` (RF_WAYS = retire slots) written by the SSC's
  `reg_commits`. Exec stage is a real pipeline stage — never clear
  `issue_pkts_reg` on flush (older in-flight instructions must complete).
  `halted` = syscall entry reaching the retire head. Exposes a
  (currently all-invalid) `commit_pkts` port — TODO(SSC): populate once
  the SSC carries pc/insn and non-writing retirements.
- `SaneStateController.sv` — retirement: walks the DRIS from the retire
  pointer, retires completed entries in program order up to the branch
  fence, drives `reg_commits` to the regfile write ports (highest way =
  youngest wins on WAW), clears retired/flushed valid bits, releases
  stores (placeholder), raises `trap_valid` on syscall/illegal (= halt).

## rtl/mem — cache controllers, caches, core interfaces

- `riscv_core_interface.sv` — **lightning** wrapper: LightningCore +
  I-side `cache_controller2` (FETCH_WORDS-wide responses) + D-side
  `cache_controller2` tied off idle (no memory unit yet); arbitration mux
  between I/D controllers onto the single testbench memory port.
- `riscv_core_interface_inorder.sv` — **inorder** wrapper (the old class
  seam): riscv_core + two `cache_controller_ref` (instances `tony`/
  `tony_d`), same outer port list as the lightning wrapper.
- `cache_controller_ref.sv` — refactored class write-through controller
  (1-word responses, 2-deep response FIFO, live request acceptance).
- `cache_controller2.sv` — writeback / write-allocate controller, same
  seam and timing contract as ref; used by Lightning (I-side widened to
  FETCH_WORDS).
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
  otherwise log forever), Verilator-only `+waves` FST dump block.
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
  plusarg (line = pc + x1..x31 hex + `#cycle=N insn=X` comment), initial
  anchor line, and the end-of-run `simulation.reg`/`simulation.reg2`/
  stdout dump — **the dump comes from the shadow**, so `make verify`
  depends on faithful commit packets (shadow-vs-flops cross-check is a
  planned guard, see TODO-verify-trace.md).

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
   registers (`simulation.reg`), sdiff vs `<test>.reg` oracle.
2. **verify-trace** (`make verify-trace TEST=... CORE=inorder`):
   per-commit full-state trace compare vs refsim — blessed on the
   in-order core (full asm suite + fault-injection check, 2026-07-11).
   Lightning emits write-only packets (end-state dump works;
   verify-trace blocked on SSC pc/insn + non-writing retirements). See
   README "verify-trace" for the flow and the commit-packet contract,
   `docs/TODO-verify-trace.md` for design rationale + remaining items.
3. **Ground truth**: VCS on AFS is the semantics oracle; Verilator is the
   daily driver. Expected failures (lightning): all load/store/mul asm
   tests, all tests/c and tests/perf, **and syscalltest** (Lightning
   halts on *any* syscall reaching the retire head, so the non-halting
   ecall test dies early — pre-existing, verified at commit 00c8ebb).
   In-order core: everything passes except the 3 mul tests (no M
   extension anywhere, refsim included).

## Lookup reference (fine-grained pointers found the hard way)

- In-order core stalls: `EMW_stall` (back half) + front-half stall truth
  table live right above the FORWARDING section in `riscv_core.sv`;
  `stall_W = EMW_stall`. Halt detection (`syscall_halt`/`halted`) is just
  below it. Commit seam (`commit_fire`, rf_commit_* wiring) sits between
  the writeback mux and STALL & FLUSH CONTROL.
- Lightning regfile write wiring (`rf_we` from SSC `reg_commits`) +
  commit-packet tie-off: bottom of `LightningCore.sv` (rf instantiation).
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

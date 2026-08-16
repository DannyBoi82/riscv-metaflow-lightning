# Verilator porting log (2026-07-06, updated 2026-07-07)

Status of the metaflow-lightning → lightning migration. The repo scaffold,
centralized config, and Makefile are done. **The Verilator segfault is
root-caused and worked around** (GCC 13.3 -O3 miscompiles Verilator itself;
see "Resolved" below) — `make verify TEST=tests/asm/additest.S` passes.

## Done

- **Plan amended** (`docs/new-repo.md` addendum): centralized control files +
  local-toolchain custom test compilation, agreed before execution.
- **Scaffold**: full new tree at `~/lightning` (git init'd, nothing committed
  yet). Layout: `rtl/{include,core,ooo,mem}`, `tb/`, `runtime/`, `tests/{asm,c,
  perf,custom}`, `scripts/`, `synth/`, `docs/`. Pruned migration done:
  - Dead 447src RTL audited by instantiation and **not copied**: `cache.sv`,
    `cache_controller.sv`, `riscv_core_timing.sv` (nothing instantiates them).
  - `fifo.sv`, `sram_simulation.sv`, `sram_synthesis.sv` are **live**
    (cache_controller2/cache3/BTB use them) → `rtl/mem/`.
  - Tests merged: 447inputs+447inputs2 → `tests/asm/` (no name collisions),
    benchmarks → `tests/c/`, benchmarksO3 dumps → `tests/c/<name>.O3.reg`,
    perf_benchmarks → `tests/perf/`, custom-tests → `tests/custom/`.
    Sources + `.reg`/`.vh` oracles only; build artifacts excluded.
  - `synth/dc_synth.tcl` is a **broken symlink into AFS** even in the old
    repo — preserved as a symlink; synth is AFS-host-only.
- **Centralized control**:
  - `config.mk` — build knobs: SIM=verilator|vcs, RISCV_PREFIX (auto-detect),
    OPT, PARAMS (+define+ passthrough), SEED (X-shakeout), output dirs.
  - `rtl/include/config.vh` — every hardware knob as `ifndef`-guarded `LTG_*`
    macros (cache geometry, DRIS sizing, ways, branch shelf, scheduler window,
    memory latencies, clock). `parameters.vh`, `riscv_uarch.vh` (LAB_18447
    conditionals removed), and `1DRIS_defs.sv` now derive from these.
    Per-run override works: `make ... PARAMS='+define+LTG_DRIS_ENTRIES=32'`.
- **Makefile** (rewritten, single file): verify/regress/sim/waves/build/lint/
  assemble/toolchain/refsim/refdump/synth targets; SIM switch; flag-stamp
  auto-rebuild when PARAMS/SEED/WAVES/TRACE change; regress auto-discovers
  every test with a `.reg` oracle; `.O3.reg` oracle selected when OPT=-O3.
  VCS flags = old ones minus `-fgp` and `+define+LAB_18447`.
- **Toolchain**: auto-detect works. Local `riscv32-unknown-linux-gnu-` GCC 16.1
  (`~/.local/riscv-gnu-toolchain/bin`) builds both `.S` and `.c` (libgcc
  rv32i/ilp32 OK) — verified by compiling additest.S and fibm.c to ELF.
- **Portability fixes applied** (all keep VCS semantics):
  - `tb/testbench.sv`: LAB generate removed (riscv_core_interface hardcoded);
    reset now `1 → #1 → 0` so `negedge rst_l` fires in 2-state sim (VCS got
    it from the X→0 edge at t=0; Verilator never would have reset anything).
    Verilator-only `$dumpfile/$dumpvars` block behind `+waves` plusarg.
  - `tb/main_memory.sv`: rewritten — flat storage arrays instead of struct
    array, file loading in an initial block, no `let`, no ref-arg functions,
    SEGMENTS from package instead of parameter (string-in-struct parameter
    is unsupported by Verilator).
  - `rtl/core/0internal_defines_pkg.sv`: enum don't-cares sized
    (`IMM_DC = 3'bx` etc.; unsized `'bx` in narrow enums is an IEEE violation
    VCS tolerated).
  - `rtl/mem/fifo.sv`: `deq_data` computation split into its own always_comb
    reading only registered state → breaks the false combinational loop
    (intake_stall → peek_only → deq_data → intake_stall). Behavior unchanged.
  - `rtl/ooo/InstructionIssueUnit.sv` (BranchShelf): defaults added for
    `alloc_write_slot` / `ok_retire_safe` → kills a real inferred latch.

## Resolved 2026-07-07: Verilator SIGSEGV = GCC 13.3 -O3 miscompile of Verilator

gdb backtrace (conda env `gdb`, since no sudo for apt) on the optimized
binary pinned the crash:

    AstNodeDType::skipRefIterp() <- AstNodeDType::isLiteralType()
    <- EmitCHeader::emitAll() <- V3EmitC::emitcHeaders()

i.e. during C++ header emission — **not** in the warning code. The
"crash site follows the last warning" pattern from 07-06 was a red
herring (the `-node:` debug line just showed whatever was processed
last before emission). Suppressing warnings (`-Wno-lint -Wno-style`,
per-warning `-Wno-*`) does not help.

Evidence it's an optimizer-level miscompile (or UB only manifest at -O3):

- `verilator_bin_dbg` (same source, -O0 + `_GLIBCXX_DEBUG`): **works**,
  verilates the full design in ~3 s CPU and the result simulates correctly.
- `verilator_bin` from the v5.048 release tag, default build (-O3,
  g++ 13.3.0 Ubuntu 24.04): **same segfault**.
- Same v5.048 source rebuilt with `-O1` (sed `-O3`→`-O1` in
  `src/Makefile_obj`, rebuild `src/obj_opt`): **works**.

Resolution: Verilator v5.048 (release tag) built at -O1 with prefix
`~/.local`, from the source tree at `~/verilator`. `config.mk` gained a
`VERILATOR ?=` knob (Makefile changed to `?=`) pointing at the working
binary. Upstream repro for a bug report would need the full design; parked.

### Verilator runtime bugs found on the way (both present on master)

1. **`%x`/`%h` loses zero-padding after an earlier `%-Ns` in the same
   format string**: `_vl_vsformat` (include/verilated.cpp ~line 1004)
   resets `widthSet` but not `left` when a new `%` begins, so the
   left-justify flag leaks and `%x` takes the minimal-width branch.
   Worked around in `print_register` by `$sformat`ing the hex into a
   string first. Worth reporting upstream (verilator/verilator).
2. `$fdisplay(fd, {N{"-"}})` prints the replication as a decimal number
   (VCS treats it as a format string → dashes). Fixed by an explicit
   `"%s"` format. Arguably our bug, not theirs.

### Other portability fixes for first passing verify

- Makefile `.S` link rule passed `$^` (source **and** linker script) while
  `RISCV_LDFLAGS` also passes `-Wl,-T<script>`; binutils 2.44 (GCC 16
  toolchain) errors with "linker script appears multiple times". Now `$<`.
- `register_file.sv` dump: `0x%08x` → per-IEEE a leading 0 in the width is
  "minimal width", so Verilator printed `0x0`; VCS reads it C-style. Replaced
  with pre-formatted `$sformat("0x%x", ...)` string (also dodges runtime bug
  1 above); `%08x` in riscv_core.sv $displays → `%x` (cosmetic only).
- Oracle `.reg` comparison: sim output has trailing spaces the refsim-made
  oracles lack — already ignored via sdiff `--ignore-all-space`.

## Historical (2026-07-06): Verilator internal fault (SIGSEGV, exit 139)

`verilator --binary --timing` on the full design segfaults. Environment:
Verilator 5.049 devel (v5.048-243-g0ee25038a) at /usr/local/bin, WSL2.
Not scale (crashes with LTG_DRIS_ENTRIES=8), not memory (62MB RSS), not
stack limit (ulimit -s unlimited honored).

Crash site moves as constructs are fixed — each crash so far sat next to a
lint-warning-generating construct:

1. after V3Delayed/V3SchedVirtIface, node = `iiu.intake_stall` (the
   UNOPTFLAT circular signal) → fixed by the fifo.sv split above.
2. V3Active, node = BranchShelf `always_comb` at InstructionIssueUnit.sv:746
   (the LATCH warning) → fixed by the defaults above.
3. **current**: V3Case (`caseAll`), node = `case(stype_funct3)` at
   `rtl/core/riscv_decode.sv:374` in instance
   `top.RISCV_Core_interface.core_inst.iiu.slot_decode[0].dec` — right where
   a CASEINCOMPLETE warning is being issued.

**Hypothesis**: the crash is in/near warning emission on this devel build
(possibly a bug in its warning-context printing), so it may keep hopping
between warned constructs. Untested ideas, in order:

1. `gdb` backtrace of `verilator_bin` (user will install gdb).
2. Quick test: add `-Wno-CASEINCOMPLETE -Wno-LATCH -Wno-UNOPTFLAT` (or bare
   `--quiet` / drop `-Wall`) — if crashes stop, it's the warning path, and we
   can pin a released Verilator instead of the devel build.
3. Fix riscv_decode.sv:374 (add `default:`) like the others and see if the
   crash moves again — also just correct RTL.
4. If the devel build is the problem: install a released Verilator (5.041+ or
   distro package with --timing support), or rebuild from a release tag.

Debug invocation that reproduces + logs (last `-node:` line before EXIT=139
identifies the crash site):

    ulimit -s unlimited
    verilator_bin --binary --timing -j 1 --top-module top -Wno-fatal \
      --debug --dumpi-tree 0 --dumpi-graph 0 -Mdir <scratch>/obj_dbg \
      +define+SIMULATION_18447 +incdir+rtl +incdir+rtl/core \
      +incdir+rtl/include +incdir+rtl/mem +incdir+rtl/ooo +incdir+tb \
      <sources in rtl/core rtl/ooo rtl/mem tb order, sorted per dir>

## 2026-07-07 (later): regression run + harness blessed via lab4b core

### Lightning regression results (Verilator)

`make regress` on the OoO core: all ALU/branch/word-independent asm tests
pass. **16 asm tests fail (all load/store/mul-dependent) plus every C/perf
test — these are NOT porting regressions.** `rtl/mem/riscv_core_interface.sv`
ties the entire D-side off idle ("LightningCore has no memory unit yet",
verbatim from metaflow-lightning), so loads retire with the AGU effective
address as their result (e.g. lw.S: x13 = 0x10000000, the address) and every
program needing memory (all of tests/c, tests/perf) can never pass. Same
behavior would occur under VCS. C tests also never halt → regress grinds a
long time per C test; consider TESTS='tests/asm/*.S' until a memory unit
exists.

### Harness validation rig: ~/lab4b-vl (lightning harness + lab4b core)

`~/lab4b-cool_otters` @ f1dc319 is a known-good in-order core (passes full
class autograde under VCS). Built `~/lab4b-vl`: lightning's Makefile,
config.mk, tb/ (ported testbench/main_memory/register_file), rtl/include
(LTG config; lab4b's 4b values match config.vh defaults exactly), lightning's
fixed fifo.sv + 447src cache/cache_controller/sram, lab4b src core, tests
symlinked to lightning's. Only source change needed: sized enum don't-cares
in lab4b's internal_defines.vh (same IEEE fix as lightning's pkg).

Result: **entire asm suite passes under Verilator** after one real harness
bug was found and fixed (below). This blesses the testbench rewrite, reset
scheme, main_memory rewrite, delay buffer, register dump, and oracle compare
end-to-end. (C-test + multest/memtest status: see regression note below.)

### mul tests: -march was wrong, and neither core implements M

multest/dependMul/dependMulLow "failures" in BOTH repos were an assemble
error: binutils 2.44 rejects `mul` at -march=rv32i ("extension `m' or
`zmmul' required"), verify correctly failed, and the stale simulation.reg
copied into failed_sims/ was the *previous* test's dump (misleading; the
real evidence is assemble.log). Fixed: `RISCV_ARCH ?= rv32im` knob in
config.mk, Makefile uses `-march=$(RISCV_ARCH)`. The tests now assemble and
run — and fail honestly at runtime, because neither the lab4b core (RV32I,
no MUL decode, no trap-emulation in crt0) nor LightningCore implements M.
They join the "needs future core work" bucket alongside the memory unit;
oracles (.reg from refsim) are already correct for whenever M lands.

### tests/c + tests/perf oracles are class-toolchain-coupled

After the main_memory fix, every C-test mismatch on the lab4b rig is
register *residue*, not results: fibm differs only in x15 (a5 =
0x1000003c, a dangling .data pointer); quicksort differs in a3..a7 with the
same values shuffled across registers (allocation order); result registers
match the oracle. Cause: the committed .reg oracles were generated from
class-toolchain compilations; local GCC 16.1 codegen leaves different junk
in caller-saved regs at the final ecall. Perf tests additionally diverge in
behavior (dhrystone's ecall-based timing hooks fire at different points).
Consequences:
- C/perf verify is only meaningful with class-toolchain binaries (AFS), OR
  after regenerating oracles for the local toolchain. The lab4b-vl rig is a
  legitimate local oracle generator: the core is VCS-blessed and .reg files
  contain only architectural register state (no cycle counts).
- Not a harness bug; asm oracles are unaffected (assembly is deterministic).

### Harness bug found by the rig: byte-lane store corruption in main_memory

`tb/main_memory.sv` (my rewrite): `seg_mem[s][offset][b] <= store_data[i][b]`
— `store_data[i]` is a flat 32-bit vector, so `[b]` was a *bit*-select,
zero-extended into byte lane b. The original passed store_data through a
`word_t`-typed function argument, implicitly reinterpreting it as bytes; the
inlined rewrite lost that. Effect: any store reaching main_memory wrote
garbage (bit b) into enabled lanes. Masked because lightning's D-side is tied
off and word stores are absorbed by the write-back cache — but lab4b's
controller sends sub-word stores straight to memory: sb/sh/memtest1/2 and all
C tests failed with exactly this signature (lw readback 0x00000000). Fixed
with a `word_t` temp; sb.S green immediately. **This would have corrupted VCS
runs too** once anything wrote through to memory — rig caught it before the
AFS parity run.

### Runaway-simulation guards (found the hard way)

An orphaned `bubblesort` sim (livelocked core: no memory unit → never
reaches its ecall) ran ~40 min and wrote a **20 GB** simulation.log
(unknown-opcode $display per cycle). Two guards added:
- `tb/testbench.sv` watchdog: `$finish` + TIMEOUT message past
  `LTG_MAX_SIM_CYCLES` (config.vh, default 20M ≈ 3x the largest legit test's
  7.2M cycles; plumbed through RISCV_UArch::MAX_SIM_CYCLES). Identical
  behavior under VCS. Verified: dependMul (livelocked: mul never retires)
  ends at the limit with no register dump → verify fails as intended.
- Makefile `rm -f $(SIM_REGDUMP)` before each sim run — a watchdog-killed
  (or crashed) run must fail verify, not inherit the previous test's dump.
  (Stale-dump confusion already bit once: failed_sims/multest contained the
  previous test's register dump after multest failed to *assemble*.)

### Lint pass done: `make lint` is clean

- `lint.vlt` (wired into the lint target via `LINT_WAIVERS ?= lint.vlt`):
  global rule-offs for style categories (UNUSED*, IMPORTSTAR, VARHIDDEN,
  DECLFILENAME, EOFNEWLINE, PINCONNECTEMPTY, WIDTHEXPAND/TRUNC) + documented
  targeted waivers (tb INITIALDLY/SYNCASYNCNET/BLKSEQ, SSC UNOPTFLAT
  priority chain).
- v5.048 quirk: `-file`/`-match` waivers were ignored for PINMISSING/
  CASEWITHX/CASEINCOMPLETE raised under rtl/core (global rule-offs worked);
  those three sites use inline `// verilator lint_off` metacomments instead.
- Real fix, not waiver: SaneStateController retire chain's genvar-constant
  `if` hoisted to a generate-if, killing a SELRANGE on the elaborated-dead
  `[k-1]` branch of instance k=0. Same logic, additest re-verified green.

## 2026-07-07 (later still): in-repo C reference simulator (tools/refsim)

Rebuilt the CMU verification chain locally: C ILS generates reference
dumps → RTL is diffed against them. Vendored the lab1a-otters simulator
(class shell + student core) into `tools/refsim/`; `REFSIM_EXECUTABLE`
in config.mk now defaults to the in-repo binary (built on demand by the
`refsim`/`refdump` targets and `scripts/gen_ref_reg.sh`); the AFS class
binary remains available as an override.

### lab1a-otters: found and fixed 4 real ISA bugs (the "private tests" fail)

The clone's default branch is the starter; the real sim is
`daniel-branch` @ "The one that passes the autograder". Reproduced the
public-pass/private-fail split locally: all 50 public tests green, but
`benchmarks/mixed.c` computed r=0 vs oracle 0x2f3f1441 (result registers
x2/x3 per crt0; verified ground truth by compiling mixed.c natively —
exit code 0x41 = low byte of the oracle value). Bugs, all in cases the
public suite never exercises (fixed in lab1a-otters commit e4f6e61 and
in the vendored copy):

1. **JAL imm[11] read from instr[19] instead of instr[20]** — wrong
   target whenever displacement bit 11 ≠ bit 19. First `jal main` of
   mixed (disp 0x8f4) jumped to 0x4000f4 instead of 0x4008f4; every
   test with |disp| < 2 KB has imm[11]==imm[19]==sign, so it always
   passed the small programs. Also sign-extension was `<<12>>12`
   (kills bit 20); now `<<11>>11`. This is what the "bugged jal"
   commits were circling.
2. **R-type SLL operands swapped** (`rs2 << rs1`) — the public list has
   slli/srl/sra but **no sll.S**, so it was never caught.
3. **SB/SH merged rs2 unmasked** — upper register bits leaked into
   neighboring byte lanes (same species as the main_memory byte-lane
   bug the rig caught).
4. **JALR wrote rd before reading rs1** — broken for `jalr` with
   rd == rs1.

Also masked all register-shift amounts to rs2[4:0] per ISA.

### Validation of the vendored sim (this is what blesses refdump)

- lab1a rig: 50/50 public tests; all benchmarks + benchmarksO3 that
  link locally produce oracle-matching x2/x3 (full-dump diffs are
  class-toolchain caller-saved residue, same taxonomy as tests/c).
- lightning rig: `make refdump` dump for **53/53 non-mul tests/asm and
  3/3 tests/custom oracles matches the committed class-refsim .reg
  byte-for-byte**. Expected failures: multest/dependMul/dependMulLow
  (sim is RV32I; no M — same bucket as the cores).
- Same memory map (STACK_END 0x7ff00000, USER_DATA 0x10000000) and
  runtime (crt0.S/test_program.ld identical to lightning's modulo
  comments); dump format identical to the class refsim's.

### Local-toolchain gaps surfaced (not sim bugs, pre-existing)

- `benchmarks/mmm*` don't link: the riscv32-unknown-linux-gnu GCC 16.1
  toolchain is **non-multilib** and its C-compiled libgcc objects
  (`muldi3.o` etc.) are tagged rv32imafdc/double-float → anything
  needing `__muldi3` (long long) or soft-float intrinsics fails at
  rv32i/ilp32 link. (`__mulsi3`-only tests like fibm link fine — the
  asm-built lib1funcs objects carry compatible tags.)
- benchmarksO3/bumergesort: GCC 16 at -O3 emits a `memcpy` libcall;
  -nostdlib provides none.

### Notes for future use

- The C sim is ~instant per test vs minutes under Verilator — use
  `scripts/gen_ref_reg.sh` for oracle generation for new asm tests and
  for the planned local-toolchain tests/c oracle regeneration (do that
  only after the VCS parity run so oracle churn doesn't muddy it).
- The vendored shell also has the `trace` command (`sim.h` trace_fd) —
  the backend `make verify-trace` used in class; not wired into the
  lightning Makefile yet.
- tools/refsim builds against system readline, falling back to
  ~/miniforge3 (this box has no libreadline-dev; needs `-fcommon` —
  commands.h defines SIGINT_RECEIVED without extern).

## Remaining after unblock

- ~~Smoke + regress~~ **done 07-07**: additest green; asm suite passing except
  the expected no-memory-unit/no-M failures (taxonomy above).
- ~~register_file.sv hierarchical refs~~ **fine under Verilator**: the
  `top.mem_access` dump works (register dumps show "Mem Accesses: N").
- ~~Lint cleanup~~ **done 07-07**: `make lint` is zero-warning via lint.vlt +
  three inline waivers + the SSC SELRANGE fix.
- ~~scripts~~ **done 07-07**: cache_sweep.py now drives PARAMS/LTG_* (no file
  rewriting, `make sim` + `+define+PERF`, tests/perf paths); gen_ref_reg.sh
  paths fixed (`make assemble`, runtime/ docs, REFSIM env override).
- ~~README + CLAUDE.md + .gitignore~~ **done 07-07**; initial git commit
  pending final regression pass.
- ~~VCS parity run (`make regress SIM=vcs`)~~ **done 07-11 on the lab
  machine** (see the 07-11 section below): asm suite + verify-trace green
  with CORE=inorder after three VCS-only fixes; C/perf leftovers are
  toolchain residue + never-committed perf headers, not simulator deltas.
- Future core work surfaced by the regression taxonomy: memory unit
  (D-side is tied off in riscv_core_interface.sv), M extension (mul tests
  now assemble and wait for hardware), C-test oracle regeneration for the
  local toolchain (the ~/lab4b-vl rig or — much faster — tools/refsim
  can produce them).
- `make verify-trace` redesign (commit-state trace compare, replaces the
  event-based class flow that choked on nop bubbles) — design + work
  items in docs/TODO-verify-trace.md.

## 2026-07-11: VCS parity run (lab machine, VCS T-2022.06)

First time the migrated harness met real VCS (previous work was WSL,
Verilator-only). `make verify-trace CORE=inorder SIM=vcs` and
`make regress TESTS='tests/asm/*.S' CORE=inorder SIM=vcs` are now green
(the 3 mul tests fail as expected — no M hardware). Full
`make regress CORE=inorder SIM=vcs`: same 3 mul failures, plus 6
machine-environment failures that are not simulator deltas —
dhrystone/kosarajus/spmv **don't compile** (their `#include`d headers
`dhrystone.h`/`kosarajus_graph.h`/`spmv_matrix.h` were never committed;
they must have sat untracked on the WSL box where full regress was
green), and fft/mmmIntRV32I/mmmFpRV32I fail only in caller-saved a*/t*
residue (the documented class-toolchain-coupled oracle issue — this
box's RISC-V GCC differs from the one that matched). Three latent bugs,
all masked by Verilator and exposed by VCS:

### Compilation-unit imports (build break)

`rtl/core/lib.sv` and `rtl/core/riscv_core.sv` used `internal_defines_pkg`
types (`imm_mode_t`, `ALU_*`, ...) without importing the package — they
`include`d `internal_defines.vh`, which is a commented-out stub (the real
definitions moved to `rtl/core/0internal_defines_pkg.sv` long ago).
Verilator treats **all sources as one compilation unit**, so the file-scope
`import internal_defines_pkg::*;` in other files (riscv_decode.sv etc.)
leaked into $unit and resolved the types. VCS compiles **one compilation
unit per file** (and even `-mfcu` is order-sensitive), so it errored with
"Identifier not declared". Fix: per-file `import internal_defines_pkg::*;`
in both files. Rule going forward: every file that uses package types
imports the package itself; never rely on another file's import.

### main_memory seg_mem: always_ff vs initial-block init (Error-[ICPD])

VCS rejects an `always_ff` variable written by any other process;
`seg_mem` is initialized (0xDE poison + file load) in an `initial` block.
Verilator doesn't enforce single-driver on always_ff. Fix: the store
process is a plain `always @(posedge clk)` with a comment.

### delay_buffer reset never fires → X-poisoned `halted` duplicates a commit

The testbench reset waveform is `1 → (t=1) 0 → (t=HALF_PERIOD) 1` and the
clock starts at 1 with posedges at t=0, 2H, 4H... — so **no clock posedge
ever samples rst_l low**, and any synchronous-reset-only state is never
reset. All design flops use async `negedge rst_l` (fires at t=1) and were
fine; the tb `delay_buffer` (memory-latency model) used a synchronous
reset. Under 2-state Verilator its `data_q` starts at 0 = RESET_VAL, so
nothing was ever visibly wrong. Under VCS it shipped X for the first
DELAY cycles — including the `mem_excpt` bit, so `exception_halt` →
`halted` was X for cycles 1..8. `pc_F1`'s enable (`~halted && ...`)
evaluated X → PC register froze, while the F1→F2 latch (not gated by
halted) marked F2 valid anyway: pc 0x400000 entered the pipe twice and
**the first instruction committed twice**. `make verify` still passed
(the duplicated addi is architecturally idempotent) — it was
`verify-trace` that caught it, at exactly commit #2, which is the tool
working as designed. Fix: delay_buffer (and the tb `mem_access` counter)
now use async resets like the rest of the design; zero behavior change
under Verilator. Rule going forward: no synchronous-reset-only state
anywhere — the reset window contains no clock edge by design.

### Environment notes (lab machine)

- VCS: T-2022.06 via AFS (`/afs/ece.cmu.edu/support/synopsys/...`).
- No working Verilator here yet: the config.mk-pinned
  `~/.local/bin/verilator` (custom v5.048 -O1 build) is on the old WSL
  box, and conda's verilator 5.046 dies with "Verilator internal fault"
  on this design (same species as the documented GCC-miscompile
  segfaults — needs a -O1 rebuild if Verilator is wanted here).

## 2026-07-31: verify-trace on CORE=lightning (the commit seam)

Lightning was still emitting the port-era stand-in commit packets —
`register_file`'s `commit_valid` tied to its own write enables, pc/insn
0 — which is all the *old* repo's verification ever needed (an
end-of-run register dump), but not what this harness consumes: the
commit_verifier's shadow regfile *is* the dump, and verify-trace needs
one packet per **retired instruction**, writing or not, with its PC.

Fix, entirely inside `LightningCore.sv` (the SSC did not have to
change): slot s of the commit array is the DRIS entry at
`retire_ptr + s` — the inverse of the SSC's `retire_vector_scatter` —
so `commit_valid[s] = retire_vector[retire_slot_index(s)]` and
`commit_pc[s]` is that entry's pc. The regfile still assembles the
packets from write port s, which belongs to the same retire slot
(`reg_commits[s]`), so the two halves stay aligned and x0/non-writing
retirements come out as `rd_addr = 0` for free.

Two things that are easy to get wrong:

- **The halting ecall never retires.** The SSC traps on it at the retire
  head instead — that is what raises `halted` — so no retire slot ever
  reports it, while the refsim executes it and prints a final trace line.
  `halted` therefore forces one last packet at slot 0 (pc = `trap_pc`,
  no register write), the same thing the in-order core does with
  `valid_W & (~stall_W | halted)`. Slot 0 is guaranteed free: nothing
  retires in a cycle whose head entry has trapped.
- **`insn` is reported only in `DEBUG builds**, since that is when the
  DRIS entry carries an instruction word (see the DEBUG section below).
  Nothing diffs against the field — it lives inside the `#` comment
  `check_commit_trace.py` strips — so a plain build just gives a less
  chatty divergence report; pc identifies the instruction either way.

Result under `SIM=vcs`: `make verify-trace` green on all of `tests/asm`
except the 3 mul tests (which no core and not the refsim implement), and
on `tests/c/fibi.c` — 22507 commits matching the reference. `make regress
TESTS='tests/asm/*.S'` unchanged (same 3 failures); VCS compile warning
count unchanged at 49. Verilator lint was *not* run: there is still no
usable verilator on this lab machine (see Environment notes above).

Doc drift found while updating: `memtest2` had been fixed by the last
commit before this one but was still listed as an expected failure in
CLAUDE.md/architecture.md, and README still described Lightning as having
no memory unit. Both corrected.

### `+define+DEBUG` had rotted (fixed the same day)

The OoO packets/entries carry `ifdef DEBUG pc/instruction fields for
waveform readability. Nobody had built with `DEBUG` in a long time and it
no longer compiled — the guarded code referenced members that don't exist:

- `DRIS.sv` writeback: `dris_entries[...].debug_pc <=
  writeback_pkts[i].debug_pc_dris_W` — neither member exists. Deleted the
  whole debug writeback block rather than adding the fields: intake
  already stores pc and the instruction word, and copying them back from
  the writeback packet would *clear* them for loads, whose data writeback
  is driven straight from the cache response (`writeback_pkts[EXEC_UNITS]`
  in LightningCore) and carries no instruction word.
- `SaneStateController.sv`: `entries_checked[i].instr` — the member is
  `debug_instr`.

With those two fixed, `PARAMS='+define+DEBUG'` builds and runs identically
to a normal build: same `make regress` result over `tests/asm` (the 3 mul
tests), `make verify-trace` green on the same 53 + `tests/c/fibi.c`, on
`CORE=lightning` and `CORE=inorder`, and the same 49 VCS compile warnings.
The payoff for verify-trace: a DEBUG build fills in the commit packet's
`insn`, so the divergence report names the instruction, not just its pc.

Guard against re-rot: DEBUG is not in any regress path, so it can only
break silently. If you touch the OoO packet structs, do one
`make build SIM=vcs PARAMS='+define+DEBUG'`.

## 2026-07-31 (later): `make verify` on a run that never halts

The register dump was only ever written on the halt edge
(`commit_verifier.sv`, and `register_file.sv` before it — the pre-port repo
did the same). A run the watchdog kills therefore produced **no**
`simulation.reg` at all, and `verify` could only report

```
diff: output/vcs/simulation.reg: No such file or directory
Incorrect! The simulator register dump does not match the reference.
```

which says nothing about what the core actually did. That is the failure
mode on every livelock: the 3 mul tests, `tests/c/fibm.c`, and any core bug
that stalls retirement. (verify-trace never had the problem — its checker
reads a truncated trace and reports "the RTL trace ended early".)

Fix, in three parts:

- `commit_verifier.sv`: a `final` block dumps `shadow` if the halt-edge dump
  never ran, gated on a `dumped` flag. So every run ends with a
  `simulation.reg`, and on a timeout it is the architectural state at the
  cutoff — the thing you want to diff against the oracle to see how far the
  program got.
- `tb/testbench.sv`: watchdog comment updated (it used to assert that no
  dump is produced, which was the mechanism that failed verify).
- `Makefile`: `verify` greps the sim log for `^TIMEOUT:` before diffing and
  fails outright if it matches. **This is load-bearing** — without it, a
  core that computes everything and then livelocks before its ecall retires
  would dump correct-looking registers and be reported as a pass. The
  missing file used to provide that guarantee; the grep replaces it.

Two VCS gotchas hit while writing the flag, both "multiple drivers" errors
on a plain `logic`:

- Calling `dump_registers()` from both the `always_ff` and the `final` block
  makes VCS count each call site as a driver of anything the function
  assigns. Hence the flag is set at the call site, not inside the function.
- `logic dumped = 1'b0;` — VCS counts the declaration initializer as a
  second driver alongside the `always_ff`. Cleared in the reset branch
  instead. (`int trace_fd = 0;` gets away with it because its other
  assignment is in an `initial` block.)

Verified under VCS, `CORE=lightning` and `CORE=inorder`: `make regress
TESTS='tests/asm/*.S'` unchanged at 3 failures (the mul tests, now failing
with the timeout message and a dump to inspect), `make verify` still green
on `tests/asm` + `tests/c/fibi.c` incl. `PARAMS='+define+DEBUG'`, exactly
one register dump per run (no double dump on normal halts), and
`make verify-trace` unaffected.

## 2026-08-07: perf benchmarks — `RISCV_ARCH=rv32im` was leaking into C

`tests/perf/*` produced wrong results on **both** cores, including the
known-good `CORE=inorder` rig, and on old commits as well as HEAD. Not a
core bug and not the missing headers: the `RISCV_ARCH ?= rv32im` knob added
on 2026-07-07 so binutils would encode `mul` in the three class **asm**
tests was wired into the single shared `RISCV_CFLAGS`, so it applied to C
compilation too. GCC given rv32im emits MUL/DIV for ordinary C, and nothing
in this repo decodes M (`FUNCT7_MULDIV` in `rtl/include/riscv_isa.vh` is
declared and never used) — so the benchmarks executed garbage.

Evidence, against the pre-OoO commit of the old repo that is known to run
these correctly (`metaflow-lightning` @ da293d0, `-march=rv32i`):

- `*.c`, `*.h`, `*.data.bin`, and the `.reg` oracles were already
  byte-identical between the repos — only `*.text.bin` differed.
- M-extension instruction counts in the new repo's disassembly: dhrystone 6,
  fft 40, spmv 2, kosarajus 0 — and kosarajus was the one benchmark whose
  `.text.bin` already matched. That is the whole diagnosis in one line.
- Rebuilding with `-march=rv32i` reproduces all 16 old `.{text,data,ktext,
  kdata}.bin` files byte-for-byte.

Fix: `-march` is now per source language, since the two have opposite needs.

- `config.mk`: `RISCV_ARCH ?= rv32im` (`.S` only — lets the assembler encode
  the mul tests) and a new `RISCV_ARCH_C ?= rv32i` (`.c`).
- `Makefile`: `-march` moved out of the shared `RISCV_CFLAGS` into
  `RISCV_C_ONLY_FLAGS` / `RISCV_AS_ONLY_FLAGS`, one per ELF rule.

Also fixed here: the `.c` ELF rule had no header prerequisites, so dropping
`tests/perf/*.h` into place did not invalidate the stale `.elf`/`.bin` and
`make assemble` silently did nothing — which is what made this look like a
core misbehavior rather than a build one. The rule now depends on
`$(TEST_HEADERS)` = the `.h` files sitting next to the test.

Verified on VCS, `CORE=inorder`: dhrystone, kosarajus, spmv, fft all report
"Correct!" against the committed oracles, with no `RISCV_ARCH` override.

Two corrections to earlier entries in this log:

- "tests/c + tests/perf oracles are class-toolchain-coupled" (2026-07-07)
  overstated the problem for perf. On this AFS host the detected toolchain
  reproduces the class binaries exactly, so all four perf oracles match with
  zero residue diff. The residue caveat still holds for local non-AFS GCC.
- `tests/c/mmmIntRV32I` and `tests/c/mmmFpRV32I` were contaminated the same
  way (1 and 4 M-instructions); they build clean now. The other 13 C tests
  were never affected — GCC found no reason to emit MUL for them, which is
  exactly why this went unnoticed for a month.

## 2026-08-11: performance counters for Lightning (`LTG_PERF`)

Lightning had no PERF block; the in-order core's (`rtl/core/riscv_core.sv`)
was the only one. Ported the architecture-independent counters over and
added the OoO-specific ones, per `docs/perf-counters-plan.md`. Everything
lives at the bottom of `rtl/ooo/LightningCore.sv`; see `docs/architecture.md`
for what it reports. Three things worth writing down.

### The switch had to be `LTG_PERF`, not `PERF`

The plan said to mirror the in-order core's `` `define PERF ``. That does
not work here, and the failure is silent. Macros carry across files on the
compiler command line, `RTL_DIR_ORDER` puts `rtl/core` before `rtl/ooo`, and
`riscv_core.sv` is compiled in **every** build regardless of `CORE` (only
the `riscv_core_interface*` files are filtered out). So `riscv_core.sv`'s
`` `define PERF `` at line 36 is already in scope by the time
`LightningCore.sv` is preprocessed.

Measured, not guessed: with a `` `define PERF `` in `LightningCore.sv`,
commenting it out left the counters compiled in and printing. Commenting out
`riscv_core.sv`'s as well was what turned them off. That is the same
macro-leak trap `1DRIS_defs.sv` documents for `DEBUG`, and it would have
meant "comment out before synthesis" quietly not working.

Renamed to `` `LTG_PERF `` (LTG_* is the convention for Lightning knobs,
`ifndef`-guarded, on by default). Verified independent afterwards: with
`riscv_core.sv`'s `PERF` left defined, commenting out `` `define LTG_PERF ``
alone drops the Lightning block and the build still passes. `cache_sweep.py`
now passes `+define+PERF +define+LTG_PERF` so a sweep gets a printout
whichever core it is pointed at.

### Mispredicts and mispredict redirects are not the same number

The plan's sanity check 4 expected `branches_mispredicted` to equal the
count of `mispredict_valid` pulses. It doesn't, and the difference is real
hardware behavior, not a counting bug: `BranchShelf` step (3) clears the
oldest WRONG entry *and everything younger than it*, and step (6) wipes the
shelf on a trap — both run in the same `always_comb` pass that step (2)
writes the resolve verdict in. A branch that resolves WRONG in the cycle an
older branch's flush reaches it is itself wrong-path, so its WRONG status is
overwritten before anyone sees it and it never redirects.

Rather than leave the two numbers unreconciled, the shelf exports a third
event, `perf_resolve_wrong_squashed` (`perf_resolve_wrong` whose verdict is
gone from the final `next_shelf`). The invariant is

    mispredicted - squashed == mispredict redirects

which holds on all 53 asm tests (`beqtest` is the one that exercises it:
8 - 2 == 6). Sanity check 4 in the plan should be read as this, not as
equality.

### Sanity check 3 (`hits + misses == accesses`) does not hold, on either core

`num_i_cache`/`num_d_cache` are not probe counts. They're derived from
`choose_d_cache`, which is main-memory port arbitration, so "D$ accesses" is
cycles the D-side owned the memory bus and "I$ accesses" is literally every
other cycle, idle ones included (`memtest2`: I$ accesses 216 of 220 cycles,
against 25 I$ misses). Inherited semantics from the in-order core, so the
`$display` string is kept for shared parsing, with a note line printed under
it. `hits`/`misses` are the real per-cache numbers. Also: `I$ hits: 0` on a
straight-line test is correct, not a broken signal — a fetch group is a
whole cache block here, so code with no reuse never re-probes a block
(`depend`: 0 hits / 80 misses / 15 evictions for 316 straight-line
instructions). Loopy tests show hits (`brtest2`: 13 hits / 21 misses).

### Also fixed here

`rtl/ooo/1DRIS_defs.sv:120` — HEAD (`ad1277d`) did not compile under VCS
T-2022.06 at all: `typedef dris_entry_t EMPTY_DRIS_ENTRY = '{...}` is a
constant declared with `typedef`, which cannot take an initializer. Changed
to `localparam dris_entry_t`. It is unused today (one commented-out
reference in `NewDris.sv`), so this is purely the syntax fix.

### Verification

- 53/53 `tests/asm` (all but the 3 expected mul failures): `instructions
  retired` equals `make verify-trace`'s commit count **exactly**, on every
  one. That is the counter cross-check that matters — it validates the
  retire accounting, the halting-ecall +1, and the DRIS-indexed
  `retire_vector` scatter in a single number.
- `make regress SIM=vcs` unchanged on both cores: 3 mul failures, nothing
  else. PERF is observation-only.
- Non-PERF build (the synthesis configuration) compiles and passes.
- Watchdog fallback: `depend` with `+define+LTG_MAX_SIM_CYCLES=200` prints
  once, flagged `!! run ended without a halting ecall`. A normal halting run
  also prints exactly once — the `perf_printed` flag is blocking-assigned so
  the `final` block sees it before `$finish` (same reasoning as
  `commit_verifier`'s `dumped`; NBA updates land after `$finish`).

### tests/perf baseline, CORE=lightning, VCS, defaults (32-entry DRIS, 4 fetch/4 exec ways, 8-entry shelf)

| | dhrystone | fft | spmv | kosarajus |
|---|---|---|---|---|
| verify | Correct | Correct | Correct | **TIMEOUT** |
| cycles | 9,828,242 | 7,566,159 | 15,452,918 | 20,000,000 (cap) |
| retired | 4,889,053 | 3,885,328 | 7,055,601 | 112,300 |
| fetched | 5,613,504 | 5,234,499 | 9,880,334 | 112,456 |
| IPC | 0.497 | 0.514 | 0.457 | 0.006 |
| intake stall (DRIS full) | 3,575,156 | 11,011 | 8,299,935 | 160,159 |
| intake stall (shelf full) | 0 | 0 | 1,640,554 | 0 |
| mispredict redirects | 130,053 | 349,331 | 315,076 | 12 |
| branches resolved / mispred | 658,108 / 140,062 | 1,375,144 / 375,417 | 1,628,119 / 346,621 | 8,035 / 12 |
| DRIS occupancy avg (of 32) | 16.9 | 2.9 | 22.8 | 0.3 |
| shelf occupancy avg (of 8) | 1.6 | 0.9 | 2.4 | 1.0 |
| int slots/cycle (of 4) | 0.551 | 0.676 | 0.606 | 0.006 |
| memory issues/cycle (of 1) | 0.277 | 0.023 | 0.154 | 0.002 |

What the numbers say, for whoever tunes this next:

> **Two of these bullets were disproven the same day by direct experiment —
> see the `2026-08-11 (later)` entry below and `docs/perf-counters.md`. The
> `LTG_DRIS_ENTRIES` and `LTG_BRANCH_SHELF_ENTRIES` recommendations are
> withdrawn: both knobs move the *stall attribution* on spmv without moving
> the cycle count at all.** The rest stands.

- **Execute width is not the bottleneck anywhere.** 0.55-0.68 integer slots
  used per cycle out of 4 ways (14-17%). Widening EXECUTE_WAYS would buy
  nothing; the starvation is upstream.
- ~~**DRIS capacity is the bottleneck on dhrystone and spmv**~~ — intake is
  blocked 36% and 54% of all cycles respectively, entirely on `dris_room`,
  and spmv sits at 22.8/32 average occupancy, but *blocked is not the same as
  limited*: doubling to `LTG_DRIS_ENTRIES=64` changes spmv by +9 cycles out
  of 15.45M. The intake-stall counters report whichever structure happens to
  be full, not what limits throughput.
- **fft is prediction-bound instead**: DRIS-full is noise (11k cycles) but it
  takes 349k mispredict redirects at a 27% mispredict rate. (This one holds
  up against the in-order baseline: fft is also where Lightning takes 3× the
  baseline's I$ misses.)
- ~~**spmv is the only benchmark where the branch shelf ever blocks intake**~~
  (1.6M cycles) — true as stated, but not actionable:
  with a 64-entry DRIS the shelf simply absorbs the pressure (shelf-full rises
  to 6.7M cycles) and the runtime is unchanged. `LTG_BRANCH_SHELF_ENTRIES` is
  not the knob.
- Note `retire_drought` is high everywhere (69% of cycles on dhrystone) while
  DRIS occupancy is mid-range — retire bandwidth is not the constraint;
  entries are sitting un-executed.

**kosarajus hangs** (hit the 20M watchdog; the counters come from the
`final`-block fallback). Pre-existing, not caused by the counters — the same
run on HEAD + only the `1DRIS_defs.sv` syntax fix also times out. The
counters do characterize it: the DRIS is 99% *empty* (avg 0.317 valid
entries), integer slots 0.1% used, only 112k instructions retired in 20M
cycles — and 2,199,096 I$ misses against 40,160 hits with 618,471 evictions.
That is fetch starvation / I-cache thrashing, not an OoO-engine deadlock,
which is a different place to start looking than `fibm.c`'s hang.

(Amended below: the in-order core runs kosarajus to a `Correct` result in
15,291,881 cycles, so the *program* is fine and this is Lightning-specific.
And the eviction figure quoted here should not be trusted — `is_eviction` is
broken on both cores, see the next entry.)

## 2026-08-11 (later): the in-order core as baseline

Ran all four `tests/perf` benchmarks on `CORE=inorder` under VCS to get the
number Lightning actually has to beat. Full standing, the counter inventory
with per-counter trust status, and the reproduction commands now live in
**`docs/perf-counters.md`**; that file is the living reference. Summary and
the things that were surprising:

**Lightning currently beats the baseline on one of four benchmarks.**
dhrystone 12,184,845 → 9,828,242 (1.24× faster); fft 7,527,873 → 7,566,159
(parity); spmv 12,847,326 → 15,452,918 (**0.83×, 20% slower**); kosarajus
15,291,881 and `Correct` on the baseline vs the 20M watchdog on Lightning.
Commit `a3859cd`'s "20% less cycles than the inorder" is right on dhrystone
and does not generalize.

### In-order IPC has to be computed — its instruction counters are per-cycle

The baseline's `ALU` / `Loads` / `Stores` and branch/JAL/JALR histograms
increment every cycle straight off W-stage control signals with no validity
gate (`riscv_core.sv:948-975`), so bubbles and flush cycles land in them. On
`beqtest` they sum to `97 + 21 = 118` = exactly the cycle count, against 21
actually-retired instructions. The `rewind` histogram index is worse: it
samples `correct_branch_prediction`, an **M1** signal, against a **W**
instruction. Lightning's equivalents are retirement-gated and correct, so
these rows are not comparable in either direction.

The core does compute a real `total_instructions` (`riscv_core.sv:911-916`)
but **no `$display` ever emits it**, and it carries the same M1-vs-W mismatch,
so it would undercount by about one per mispredict. Left alone rather than
"fixed" silently — the baseline core is the blessed rig.

Instead: retired counts are architecturally identical across cores for a fixed
binary, so Lightning's (already verified == refsim on 53/53 asm) serves both.
Confirmed directly — in-order commit traces match the refsim on beqtest /
depend / memtest2 at 21 / 316 / 93.

### `is_eviction` is unusable on both cores

Gated on `(&way_valid) && (|current_set.metadata)` and only sampled during
refill (`cache3.sv:373-376`, `:280`). Lightning's spmv reports 244,900 I$
misses against **8** evictions in a 64-block cache; the baseline's dhrystone
reports 42,011 D$ misses against **0**. Both impossible. Every eviction number
recorded in the entry above should be disregarded.

D$ hit/miss also mean different things per core — calibrated on `memtest2`
(34 loads, 26 stores), the baseline reports 33+1 = loads only, Lightning
reports 56+4 = loads and stores. The two wrap different controller FSMs
(`cache_controller_ref` vs `cache_controller2`) around the same `cache3`. I$
misses are the one cache figure that compares cleanly.

### spmv: two hypotheses tested, both null

| config | cycles |
|---|---|
| default | 15,452,918 |
| `LTG_ICACHE_INDEX_BITS=8` (8× I$) | 15,452,903 |
| `LTG_DRIS_ENTRIES=64` (2× DRIS) | 15,452,927, still `Correct` |

The I$ null is real, not a define that failed to apply: `parameters.vh:18`
plumbs it, and behaviour *did* change (I$ evictions 8 → 0) while misses stayed
at 244,897 vs 244,900. So Lightning's spmv I$ misses are not capacity or
conflict misses.

The DRIS null is the more useful result — the stall **relocated**: DRIS-full
8,299,935 → 2,373,424, branch-shelf-full 1,640,554 → 6,681,203, total runtime
unchanged. That is what disqualifies the intake-stall counters as a diagnosis,
and it retires the shelf as a candidate too.

Three very different configs landing within 9 cycles of each other means
something serial dominates spmv that none of these knobs touch. Not memory
latency — `tb/main_memory.sv` is combinational with no delay model. **Still
unidentified**, and it is the blocker for Lightning beating the baseline more
broadly.

### kosarajus is a fetch-path livelock, not speculation

Lightning takes only **12** mispredict redirects across the entire run,
alongside a 98% I$ miss rate (2,199,096 vs 40,160 hits), a 99%-empty DRIS and
integer slots at 0.1%. Speculation is not the mechanism. Given the spmv I$
null, a bigger I$ is unlikely to help either; this needs a waveform on the
fetch/I$ request path.

## 2026-08-12: fibi perf comparison + the I-fetch bounds checker

### fibi joins the standing (Lightning 1.13×)

Ran `tests/c/fibi.c` on both cores under VCS at defaults, into separate
`OUTPUT_BASE_DIR` trees. Identical register dumps, both matching the
`fibi.reg` oracle. Lightning 22,438 cycles vs the baseline's 25,321 — 1.13×,
IPC 1.003 vs 0.889. Second win after dhrystone, and a different mechanism:
the DRIS never fills (avg 5.6 of 32, **zero** intake stall cycles) and integer
slots sit at 29.9% of 4, so this is not an occupancy win. Numbers and the
full breakdown in `docs/perf-counters.md` §1.1.

### The I$ miss count is the whole story, and it is not wrong-path addresses

fibi's text is **196 bytes**. That is 13 blocks of a 64-block I$ — the entire
program resident with 80% of the cache spare, cold-miss floor 13. The baseline
takes 21 misses. Lightning takes **858**.

Hypothesis: wrong-path fetch running off into the `0xdedede...` segment fill.
Built `tb/ifetch_bounds_check.sv` to settle it — taps `core_req_re` /
`core_req_addr` at the core→I$ seam, puts back the two implied low bits (the
core drives pc[31:2]), and range-checks against the program image actually
loaded, sizing `mem.text.bin` / `mem.ktext.bin` with the same `$fseek`/`$ftell`
idiom `main_memory` uses. That is the same extent the test's disassembly
covers, without parsing anything: it computed text as `[0x00400000,
0x004000c4)` against a disassembly whose last instruction is `jalr` at
`0x4000bc` with `unimp` at `0x4000c0`.

Instantiated in **both** core interfaces under `ifdef SIMULATION_18447` so
synth is untouched, with `CORE_NAME` telling them apart in the log. Reports
rather than fails by default — wrong-path fetch past the end of the program is
legal behaviour on an OoO core and the point was to measure it, not to ban it;
`+define+IFETCH_BOUNDS_FATAL` makes the first one fatal. Costs no cycles: both
cores' totals are identical with it in.

**Hypothesis disproven.** In-order: 0 out-of-bounds. Lightning: 5, all
`0x004000d0`, on cycles 22428–22432 — the last five cycles of the run, 12 bytes
off the end while the machine drains at halt. Both cores report exactly one
unknown-address request, on cycle 1: the X fetch PC out of reset, benign but
worth knowing the checker sees it.

So all 858 misses are requests for addresses *inside* a 196-byte program.
Nothing is evicted by capacity or conflict, which means lines are being
installed and then lost, or never installed. The number sitting next to 858 is
**793 mispredict redirects** (792 flush cycles) — about one extra miss per
redirect over a 13-block floor. Prime suspect is the `core_req_cancel` path:
a redirect killing an in-flight refill so the line never lands and the
post-mispredict re-fetch misses again. That would also explain the 2026-08-11
spmv I$ sizing null — if lines are dropped rather than evicted, no cache size
helps. Unconfirmed; needs cancels instrumented against refill completions in
`cache_controller2`. `docs/perf-counters.md` §4.1 and open question 5.

fibi is a 22K-cycle reproduction of this, against multi-million-cycle perf
benchmarks — iterate there.

## 2026-08-15: the cancel fix lands, and the I$ turns out not to have mattered

Continues the 2026-08-12 entry above and `docs/perf-counters.md` §4.1a. The
suspect was right, the mechanism was not, and the fix does not buy what the
last three entries assumed it would.

### `core_req_cancel` is now `mispredict_valid`, and that needs an F-queue

`assign core_req_cancel = redirect` became `= mispredict_valid`
(`rtl/ooo/InstructionIssueUnit.sv`). `redirect` includes `ct_redirect`, which
fires on every JAL and every predicted-taken branch — *correctly predicted*
control flow — so fibi raised 5,826 cancels against 793 mispredicts and threw
away a cache line each time.

**The one-line change is not safe on its own.** With `ct_redirect` no longer
cancelling, the sequential fetches past a taken branch still arrive at the
response FIFO, and `slot_valid` keys off `core_rsp_data_valid` alone — those
wrong-path instructions would be written into the DRIS as architectural. The
change needs somewhere for them to die, so the IIU now carries an **F-queue**:
two entries (matching the controller's 2-deep response FIFO) tracking every
outstanding request, with `busy` (a response is still owed) and `good` (it is
still on the fetch path) as separate bits. A CT cut or trap clears `good` only
— nothing cancelled the cache, so the response is still coming and must be
received — and `f2.good` gates `issue_fire`, `intake_stall` and the two
`perf_stall_*` counters. Folding the two bits into one drops occupancy on the
redirect and the next wrong-path response arrives untracked.

The mispredict cancel needs the opposite handling from `e59a386`'s
`cancel = 1'b0`: `core_req_cancel` flushes the controller's whole response
FIFO (`cache_controller2.sv:504`), forces `next_state = IDLE` (:251) and
suppresses the enqueue strobes (:370), so *every* outstanding request is
voided at once. The F-queue clears both entries outright on a cancel rather
than just marking them wrong-path. `accept` is also gated on
`!core_req_cancel`, because the cancel override clears `cache_issue_read` but
**not** `core_rsp_ready` — without that term a cancel cycle records a request
the controller never took. Three `$fatal` assertions hold the invariant.

Verified: `make regress TESTS='tests/asm/*.S' SIM=vcs` is the 3 known mul
failures and nothing else; fibi and dhrystone both verify `Correct` with
identical retired counts (22,507 / 4,889,053).

### Build fix: the shelf typedefs had to move into the package

`BranchShelf` now lives in its own file. Sources are compiled in sorted order
per directory, so `BranchShelf.sv` precedes `InstructionIssueUnit.sv` and the
`$unit`-scope `shelf_intake_pkt_t` / `btb_train_pkt_t` were not yet declared
when its port list elaborated — a hard syntax error. Both typedefs moved into
`package DRIS_defs` (`rtl/ooo/1DRIS_defs.sv`, the `1` prefix is exactly this
ordering convention). Same reason the DEBUG note at the top of that file
exists.

### The fix works on the cache and costs cycles

| dhrystone, `core_req_cancel` = | cycles | I$ misses | phantom | lost fills |
|---|---:|---:|---:|---:|
| `redirect` (original) | **9,828,242** | 548,085 | 158,045 | 42,042 |
| `mispredict_valid` | 9,924,185 | 448,076 | 50,035 | 48,049 |
| `1'b0` (e59a386) | 9,934,184 | **404,047** | **0** | 0 |

Monotonic, and the wrong way round: the closer the I$ gets to its ideal miss
floor the slower the program runs. **A cancelled miss never requested a fill,
so it never paid the memory latency** — it was cheap and wasteful, not slow.
Completing the fill costs 8 cycles on a port the D$ also wants. The original
cancel was accidentally acting as a "don't fill on speculative fetches"
filter and that filter was winning.

spmv settles it: I$ misses **244,900 → 260** (940×) for a **78-cycle**
change in a 15.45M-cycle run.

### The memory model was documented wrong, and it misled all of this

`docs/perf-counters.md` §4.2 said "`tb/main_memory.sv` is combinational, with
no delay model at all." `main_memory.sv` is combinational, but the testbench
wraps it in a `delay_buffer` with `DELAY = 8` (`tb/testbench.sv:128-138`) and
`riscv_core_interface` arbitrates **both** caches onto that one port
(`:97-108`). Every fill, I$ and D$, pays 8 cycles. The instance is named
`DataDelayBuffer` and parameterized with `DMEMORY_READ_DELAY`, which is where
the "D-side only" reading came from. `LTG_IMEM_READ_DELAY` /
`IMEMORY_READ_DELAY` is imported at `tb/testbench.sv:61` and used nowhere — a
dead knob, not a second delay.

### Bounding the whole memory system: 16.7%

Set the latency to 1 cycle and read off what disappears — this bounds every
memory-system improvement at once (non-blocking caches, MSHRs, hit-under-miss,
prefetch, sizing, port de-contention). dhrystone 9,924,185 → **8,261,978,
−16.7%**, with about half the latency already being overlapped. And:

- **No D-side miss traffic to parallelize.** dhrystone takes **36** D$ misses
  in 9.9M cycles. spmv has real traffic (141,208) but freeing all of it is
  1.13M cycles, **7.3%** against a 20% deficit.
- **Removing memory latency makes the real bottleneck worse.** Intake stalls
  *rose* 3.49M → 4.25M; 65% of cycles still retire nothing.

So "an OoO engine can't perform without non-blocking caches" is not what is
happening here. It is bounded at 16.7% on dhrystone and ~7% on spmv.

`LTG_DMEM_READ_DELAY=0` hangs the core outright — zero retired, watchdog —
despite `delay_buffer` documenting DELAY=0 as combinational. Latent bug,
perf-counters open question 8.

### The one real win: an 8 KB I$ is −17% on dhrystone

| dhrystone | cycles | I$ misses | I$ evictions |
|---|---:|---:|---:|
| default (1 KB I$) | 9,924,185 | 448,076 | 387,960 |
| `LTG_ICACHE_INDEX_BITS=8` | **8,240,847 (−17.0%)** | **255** | **0** |

1.48× the in-order baseline, up from 1.24×, and within 0.3% of the
1-cycle-memory bound — on dhrystone the entire memory-system cost *is* I$
capacity misses (187 blocks into 64), and sizing collects all of it. The
2026-08-11 "I$ sizing is a genuine null" result was only ever run on spmv,
which does not overflow; it does not transfer.

### Two regimes, and a lead on spmv

fibi is **fetch-starved** (DRIS 5.6/32 avg, capacity hit zero times, zero
intake stalls) — the compute-bound case, still a front-end problem.
dhrystone and spmv are **DRIS-bound** and were before this work. Don't
generalize a limiter across them; perf-counters §1.2.

The lead worth chasing (§1.3): on spmv, intake reports **DRIS-full for
8,299,678 cycles** while the valid-entry count is at capacity for only
**1,534,113**. Intake uses `fetch_ptr − retire_ptr`; PERF popcounts valid
entries. For ~6.8M cycles — 44% of the run — the DRIS is *not* full but the
pointers say it is, i.e. `retire_ptr` is not advancing past finished work.
That makes spmv's dominant stall a retirement stall with an intake stall's
name on it, and `branch_fence_valid` is the first suspect. Measure the fence
hold cycles and histogram the allocated-but-dead gap before touching anything
in the front end.

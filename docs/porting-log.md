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

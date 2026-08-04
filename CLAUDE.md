# CLAUDE.md

OoO RISC-V core (RV32I, DRIS/Metaflow-style). Dual-simulator: Verilator
(default, portable) and VCS (`SIM=vcs`, CMU AFS only). History and gotchas:
`docs/porting-log.md` — read it before touching the harness or build.
File/module map + how everything interacts: `docs/architecture.md` — read
it first instead of re-exploring the tree; keep it updated when the
structure changes.

## Commands

- `make verify TEST=tests/asm/additest.S` — build, run, diff vs `.reg` oracle
- `make verify-trace TEST=...` — per-commit architectural state compare vs
  refsim; first divergent commit reported with pc/insn/regs/cycle and the
  `$time` to jump to in the waveform (README
  "verify-trace"). Works on both cores; on lightning the `insn` annotation
  needs `PARAMS='+define+DEBUG'` (the DRIS keeps the instruction word only
  in DEBUG builds) — nothing diffs against that field either way
- `CORE=lightning|inorder` (config.mk) — which core the harness wraps; the
  in-order class core is the known-good rig for harness work
- `make regress TESTS='tests/asm/*.S'` — suite; omit TESTS for everything
  with an oracle (C tests are slow; see "Ground truth" for what passes)
- `make lint` — verilator -Wall with `lint.vlt` waivers; keep it at zero
- `make waves TEST=...` — FST + gtkwave
- `make refdump TEST=...` — reference register dump (`refdump.reg`) from
  the in-repo C simulator (`tools/refsim`, built on demand); use
  `scripts/gen_ref_reg.sh <test>` to write the `.reg` oracle next to the
  test. RV32I only (no M): mul tests can't be oracled with it.
- Hardware knobs: `LTG_*` in `rtl/include/config.vh`, overridden per run via
  `PARAMS='+define+LTG_...=N'`. Build knobs: `config.mk`.
- `PARAMS='+define+DEBUG'` adds the debug pc/instruction fields to the OoO
  packets and DRIS entries (waveform readability + `insn` in commit
  packets). It builds and passes the same tests as a normal build; keep it
  that way — it silently rotted before (2026-07-31 porting-log entry).

## Ground truth

- **VCS is the semantics oracle.** Any RTL/tb change must keep VCS behavior
  identical; 2-state Verilator differences get fixed on the Verilator side
  (or documented). Final blessing = `make regress SIM=vcs` on AFS.
- The Verilator binary is a **v5.048 -O1 build** (`VERILATOR` in config.mk);
  stock -O3 builds segfault on this design (GCC 13.3 miscompile).
- Expected failures today (CORE=lightning, `make regress SIM=vcs` over
  tests/asm): the 3 mul tests, and only those (nobody implements M — not
  even the refsim). Everything else passes, loads/stores, `memtest2` and
  syscalltest included; the same 53 also pass `make verify-trace`. In
  tests/c, `fibi.c` passes (verify and verify-trace) and `fibm.c` hangs
  (the watchdog catches it; it hung before the port too). CORE=inorder
  passes everything except the same 3 mul tests.
  Don't "fix" failures by touching the harness — the harness is blessed
  against the in-repo in-order core (`CORE=inorder`, formerly the
  `~/lab4b-vl` rig, see porting log).
- tests/c and tests/perf `.reg` oracles are class-toolchain-coupled
  (caller-saved register residue). Local GCC ≠ class GCC ⇒ residue diffs,
  not bugs. On AFS this does not bite: all four tests/perf benchmarks
  (dhrystone, fft, kosarajus, spmv) verify clean on `CORE=inorder` under
  VCS, byte-identical binaries to the pre-OoO reference build.
- **C is compiled `-march=rv32i` (`RISCV_ARCH_C`), assembly `rv32im`
  (`RISCV_ARCH`).** Do not collapse these back into one knob. Nothing here
  decodes M, so any MUL/DIV GCC emits for ordinary C silently corrupts
  results — that is exactly what broke tests/perf for a month (porting log,
  2026-08-07). rv32im on the `.S` side only exists so binutils can encode
  the 3 class mul tests, which still fail at runtime as expected.

## Conventions

- SV sources are auto-discovered (`rtl/core rtl/ooo rtl/mem tb`, sorted per
  dir — the `0`/`1` filename prefixes order packages first). New files need
  no Makefile edits.
- Testbench must stay a single SV top valid for both simulators; no
  Verilator-only C++ harness, no VCS-only constructs outside `ifdef guards.
- A watchdog `$finish`es runs after `LTG_MAX_SIM_CYCLES` (livelocked cores
  otherwise log forever); the Makefile deletes stale `simulation.reg` before
  each run — keep both if you rework the sim flow. A timed-out run *does*
  write its register dump (commit_verifier `final` block, state at the
  cutoff); `verify` fails it by grepping the sim log for `TIMEOUT:`, so
  don't rely on a missing dump to fail a run.
- Lint waivers: prefer fixing RTL; else document in `lint.vlt` (global rules
  there don't always catch elaboration-stage warnings — those need inline
  `// verilator lint_off` metacomments; see porting log).

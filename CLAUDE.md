# CLAUDE.md

OoO RISC-V core (RV32I, DRIS/Metaflow-style). Dual-simulator: Verilator
(default, portable) and VCS (`SIM=vcs`, CMU AFS only). History and gotchas:
`docs/porting-log.md` — read it before touching the harness or build.
File/module map + how everything interacts: `docs/architecture.md` — read
it first instead of re-exploring the tree; keep it updated when the
structure changes.

## Commands

- `make verify TEST=tests/asm/additest.S` — build, run, diff vs `.reg` oracle
- `make verify-trace TEST=... CORE=inorder` — per-commit architectural state
  compare vs refsim; first divergent commit reported with pc/insn/regs/cycle
  (README "verify-trace"; lightning can't run it yet — SSC lacks retire info)
- `CORE=lightning|inorder` (config.mk) — which core the harness wraps; the
  in-order class core is the known-good rig for harness work
- `make regress TESTS='tests/asm/*.S'` — suite; omit TESTS for everything
  with an oracle (C tests are slow and currently can't pass — see below)
- `make lint` — verilator -Wall with `lint.vlt` waivers; keep it at zero
- `make waves TEST=...` — FST + gtkwave
- `make refdump TEST=...` — reference register dump (`refdump.reg`) from
  the in-repo C simulator (`tools/refsim`, built on demand); use
  `scripts/gen_ref_reg.sh <test>` to write the `.reg` oracle next to the
  test. RV32I only (no M): mul tests can't be oracled with it.
- Hardware knobs: `LTG_*` in `rtl/include/config.vh`, overridden per run via
  `PARAMS='+define+LTG_...=N'`. Build knobs: `config.mk`.

## Ground truth

- **VCS is the semantics oracle.** Any RTL/tb change must keep VCS behavior
  identical; 2-state Verilator differences get fixed on the Verilator side
  (or documented). Final blessing = `make regress SIM=vcs` on AFS.
- The Verilator binary is a **v5.048 -O1 build** (`VERILATOR` in config.mk);
  stock -O3 builds segfault on this design (GCC 13.3 miscompile).
- Expected failures today (CORE=lightning): load/store/mul asm tests,
  syscalltest (Lightning halts on any syscall at the retire head), and all
  tests/c, tests/perf (no memory unit; nobody implements M yet).
  Passing set = ALU/branch/jump asm tests. CORE=inorder passes everything
  except the 3 mul tests. Don't "fix" the others by touching the harness —
  the harness is blessed against the in-repo in-order core (`CORE=inorder`,
  formerly the `~/lab4b-vl` rig, see porting log).
- tests/c and tests/perf `.reg` oracles are class-toolchain-coupled
  (caller-saved register residue). Local GCC ≠ class GCC ⇒ residue diffs,
  not bugs.

## Conventions

- SV sources are auto-discovered (`rtl/core rtl/ooo rtl/mem tb`, sorted per
  dir — the `0`/`1` filename prefixes order packages first). New files need
  no Makefile edits.
- Testbench must stay a single SV top valid for both simulators; no
  Verilator-only C++ harness, no VCS-only constructs outside `ifdef guards.
- A watchdog `$finish`es runs after `LTG_MAX_SIM_CYCLES` (livelocked cores
  otherwise log forever); the Makefile deletes stale `simulation.reg` before
  each run — keep both if you rework the sim flow.
- Lint waivers: prefer fixing RTL; else document in `lint.vlt` (global rules
  there don't always catch elaboration-stage warnings — those need inline
  `// verilator lint_off` metacomments; see porting log).

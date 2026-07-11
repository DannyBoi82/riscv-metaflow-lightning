# lightning

An out-of-order RISC-V (RV32I) core — the DRIS/Metaflow-style successor to
`metaflow-lightning`, restructured for dual-simulator development: Verilator
anywhere, VCS on CMU AFS hosts.

## Layout

```
lightning/
├── Makefile              # single entry point, SIM=verilator|vcs
├── config.mk             # build knobs (simulator, toolchain, PARAMS, ...)
├── lint.vlt              # documented lint waivers (make lint)
├── rtl/
│   ├── include/          # config.vh (LTG_* hardware knobs) + class headers
│   ├── core/             # baseline in-order pieces reused by the OoO core
│   ├── ooo/              # DRIS, Scheduler, SSC, IIU, LightningCore
│   └── mem/              # cache3, cache controllers, riscv_core_interface
├── tb/                   # testbench, main_memory, register_file,
│                         #   commit_verifier (portable: Verilator AND VCS)
├── runtime/              # crt0.S, test_program.ld
├── tests/                # asm/ c/ perf/ custom/ — sources + .reg oracles
├── tools/refsim/         # in-repo C reference simulator (oracles + traces)
├── scripts/              # cache_sweep.py, gen_ref_reg.sh, trace checker/viewer
├── synth/                # DC flow (AFS hosts only)
└── docs/                 # architecture.md, porting-log.md, TODOs
```

## Quick start

```
make verify TEST=tests/asm/additest.S      # build + run + diff vs oracle
make verify-trace TEST=... CORE=inorder    # per-commit state compare (below)
make regress TESTS='tests/asm/*.S'         # regression over a glob
make waves TEST=...                        # FST + gtkwave (SIM=vcs: DVE)
make lint                                  # verilator --lint-only -Wall, clean
make help                                  # everything else
```

Two cores share the harness: `CORE=lightning` (default, the OoO core) and
`CORE=inorder` (the blessed 8-stage class core, `rtl/core/` — a known-good
rig for harness work).

Hardware knobs (cache geometry, DRIS sizing, memory latency, watchdog) are
`LTG_*` macros in `rtl/include/config.vh`; override per run with
`PARAMS='+define+LTG_DCACHE_INDEX_BITS=6'` — the build re-triggers
automatically when PARAMS change. Build knobs live in `config.mk`.

## Dependencies

- **Verilator**: v5.048 built at `-O1` (`~/.local/bin` here; default `-O3`
  builds miscompile on this design — see `docs/porting-log.md`). Pin via
  `VERILATOR=` in config.mk.
- **RISC-V GCC**: auto-detected from common prefixes; tests build with
  `-march=rv32im -mabi=ilp32` (`RISCV_ARCH` in config.mk).
- **AFS-only** (CMU hosts): VCS (`SIM=vcs`) and DC synthesis (`make synth`).
  The reference simulator is in-repo (`tools/refsim`, built on demand by
  `make refsim`/`refdump`/`reftrace`); the AFS class binary remains usable
  via `REFSIM_EXECUTABLE=` in config.mk.

## verify-trace: per-commit state compare

`make verify-trace TEST=... CORE=inorder` compares **full architectural
register state after every committed instruction** against the reference
simulator, and reports the first divergent commit with its PC, instruction,
differing registers, and RTL retire cycle (jump there with `make waves`).
Because every line is a full state keyed by "one committed instruction",
the diff self-anchors — bubbles, stalls, and multi-way retirement can't
slip the alignment the way the old write-event trace could.

How it works:

1. The core emits one `commit_pkt_t` per retired instruction
   (`rtl/include/riscv_commit.vh` — RVFI-style: pc, insn, rd_addr with
   0 = "no register write", rd_wdata; slot 0 = oldest in the cycle).
2. `tb/commit_verifier.sv` replays the packets into a shadow architectural
   regfile, writes one state line per commit to `commit_trace.txt` (under
   `+commit_trace`, which `verify-trace` passes), and produces the
   end-of-run `simulation.reg` dump from that same shadow.
3. The refsim writes the same format (`statetrace` shell command;
   `make reftrace TEST=...`), and `scripts/check_commit_trace.py` diffs
   them (`scripts/view_commit_trace.py` pretty-prints a trace).

**The commit packets are the only design-to-harness contract.** Both
current cores produce them inside `tb/register_file.sv` (the core supplies
per-slot `commit_valid`/`commit_pc`/`commit_insn`; the regfile pairs them
with its write ports) — but using that module is *not* required. A design
with, say, an architectural-vs-physical register file split has no
architectural regfile module to instrument; it just drives the
`commit_pkts` array itself at its retirement point (report every retired
instruction exactly once, in program order, wrong-path excluded, x0 writes
as rd_addr=0) and the whole flow works unchanged.

Cost: tracing is print-side only — **cycle counts and perf counters are
unaffected**. The price is wall-clock and disk (~300 B per commit, so
~300 MB per million commits; the `LTG_MAX_SIM_CYCLES` watchdog bounds
livelocked traces).

Status: blessed on `CORE=inorder` (full asm suite). `CORE=lightning`
currently emits write-only packets (no pc/insn, no non-writing
retirements) — enough for the end-state dump, but `verify-trace` needs
the SSC to emit full retire info (see `docs/TODO-verify-trace.md`).

## Test status & caveats

- LightningCore currently has **no memory unit** (D-side is tied off in
  `riscv_core_interface.sv`) and no M extension: load/store/mul tests and
  all C tests fail by design until those land. The harness itself is
  validated end-to-end against a known-good in-order core (see
  `docs/porting-log.md`, 2026-07-07).
- `tests/c` / `tests/perf` `.reg` oracles are coupled to the class
  toolchain's codegen (register residue); with a different compiler,
  regenerate oracles before trusting failures.
- The committed per-test `.vh` files are the superseded class write-event
  trace oracles (verify-trace replaces that flow); they are reproducible
  locally via the in-repo refsim's `trace` command if ever needed.

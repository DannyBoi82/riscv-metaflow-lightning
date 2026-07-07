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
├── tb/                   # testbench, main_memory, register_file (portable)
├── runtime/              # crt0.S, test_program.ld
├── tests/                # asm/ c/ perf/ custom/ — sources + .reg oracles
├── scripts/              # cache_sweep.py, gen_ref_reg.sh
├── synth/                # DC flow (AFS hosts only)
└── docs/                 # architecture PDFs, TODO-IIU.md, porting-log.md
```

## Quick start

```
make verify TEST=tests/asm/additest.S      # build + run + diff vs oracle
make regress TESTS='tests/asm/*.S'         # regression over a glob
make waves TEST=...                        # FST + gtkwave (SIM=vcs: DVE)
make lint                                  # verilator --lint-only -Wall, clean
make help                                  # everything else
```

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
- **AFS-only** (CMU hosts): VCS (`SIM=vcs`), DC synthesis (`make synth`),
  and the class reference simulator (`make refsim` / oracle regeneration).

## Test status & caveats

- LightningCore currently has **no memory unit** (D-side is tied off in
  `riscv_core_interface.sv`) and no M extension: load/store/mul tests and
  all C tests fail by design until those land. The harness itself is
  validated end-to-end against a known-good in-order core (see
  `docs/porting-log.md`, 2026-07-07).
- `tests/c` / `tests/perf` `.reg` oracles are coupled to the class
  toolchain's codegen (register residue); with a different compiler,
  regenerate oracles before trusting failures.
- The committed `.vh` trace oracles are kept but not regenerable without
  the class-hosted scripts.

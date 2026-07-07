Plan: lightning — a clean, dual-simulator successor to metaflow-lightning
What the new repo keeps, drops, and restructures
Keep (the actual project):

All of src/ — the OoO modules (src/ooo/), cache3 + controllers, core interface, in-order baseline core, decoder, lib, packages, parameters.vh
The simulation framework that's genuinely load-bearing: testbench.sv, main_memory.sv, register_file.sv, the 447include/*.vh headers, 447runtime/ (crt0 + linker script)
Tests: 447inputs/, 447inputs2/, benchmarks/, perf_benchmarks/, custom-tests/ — sources and .reg/.vh oracles only, with .elf/.bin/.disassembly.s build artifacts gitignored instead of committed
docs/ (the four PDFs + TODO-IIU.md), gen_ref_reg.sh, cache_sweep.py
The DC synthesis flow (dc/) as an optional, VCS-machine-only target
Drop (class leftovers):

LAB_18447 knob and all its conditional test-set logic; the corresponding generate if (\LAB_18447 == "4a")branch in the testbench (hardcode theriscv_core_interface` instantiation)
The Pareto snooper — the current Makefile copies your perf regdumps and synthesis reports into /afs/ece.cmu.edu/class/ece447/Lab4_Results on every run. This should absolutely not survive
The synth recipe's cp /afs/ece/class/ece447/Patches/*.sv 447src/ step that overwrites your sources from the class directory at synth time
gen-sv/analyze-regs targets (they call class-hosted Python); the committed .vh trace oracles are kept, just not regenerable without the class scripts — noted in README
old-reports/, dve-sessions/, misc-unused-verilog/, benchmarksO3/ (fold into a OPT=-O3 flag on the benchmarks dir instead of a parallel tree), trace.txt, .riscv_sim_history, output/
Dead framework RTL after an audit: 447src/cache.sv, cache_controller.sv, fifo.sv, riscv_core_timing.sv, sram_*.sv are all compiled today but likely only reachable from the superseded in-order paths — whatever the elaborated tree doesn't instantiate gets deleted, not parked
New layout (flat, purpose-named, no 447 prefixes):


lightning/
├── Makefile              # single entry point, SIM=verilator|vcs
├── rtl/
│   ├── include/          # riscv_isa.vh, riscv_uarch.vh, memory_segments.vh, parameters.vh, ...
│   ├── core/             # riscv_core.sv (baseline), riscv_decode.sv, lib.sv, defines pkg
│   ├── ooo/              # 1DRIS_defs.sv, DRIS.sv, Scheduler.sv, SSC, IIU, LightningCore.sv
│   └── mem/              # cache3.sv, cache_controller2.sv, cache_controller_ref.sv, riscv_core_interface.sv
├── tb/                   # testbench.sv, main_memory.sv, register_file.sv, register names vh
├── runtime/              # crt0.S, test_program.ld
├── tests/
│   ├── asm/              # 447inputs + 447inputs2 merged (names don't collide)
│   ├── c/                # benchmarks (default -O, override with OPT=)
│   ├── perf/             # perf_benchmarks
│   └── custom/           # custom-tests
├── scripts/              # gen_ref_reg.sh, cache_sweep.py
├── synth/                # dc_synth.tcl (VCS/DC hosts only)
├── docs/                 # the four PDFs, TODO-IIU.md
├── CLAUDE.md             # rewritten for the new layout
└── .gitignore            # output/, *.elf, *.bin, *.disassembly.s, obj_dir/, *.vcd, *.fst, ...
The build keeps the auto-discovery convention (find rtl tb -name '*.sv' | sort with the 0/1 filename-ordering trick for packages preserved), so adding files still needs no Makefile edits.

The Makefile rewrite
One Makefile, ~1/3 the size, with a SIM switch:


make verify TEST=tests/asm/additest.S              # Verilator by default
make verify TEST=... SIM=vcs                       # VCS when you want it
make regress                                        # full suite (replaces autograde + LAB sets)
make waves TEST=...                                 # FST + gtkwave (verilator) / DVE (vcs)
make refsim / refdump TEST=...                      # unchanged, still uses class riscv-ref-sim
make synth                                          # DC, unchanged minus snooper/patching
make lint                                           # verilator --lint-only -Wall (+ verible)
Shared logic (test assembly via riscv64-unknown-elf-gcc, section extraction with objcopy, regdump diff, the regression runner) stays simulator-agnostic — it already is. Only the build sim executable and run sim recipes fork on SIM:

VCS backend: current flags minus +define+LAB_18447, minus -fgp (unneeded for a design this size and it complicates nothing else).
Verilator backend: verilator --binary --timing -Wall -Wno-fatal (tightening warnings over time), +incdir mirroring, -o sim into output/verilator/. The testbench's forever #HALF_PERIOD clock, #0 settling, $fopen("rb")/$fread binary segment loading, and $fopen regdump are all supported by Verilator 5 with --timing — no C++ harness needed, the SV testbench stays the single top for both simulators.
riscv-ref-sim and the RISC-V toolchain remain AFS-hosted dependencies; the README states that plainly (sim itself will be portable; oracle regeneration is not).

Known Verilator porting work (the real technical risk)
Hierarchical reference top.mem_access inside register_file.sv — plumb it through a port instead (also makes the regfile self-contained).
2-state vs 4-state: VCS propagates X; Verilator forces 2-state. The testbench's assign pc = 'bx and any reset-dependent X in the core become zeros. Mitigation: build with --x-assign unique --x-initial unique in a make regress SEED=n mode so latent reset bugs still get shaken out, and treat VCS as the X-propagation oracle.
Lint delta: -Wall under Verilator will flag WIDTH/UNUSED/UNDRIVEN issues VCS's +lint tolerated, especially in the OoO modules' whole-array exposure. Budget a cleanup pass; whitelist with /* verilator lint_off */ only where the warning is genuinely wrong.
String-typed localparams / const ref function args in testbench + main_memory — supported in Verilator 5, but if anything chokes, the LAB_18447 string machinery being deleted removes most of it anyway.
Addendum — centralized control + local-toolchain custom tests (added 2026-07-06, before execution)

1. Centralized parameter control, two files by domain, both documented in the README:
   - `config.mk` (repo root) — every build-side knob in one place: SIM backend (verilator|vcs), RISCV_PREFIX (toolchain prefix, auto-detected when empty), OPT (C optimization level), PARAMS (extra +define+ passthrough), output dirs. Included by the Makefile; command-line assignments always win.
   - `rtl/include/config.vh` — every hardware knob in one place, as `ifndef`-guarded `LTG_*` macros: I/D cache geometry (ways, index bits, policy, block offset bits), OoO sizing (DRIS entries, fetch/execute ways, regfile write ports, memory read/write ports, branch ways, branch shelf entries, scheduler window), memory model timing (I/D read delay, read width), superscalar ways, clock half period. `parameters.vh`, `1DRIS_defs.sv`, and `riscv_uarch.vh` derive their parameters from these macros instead of hardcoding (this also replaces riscv_uarch.vh's LAB_18447 conditionals with the lab-4a values as defaults).
   - Because the macros are `ifndef`-guarded, any knob can be overridden per run without editing a file, identically under VCS and Verilator: `make verify TEST=... PARAMS='+define+LTG_DRIS_ENTRIES=32'`.
   - `cache_sweep.py` rewrites `rtl/include/config.vh` instead of `src/parameters.vh`.

2. Custom test compilation with a locally installed RISC-V toolchain:
   - The Makefile auto-detects the toolchain prefix (riscv64-unknown-elf-, riscv32-unknown-elf-, riscv32-unknown-linux-gnu-, riscv64-unknown-linux-gnu-), overridable via RISCV_PREFIX in config.mk. Verified locally: riscv32-unknown-linux-gnu GCC 16.1 in ~/.local/riscv-gnu-toolchain builds both .S tests and .c benchmarks (libgcc rv32i/ilp32 multilib works) against runtime/crt0.S + test_program.ld.
   - `tests/custom/` builds like every other test dir: `make verify TEST=tests/custom/foo.S` diffs against a committed `foo.reg`; `make sim` runs oracle-less tests. Generating a new .reg oracle still requires the AFS-hosted riscv-ref-sim (`scripts/gen_ref_reg.sh`).
   - benchmarksO3 fold: the -O3 register dumps are committed as `tests/c/<name>.O3.reg`; `make verify TEST=tests/c/foo.c OPT=-O3` selects the O3 oracle automatically.

Execution order
Scaffold + migrate: create the new tree, git init fresh (old repo stays as the archive; no history carried over), copy pruned files into the new layout, fix \include` paths and the testbench's hardcoded generate.
VCS parity first: get make regress SIM=vcs passing the same set the old repo passes before touching Verilator — this proves the restructure changed nothing behaviorally.
Verilator bring-up: lint-only → compile → single smoke test (additest.S) → full make regress SIM=verilator, diffing regdumps against the same .reg oracles.
Polish: make waves for both backends, README, rewritten CLAUDE.md (environment gotchas change: no 447setup warning needed, add conda env verilog-hdl for Verilator), .gitignore.
Optional: re-verify make synth still works from the new layout.
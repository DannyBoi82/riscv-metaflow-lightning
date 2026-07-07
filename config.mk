# config.mk
#
# Lightning — centralized build configuration.
#
# Every user-facing build knob lives here. Command-line assignments always
# win over the values in this file (e.g. `make verify TEST=... SIM=vcs`).
#
# Hardware parameters (cache geometry, DRIS sizing, memory latency, ...) live
# in rtl/include/config.vh. Override any of them per build via PARAMS below.

# ------------------------------------------------------------------------
# Simulator backend: verilator (default, runs anywhere) or vcs (AFS hosts)
# ------------------------------------------------------------------------
SIM ?= verilator

# ------------------------------------------------------------------------
# RISC-V toolchain
#
# Leave RISCV_PREFIX empty to auto-detect from the candidates below (first
# one found in PATH wins). Set it explicitly to pin a toolchain, e.g.:
#     RISCV_PREFIX = riscv32-unknown-linux-gnu-
# All tests build with -march=$(RISCV_ARCH) -mabi=ilp32 regardless of the
# prefix. The class mul tests (multest, dependMul*) need the M extension,
# hence rv32im; set RISCV_ARCH=rv32i to mimic a strict base-ISA build.
# ------------------------------------------------------------------------
RISCV_PREFIX ?=
RISCV_ARCH ?= rv32im
RISCV_TOOLCHAIN_CANDIDATES = riscv64-unknown-elf- riscv32-unknown-elf- \
		riscv32-unknown-linux-gnu- riscv64-unknown-linux-gnu-

# ------------------------------------------------------------------------
# C test optimization level. Defaults per directory when empty:
#   tests/c    -> -O
#   tests/perf -> -O0
#   elsewhere  -> -O
# Set OPT=-O3 to build (and, for tests/c, verify against) the O3 variant.
# ------------------------------------------------------------------------
OPT ?=

# ------------------------------------------------------------------------
# Extra hardware parameter overrides, passed to both simulators, e.g.:
#   PARAMS = +define+LTG_DRIS_ENTRIES=32 +define+LTG_DCACHE_INDEX_BITS=6
# See rtl/include/config.vh for the full list of LTG_* knobs.
# ------------------------------------------------------------------------
PARAMS ?=

# ------------------------------------------------------------------------
# X-shakeout mode (Verilator only). Verilator is 2-state, so X values that
# VCS would propagate become deterministic zeros. Setting SEED=<n> builds
# with --x-assign unique --x-initial unique and runs with that runtime seed
# so latent reset bugs still get exercised. VCS remains the X oracle.
# ------------------------------------------------------------------------
SEED ?=

# ------------------------------------------------------------------------
# Output directories
# ------------------------------------------------------------------------
OUTPUT_BASE_DIR ?= output
SIM_OUTPUT      ?= $(OUTPUT_BASE_DIR)/$(SIM)
SYNTH_OUTPUT    ?= $(OUTPUT_BASE_DIR)/synthesis

# ------------------------------------------------------------------------
# Regression suite: every test source with a committed .reg oracle.
# Override with TESTS="..." (glob patterns work) for a subset.
# ------------------------------------------------------------------------
REGRESS_DIRS ?= tests/asm tests/c tests/perf tests/custom

# ------------------------------------------------------------------------
# Reference instruction-level simulator (oracle generator for refsim/
# refdump). Defaults to the in-repo C simulator (tools/refsim, built on
# demand). Point it at the class binary for class-toolchain oracle work:
#     REFSIM_EXECUTABLE = /afs/ece/class/ece447/bin/riscv-ref-sim
# ------------------------------------------------------------------------
REFSIM_LOCAL       = tools/refsim/riscv-refsim
REFSIM_EXECUTABLE ?= $(REFSIM_LOCAL)

# ------------------------------------------------------------------------
# Verilator binary. Default -O3 builds of Verilator 5.048/5.049-devel
# (including the /usr/local one) segfault on this design during C++ header
# emission (AstNodeDType::skipRefIterp via EmitCHeader::emitAll) when
# compiled with GCC 13.3; ~/.local holds v5.048 rebuilt at -O1, which is
# correct. See docs/porting-log.md (2026-07-07) for the full story.
# ------------------------------------------------------------------------
VERILATOR ?= $(HOME)/.local/bin/verilator

# ------------------------------------------------------------------------
# Extra flags passthrough (appended to the respective tool invocations)
# ------------------------------------------------------------------------
VERILATOR_EXTRA ?=
VCS_EXTRA       ?=
RISCV_CFLAGS_EXTRA ?=

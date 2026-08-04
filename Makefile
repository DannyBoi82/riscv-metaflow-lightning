# Makefile
#
# lightning — dual-simulator build system (Verilator | VCS)
#
# Single entry point for assembling RISC-V test programs, compiling the
# processor into a simulator, running and verifying tests, and synthesis.
#
# All user knobs live in config.mk (build side) and rtl/include/config.vh
# (hardware side). Command-line assignments override config.mk.
#
# Common invocations:
#   make verify TEST=tests/asm/additest.S          # Verilator by default
#   make verify TEST=tests/c/fibi.c SIM=vcs        # VCS when you want it
#   make regress                                   # every test with a .reg oracle
#   make waves TEST=tests/asm/additest.S           # FST + gtkwave / DVE
#   make lint                                      # verilator --lint-only -Wall
#   make verify TEST=... PARAMS='+define+LTG_DRIS_ENTRIES=32'

include config.mk

################################################################################
# General
################################################################################

SHELL = /bin/bash -o pipefail

CORES = $(shell getconf _NPROCESSORS_ONLN)
THREADS = $(shell echo $$((2 * $(CORES))))

# Terminal color and modifier attributes (empty when no terminal is connected)
n := $(shell tty -s && tput sgr0)
r := $(shell tty -s && tput setaf 1)
g := $(shell tty -s && tput setaf 2)
b := $(shell tty -s && tput bold)
u := $(shell tty -s && tput smul)

.PHONY: default all clean veryclean check-test-defined check-sim-valid FORCE

default all: help

# Default the output directory by target class
SYNTH_TARGETS = synth view-timing view-power view-area synth-clean
ifneq ($(filter $(SYNTH_TARGETS),$(MAKECMDGOALS)),)
    OUTPUT = $(SYNTH_OUTPUT)
else
    OUTPUT = $(SIM_OUTPUT)
endif

VALID_SIMS = verilator vcs

check-sim-valid:
ifeq ($(filter $(SIM),$(VALID_SIMS)),)
	@printf "$rError: Invalid SIM '$(SIM)'. Must be one of {verilator, vcs}.$n\n"
	@exit 1
endif

check-test-defined:
ifeq ($(strip $(TEST)),)
	@printf "$rError: Variable $bTEST$n$r was not specified.\n$n"
	@exit 1
endif

$(OUTPUT):
	@mkdir -p $@

clean:
	@rm -rf $(OUTPUT_BASE_DIR)

veryclean: clean assemble-veryclean

################################################################################
# RISC-V Toolchain
################################################################################

# Auto-detect the toolchain prefix when not pinned in config.mk. All builds
# use -mabi=ilp32 with -march=$(RISCV_ARCH) (.S) or -march=$(RISCV_ARCH_C)
# (.c), so any rv32-capable prefix works.
ifeq ($(strip $(RISCV_PREFIX)),)
    RISCV_PREFIX := $(firstword $(foreach p,$(RISCV_TOOLCHAIN_CANDIDATES),\
            $(if $(shell command -v $(p)gcc 2> /dev/null),$(p))))
endif

RISCV_CC = $(RISCV_PREFIX)gcc
RISCV_OBJCOPY = $(RISCV_PREFIX)objcopy
RISCV_OBJDUMP = $(RISCV_PREFIX)objdump

.PHONY: toolchain assemble-check-compiler
toolchain:
	@if [ -z "$(RISCV_PREFIX)" ]; then \
		printf "$rNo RISC-V toolchain found in PATH.$n\n"; exit 1; \
	fi
	@printf "RISC-V toolchain: $b$(RISCV_PREFIX)$n ($$(command -v $(RISCV_CC)))\n"
	@$(RISCV_CC) --version | head -1

assemble-check-compiler:
ifeq ($(shell command -v $(RISCV_CC) 2> /dev/null),)
	@printf "$rError: No RISC-V compiler found. Searched prefixes: "
	@printf "$(RISCV_TOOLCHAIN_CANDIDATES).\n"
	@printf "Install a toolchain or set RISCV_PREFIX in config.mk.$n\n"
	@exit 1
endif

################################################################################
# Assemble Test Programs
################################################################################

.PHONY: assemble assemble-clean assemble-veryclean assemble-check-test \
		assemble-check-extension

RISCV_ENTRY_POINT = main

RUNTIME_DIR = runtime
RISCV_STARTUP_FILE = $(RUNTIME_DIR)/crt0.S
RISCV_LINKER_SCRIPT = $(RUNTIME_DIR)/test_program.ld

# Per-directory default optimization level, overridden by OPT
ifeq ($(strip $(OPT)),)
    ifeq ($(dir $(TEST)),tests/perf/)
        TEST_OPT = -O0
    else
        TEST_OPT = -O
    endif
else
    TEST_OPT = $(OPT)
endif

RISCV_CFLAGS = -static -nostdlib -nostartfiles -mabi=ilp32 -Wall \
		-Wextra -std=c11 -pedantic -g -Werror=implicit-function-declaration \
		$(RISCV_CFLAGS_EXTRA)
# -march is per-source-language: hand-written .S tests assemble with
# RISCV_ARCH (rv32im, so the class mul tests can encode MUL), while C is
# compiled for RISCV_ARCH_C (rv32i) so the compiler never emits M-extension
# instructions that neither core decodes. See config.mk.
RISCV_C_ONLY_FLAGS = -march=$(RISCV_ARCH_C) $(TEST_OPT) -fno-inline
RISCV_AS_ONLY_FLAGS = -march=$(RISCV_ARCH)

# Headers living alongside the test, as build prerequisites (see the .elf
# rule). Directory-granular rather than per-#include, which is enough here
# and needs no depfile machinery.
TEST_HEADERS = $(wildcard $(dir $(TEST))*.h)
RISCV_AS_LDFLAGS = -Wl,-e$(RISCV_ENTRY_POINT)
RISCV_LDFLAGS = -Wl,-T$(RISCV_LINKER_SCRIPT) -lgcc

RISCV_OBJCOPY_FLAGS = -O binary
RISCV_OBJDUMP_FLAGS = -d -M numeric,no-aliases $(addprefix -j ,.text .ktext \
		.data .bss .kdata .kbss)

ELF_EXTENSION = elf
BINARY_EXTENSION = bin
DISAS_EXTENSION = disassembly.s

TEST_NAME = $(basename $(TEST))
BIN_SECTIONS = $(addsuffix .$(BINARY_EXTENSION),text data ktext kdata)
TEST_BIN = $(addprefix $(TEST_NAME).,$(BIN_SECTIONS))

# The binary names in the output directory, expected by the testbench
OUTPUT_NAME = $(OUTPUT)/mem
TEST_OUTPUT_BIN = $(addprefix $(OUTPUT_NAME).,$(BIN_SECTIONS))

TEST_EXECUTABLE = $(addsuffix .$(ELF_EXTENSION), $(TEST_NAME))
TEST_DISASSEMBLY = $(addsuffix .$(DISAS_EXTENSION), $(TEST_NAME))

ASSEMBLE_LOG = $(OUTPUT)/assemble.log

# Always re-copy binaries, as TEST changes based on user input
.PHONY: $(TEST_OUTPUT_BIN)
.PRECIOUS: %.$(ELF_EXTENSION)

assemble: $(TEST) $(TEST_OUTPUT_BIN) $(TEST_DISASSEMBLY) | check-test-defined \
		assemble-check-extension

$(TEST_OUTPUT_BIN): $(OUTPUT_NAME).%.$(BINARY_EXTENSION): \
		$(TEST_NAME).%.$(BINARY_EXTENSION) | $(OUTPUT)
	@cp $^ $@

$(TEST_NAME).%.$(BINARY_EXTENSION): $(TEST_EXECUTABLE) | $(OUTPUT) \
		check-test-defined
	@$(RISCV_OBJCOPY) $(RISCV_OBJCOPY_FLAGS) -j .$* $^ $@ |& \
			tee -a $(ASSEMBLE_LOG)

# The .bss/.kbss sections are concatenated with their data sections
$(TEST_NAME).data.$(BINARY_EXTENSION): $(TEST_EXECUTABLE)
	@$(RISCV_OBJCOPY) $(RISCV_OBJCOPY_FLAGS) -j .data -j .bss \
			--set-section-flags .bss=alloc,load,contents $^ $@

$(TEST_NAME).kdata.$(BINARY_EXTENSION): $(TEST_EXECUTABLE)
	@$(RISCV_OBJCOPY) $(RISCV_OBJCOPY_FLAGS) -j .kdata -j .kbss \
			--set-section-flags .kbss=alloc,load,contents $^ $@

%.$(DISAS_EXTENSION): %.$(ELF_EXTENSION) | $(OUTPUT)
	@$(RISCV_OBJDUMP) $(RISCV_OBJDUMP_FLAGS) $^ > $@ |& tee -a $(ASSEMBLE_LOG)

%.$(ELF_EXTENSION): %.S $(RISCV_LINKER_SCRIPT) | $(OUTPUT) \
		assemble-check-compiler assemble-check-test
	@printf "Assembling test $u$<$n into binary files...\n"
	@$(RISCV_CC) $(RISCV_CFLAGS) $(RISCV_AS_ONLY_FLAGS) $< $(RISCV_LDFLAGS) \
			$(RISCV_AS_LDFLAGS) -o $@ \
			|& tee $(ASSEMBLE_LOG)

# The trailing $(TEST_HEADERS) keeps the committed .elf/.bin from going stale
# when a header next to the test changes (tests/perf/*.c pull their data sets
# in that way). It stays out of $(wordlist 1,2,$^), which selects crt0.S + .c.
%.$(ELF_EXTENSION): $(RISCV_STARTUP_FILE) %.c $(RISCV_LINKER_SCRIPT) \
		$(TEST_HEADERS) | $(OUTPUT) assemble-check-compiler assemble-check-test
	@printf "Assembling test $u$(word 2,$^)$n into binary files ($(TEST_OPT))...\n"
	@$(RISCV_CC) $(RISCV_CFLAGS) $(RISCV_C_ONLY_FLAGS) $(wordlist 1,2,$^) \
			$(RISCV_LDFLAGS) -o $@ |& tee $(ASSEMBLE_LOG)

$(TEST): | assemble-check-extension assemble-check-test

assemble-clean:
	@rm -f $(TEST_OUTPUT_BIN) $(ASSEMBLE_LOG)

assemble-veryclean: assemble-clean
	@printf "Cleaning up assembled binary files in the project directory...\n"
	@rm -f $$(find -L tests -name '*.$(BINARY_EXTENSION)' \
			-o -name '*.$(ELF_EXTENSION)' -o -name '*.$(DISAS_EXTENSION)')

assemble-check-test:
ifeq ($(wildcard $(TEST)),)
	@printf "$rError: $u$(TEST)$n$r: RISC-V test file does not exist.$n\n"
	@exit 1
endif

assemble-check-extension:
ifeq ($(filter %.c %.S,$(TEST)),)
	@printf "$rError: $u$(TEST)$n$r: RISC-V test file does not have a .c or .S "
	@printf "extension.$n\n"
	@exit 1
endif

################################################################################
# RTL Sources
################################################################################

# Auto-discovery: adding a file requires no Makefile edits. Directory order
# matters for package compilation (packages must precede their importers),
# and the 0/1 filename prefixes keep package files first within a directory.
RTL_DIR_ORDER = rtl/core rtl/ooo rtl/mem tb
SV_SRC := $(foreach d,$(RTL_DIR_ORDER),$(sort $(shell find -L $(d) -type f -name '*.sv')))

# Core selection (CORE in config.mk): both riscv_core_interface*.sv files
# define the same module name, so exactly one may be compiled.
ifeq ($(CORE),inorder)
    SV_SRC := $(filter-out rtl/mem/riscv_core_interface.sv,$(SV_SRC))
else ifeq ($(CORE),lightning)
    SV_SRC := $(filter-out rtl/mem/riscv_core_interface_inorder.sv,$(SV_SRC))
else
    $(error Invalid CORE '$(CORE)'. Must be one of {lightning, inorder})
endif
VH_SRC := $(sort $(shell find -L rtl tb -type f -name '*.vh'))
INC_DIRS := $(sort $(shell find -L rtl tb -type d)) $(SIM_OUTPUT)

################################################################################
# Compile the Simulator
################################################################################

.PHONY: build build-check-verilator build-check-vcs

SIM_EXECUTABLE = sim
SIM_COMPILE_LOG = compilation.log

# Common defines for both backends. (The old TRACE=1 / DEBUG_RFWRTRACE
# write-event trace check was superseded by `make verify-trace`.)
SIM_DEFINES = +define+SIMULATION_18447 $(PARAMS)

# --- Verilator backend ---------------------------------------------------
VERILATOR ?= verilator
VLT_OBJ_DIR = $(SIM_OUTPUT)/obj_dir
VLT_INC_FLAGS = $(addprefix +incdir+,$(abspath $(INC_DIRS)))
VLT_FLAGS = --binary --timing -j $(CORES) --top-module top \
		-Wall -Wno-fatal \
		-Mdir $(VLT_OBJ_DIR) -o ../$(SIM_EXECUTABLE) \
		$(SIM_DEFINES) $(VLT_INC_FLAGS) $(VERILATOR_EXTRA)
ifneq ($(strip $(SEED)),)
    VLT_FLAGS += --x-assign unique --x-initial unique
endif
ifeq ($(WAVES),1)
    VLT_FLAGS += --trace-fst --trace-structs
endif

# --- VCS backend ----------------------------------------------------------
VCS = vcs
VCS_FLAGS_BASE = -sverilog -q -j $(THREADS) +warn=all \
		+lint=PCWM,IWU,TFIPC,ONGS,VNGS,IRIMW,UI,CAWM-L +error+20 \
		-xzcheck nofalseneg $(SIM_DEFINES) $(VCS_EXTRA)
VCS_DEBUG_FLAGS = -debug_acc+all -debug_region+cell+encrypt +memcbk
VCS_FLAGS = $(VCS_FLAGS_BASE)
ifeq ($(WAVES),1)
    VCS_FLAGS += $(VCS_DEBUG_FLAGS)
endif
VCS_INC_FLAGS = $(addprefix +incdir+,$(abspath $(INC_DIRS)))

# Rebuild automatically whenever the build configuration changes (PARAMS,
# SEED, WAVES, SIM, CORE, ...), not just when sources change.
BUILD_FLAGS_ID = $(SIM)|$(CORE)|$(SIM_DEFINES)|$(SEED)|$(WAVES)
FLAGS_STAMP = $(SIM_OUTPUT)/.buildflags

$(FLAGS_STAMP): FORCE | $(OUTPUT)
	@mkdir -p $(SIM_OUTPUT)
	@echo '$(BUILD_FLAGS_ID)' | cmp -s - $@ || echo '$(BUILD_FLAGS_ID)' > $@

build: $(SIM_OUTPUT)/$(SIM_EXECUTABLE)

ifeq ($(SIM),verilator)
$(SIM_OUTPUT)/$(SIM_EXECUTABLE): $(SV_SRC) $(VH_SRC) $(FLAGS_STAMP) | $(OUTPUT) \
		check-sim-valid build-check-verilator
	@printf "Compiling design with Verilator into $u$(SIM_OUTPUT)$n...\n"
	@$(VERILATOR) $(VLT_FLAGS) $(abspath $(SV_SRC)) \
			|& tee $(SIM_OUTPUT)/$(SIM_COMPILE_LOG)
	@printf "The simulator executable is at $u$@$n.\n"
else
$(SIM_OUTPUT)/$(SIM_EXECUTABLE): $(SV_SRC) $(VH_SRC) $(FLAGS_STAMP) | $(OUTPUT) \
		check-sim-valid build-check-vcs
	@printf "Compiling design with VCS into $u$(SIM_OUTPUT)$n...\n"
	@cd $(SIM_OUTPUT) && $(VCS) $(VCS_FLAGS) $(VCS_INC_FLAGS) \
			$(abspath $(SV_SRC)) -o $(SIM_EXECUTABLE) |& tee $(SIM_COMPILE_LOG)
	@printf "The simulator executable is at $u$@$n.\n"
endif

build-check-verilator:
ifeq ($(shell command -v $(VERILATOR) 2> /dev/null),)
	@printf "$rError: $u$(VERILATOR)$n$r was not found in your PATH.$n\n"
	@exit 1
endif

build-check-vcs:
ifeq ($(shell command -v $(VCS) 2> /dev/null),)
	@printf "$rError: $u$(VCS)$n$r was not found in your PATH (VCS is only "
	@printf "available on the AFS/class machines).$n\n"
	@exit 1
endif

################################################################################
# Simulate
################################################################################

.PHONY: sim sim-gui waves

SIM_REGDUMP = $(OUTPUT)/simulation.reg
SIM_LOG = simulation.log
FAILED_SIMS = $(OUTPUT_BASE_DIR)/failed_sims

# Runtime arguments for the simulator
SIM_RUN_ARGS =
ifeq ($(SIM),verilator)
ifneq ($(strip $(SEED)),)
    SIM_RUN_ARGS += +verilator+seed+$(SEED)
endif
ifeq ($(WAVES),1)
    SIM_RUN_ARGS += +waves
endif
endif

# User-specified runtime plusargs (e.g. PLUSARGS=+commit_trace). Runtime
# only — no rebuild needed, so not part of BUILD_FLAGS_ID.
SIM_RUN_ARGS += $(PLUSARGS)

# Always re-run: the specified test can change based on user input
.PHONY: $(SIM_REGDUMP)

sim: $(SIM_REGDUMP) | assemble check-test-defined

$(SIM_REGDUMP): $(TEST) $(TEST_OUTPUT_BIN) $(SIM_OUTPUT)/$(SIM_EXECUTABLE) \
		| $(OUTPUT) assemble
	@printf "Simulating test $u$(TEST)$n in $u$(OUTPUT)$n...\n"
	@rm -f $(SIM_REGDUMP)   # a watchdog-killed run must not inherit a stale dump
	@cd $(OUTPUT) && ./$(SIM_EXECUTABLE) $(SIM_RUN_ARGS) |& tee $(SIM_LOG)
	@printf "\nThe simulator register dump is at $u$(SIM_REGDUMP)$n\n"

# Waveform viewing. Verilator: FST dump + gtkwave. VCS: DVE GUI.
ifeq ($(SIM),verilator)
waves: | check-test-defined
	@$(MAKE) --no-print-directory sim TEST=$(TEST) WAVES=1
	@printf "Opening $u$(OUTPUT)/waves.fst$n in gtkwave...\n"
	@gtkwave $(OUTPUT)/waves.fst &> /dev/null &
else
waves: sim-gui
endif

sim-gui: $(TEST) $(TEST_OUTPUT_BIN) | assemble check-test-defined
	@$(MAKE) --no-print-directory build WAVES=1
	@printf "Starting up the simulator gui in $u$(OUTPUT)$n...\n"
	@cd $(OUTPUT) && ./$(SIM_EXECUTABLE) -gui &
	@sleep 2

################################################################################
# Verify
################################################################################

.PHONY: verify regress verify-check-ref-regdump

VERIFY_SCRIPT = sdiff
VERIFY_OPTIONS = --ignore-all-space --ignore-blank-lines

# The reference register dump for the test. With OPT=-O3, an <name>.O3.reg
# oracle is used when present (the old benchmarksO3 dumps).
REF_REGDUMP = $(TEST_NAME).reg
ifeq ($(strip $(OPT)),-O3)
    ifneq ($(wildcard $(TEST_NAME).O3.reg),)
        REF_REGDUMP = $(TEST_NAME).O3.reg
    endif
endif

verify: $(SIM_REGDUMP) $(REF_REGDUMP) | assemble verify-check-ref-regdump \
		check-test-defined
	@printf "\n"
	@if grep -q '^TIMEOUT:' $(OUTPUT)/$(SIM_LOG) 2> /dev/null; then \
		printf "$rIncorrect! The core never halted — the watchdog cut the "; \
		printf "run off after $bLTG_MAX_SIM_CYCLES$n$r cycles. The dump at "; \
		printf "$u$(SIM_REGDUMP)$n$r is its architectural state at the "; \
		printf "cutoff, not a finished program.$n\n"; \
		exit 1; \
	fi
	@if $(VERIFY_SCRIPT) $(VERIFY_OPTIONS) $^ &> /dev/null; then \
		printf "$gCorrect! The simulator register dump matches the "; \
		printf "reference.$n\n"; \
	else \
		printf "\n%-67s\t%s\n\n" "$u$(SIM_REGDUMP)$n" "$u$(REF_REGDUMP)$n"; \
		$(VERIFY_SCRIPT) $(VERIFY_OPTIONS) $^; \
		printf "$rIncorrect! The simulator register dump does not match the "; \
		printf "reference.$n\n"; \
		exit 1; \
	fi

# Suppresses 'no rule to make...' when the REF_REGDUMP doesn't exist
$(REF_REGDUMP):

verify-check-ref-regdump:
ifeq ($(wildcard $(REF_REGDUMP)),)
	@printf "$rError: $u$(REF_REGDUMP)$n$r: Reference register dump for test "
	@printf "$u$(TEST)$n$r does not exist.\n$n"
	@exit 1
endif

# The regression suite: every test source with a committed .reg oracle,
# unless TESTS was given explicitly.
ifeq ($(strip $(TESTS)),)
    TESTS := $(foreach t,\
            $(sort $(wildcard $(addsuffix /*.S,$(REGRESS_DIRS))) \
                   $(wildcard $(addsuffix /*.c,$(REGRESS_DIRS)))),\
            $(if $(wildcard $(basename $(t)).reg),$(t)))
endif

regress:
	@printf "%-40s %s\n" "Test" "Result"
	@printf "%.0s-" {1..47}
	@printf "\n"
	@mkdir -p "$(OUTPUT)"
	@fails=0; for test in $(TESTS); do \
		BASENAME=$${test} && BASENAME=$${BASENAME%.*}; \
		printf "$b%-36s %s$n" "$${test}" "Running..."; \
		rm -rf "$(FAILED_SIMS)/$${BASENAME}"; \
		$(MAKE) --no-print-directory verify TEST=$${test} OUTPUT=$(OUTPUT) \
				&> $(OUTPUT)/verify.log; \
		if [ $$? -eq 0 ]; then \
			printf "\r$g%-40s %s$n\n" "$${test}" "Passed"; \
		else \
			fails=$$((fails+1)); \
			printf "\r$r%-40s %s$n\n" "$${test}" "Failed"; \
			mkdir -p "$(FAILED_SIMS)/$${BASENAME}"; \
			cp "$(OUTPUT)"/*.log "$(OUTPUT)"/simulation.reg \
					"$(FAILED_SIMS)/$${BASENAME}/" 2>/dev/null; \
		fi; \
	done; \
	printf "%.0s-" {1..47}; printf "\n"; \
	if [ $$fails -eq 0 ]; then \
		printf "$gAll $$(echo $(TESTS) | wc -w) tests passed.$n\n"; \
	else \
		printf "$r$$fails test(s) failed. Logs are in $(FAILED_SIMS)/.$n\n"; \
		exit 1; \
	fi

################################################################################
# Lint
################################################################################

.PHONY: lint

# Documented waivers live in lint.vlt; run `make lint LINT_WAIVERS=` to see
# everything.
LINT_WAIVERS ?= lint.vlt

lint:
	@printf "Linting with $bverilator --lint-only -Wall$n...\n"
	@$(VERILATOR) --lint-only --timing -Wall -Wno-fatal --top-module top \
			$(SIM_DEFINES) $(VLT_INC_FLAGS) $(abspath $(LINT_WAIVERS)) \
			$(abspath $(SV_SRC))
	@printf "$gLint completed.$n\n"

################################################################################
# Reference Simulator (in-repo C ILS at tools/refsim; override
# REFSIM_EXECUTABLE in config.mk for the AFS class binary)
################################################################################

.PHONY: refsim refdump

REFSIM_REGDUMP = refdump.reg

refsim: $(REFSIM_EXECUTABLE) $(TEST) | assemble check-test-defined
	@printf "Running reference sim on test $u$(TEST)$n...\n"
	@$(REFSIM_EXECUTABLE) $(TEST)

refdump: $(TEST_BIN) $(REFSIM_EXECUTABLE) $(TEST) | assemble
	@printf "Generating refdump.reg from reference sim on test $u$(TEST)$n...\n"
	@printf "go\nrdump $(REFSIM_REGDUMP)\n" | $(REFSIM_EXECUTABLE) $(TEST)

################################################################################
# Verify-trace: per-commit architectural state compare vs the reference sim
# (see docs/TODO-verify-trace.md and README). The core emits a commit packet
# per retired instruction; the tb reconstructs full register state per commit
# (+commit_trace -> commit_trace.txt) and the refsim writes the same format
# (statetrace command); the checker reports the first divergent commit.
################################################################################

.PHONY: reftrace verify-trace

REF_STATETRACE = $(OUTPUT)/reftrace.txt
RTL_COMMIT_TRACE = $(OUTPUT)/commit_trace.txt
TRACE_CHECKER = python3 scripts/check_commit_trace.py

reftrace: $(TEST_BIN) $(REFSIM_EXECUTABLE) $(TEST) | $(OUTPUT) assemble \
		check-test-defined
	@printf "Generating $u$(REF_STATETRACE)$n from reference sim on test $u$(TEST)$n...\n"
	@printf "statetrace $(abspath $(REF_STATETRACE))\ngo\nquit\n" | \
			$(REFSIM_EXECUTABLE) $(TEST)

verify-trace: reftrace | check-test-defined
	@rm -f $(RTL_COMMIT_TRACE)  # a run without tracing must not leave a stale trace
	@$(MAKE) --no-print-directory sim TEST=$(TEST) OUTPUT=$(OUTPUT) \
			PLUSARGS='$(PLUSARGS) +commit_trace'
	@printf "\nComparing the RTL commit trace against the reference state trace...\n"
	@if $(TRACE_CHECKER) $(RTL_COMMIT_TRACE) $(REF_STATETRACE); then \
		printf "$gCorrect! The RTL commit trace matches the reference.$n\n"; \
	else \
		printf "\n%-67s\t%s\n" "$u$(RTL_COMMIT_TRACE)$n" "$u$(REF_STATETRACE)$n"; \
		printf "(view with $bscripts/view_commit_trace.py <trace>$n)\n"; \
		printf "$rIncorrect! The RTL commit trace diverges from the reference.$n\n"; \
		exit 1; \
	fi

################################################################################
# Verify-mem: per-memory-op compare vs the reference sim. Where verify-trace
# checks architectural *register* state, this checks what actually reached data
# memory: every committed load/store's address, byte lanes and data, in commit
# order. Divergences are classified as missing / extra / out-of-order / wrong
# value, which is where an OoO core's memory bugs live.
#
# The core-side drives are `ifdef DEBUG (they cost an address field per
# in-flight instruction), so this builds with +define+DEBUG; the flags stamp
# rebuilds automatically when switching in and out of it.
################################################################################

.PHONY: refmemtrace verify-mem

REF_MEM_TRACE = $(OUTPUT)/refmemtrace.txt
RTL_MEM_TRACE = $(OUTPUT)/mem_trace.txt
MEM_CHECKER = python3 scripts/check_mem_trace.py

refmemtrace: $(TEST_BIN) $(REFSIM_EXECUTABLE) $(TEST) | $(OUTPUT) assemble \
		check-test-defined
	@printf "Generating $u$(REF_MEM_TRACE)$n from reference sim on test $u$(TEST)$n...\n"
	@printf "memtrace $(abspath $(REF_MEM_TRACE))\ngo\nquit\n" | \
			$(REFSIM_EXECUTABLE) $(TEST)

verify-mem: refmemtrace | check-test-defined
	@rm -f $(RTL_MEM_TRACE)  # a run without tracing must not leave a stale trace
	@$(MAKE) --no-print-directory sim TEST=$(TEST) OUTPUT=$(OUTPUT) \
			PARAMS='$(PARAMS) +define+DEBUG' \
			PLUSARGS='$(PLUSARGS) +mem_trace'
	@printf "\nComparing the RTL memory trace against the reference...\n"
	@if $(MEM_CHECKER) $(RTL_MEM_TRACE) $(REF_MEM_TRACE); then \
		printf "$gCorrect! The RTL memory operations match the reference.$n\n"; \
	else \
		printf "\n%-67s\t%s\n" "$u$(RTL_MEM_TRACE)$n" "$u$(REF_MEM_TRACE)$n"; \
		printf "$rIncorrect! The RTL memory operations diverge from the reference.$n\n"; \
		exit 1; \
	fi

# The in-repo reference simulator is built on demand; any other path
# (e.g. the AFS class binary) must already exist.
$(REFSIM_LOCAL): $(wildcard tools/refsim/*.c tools/refsim/*/*.c \
		tools/refsim/*/*.h tools/refsim/Makefile)
	@$(MAKE) --no-print-directory -C tools/refsim

ifneq ($(REFSIM_EXECUTABLE),$(REFSIM_LOCAL))
$(REFSIM_EXECUTABLE):
	@printf "$rError: $u$(REFSIM_EXECUTABLE)$n$r not found. Set "
	@printf "REFSIM_EXECUTABLE to a valid reference simulator (default "
	@printf "is the in-repo $u$(REFSIM_LOCAL)$n).$n\n"
	@exit 1
endif

################################################################################
# Synthesize (Design Compiler; VCS/DC hosts only)
################################################################################

SYNTH_CC = dc_shell-xg-t
SYNTH_SCRIPT = synth/dc_synth.tcl
DC_SCRIPT := $(shell readlink -m $(SYNTH_SCRIPT))

TIMING_REPORT = timing_riscv_core.rpt
POWER_REPORT = power_riscv_core.rpt
AREA_REPORT = area_riscv_core.rpt
REPORTS = $(TIMING_REPORT) $(POWER_REPORT) $(AREA_REPORT)
NETLIST = netlist_riscv_core.sv
SYNTH_REPORTS = $(addprefix $(OUTPUT)/,$(REPORTS) $(NETLIST))
SYNTH_LOG = synthesis.log

ifneq ($(strip $(CLOCK_PERIOD)),)
    SET_CLOCK_PERIOD = ; set clock_period $(CLOCK_PERIOD)
endif

.PHONY: synth view-timing view-power view-area synth-clean synth-check-compiler \
		synth-check-script

synth: $(SYNTH_REPORTS)

$(SYNTH_REPORTS): $(SV_SRC) $(VH_SRC) $(DC_SCRIPT) | $(OUTPUT) \
		synth-check-compiler synth-check-script
	@printf "Synthesizing design in $u$(OUTPUT)$n..."
	@cd $(OUTPUT) && $(SYNTH_CC) -f $(DC_SCRIPT) -x "set project_dir $(PWD); \
		set lab_18447 4a$(SET_CLOCK_PERIOD)" |& tee $(SYNTH_LOG)
	@printf "\nThe timing report is at $u$(OUTPUT)/$(TIMING_REPORT)$n\n"
	@if grep -i latch $(OUTPUT)/$(SYNTH_LOG) &> /dev/null; then \
		printf "$r$bFound disallowed latch inference:$n\n"; \
		grep -i latch $(OUTPUT)/$(SYNTH_LOG); \
	else \
		printf "No latches found in $u$(OUTPUT)/$(SYNTH_LOG)$n\n"; \
	fi

view-timing view-power view-area: view-%:
	@if [ ! -e $(OUTPUT)/$($(shell echo $* | tr a-z A-Z)_REPORT) ]; then \
		$(MAKE) OUTPUT=$(OUTPUT) synth; \
	fi
	@cat $(OUTPUT)/$($(shell echo $* | tr a-z A-Z)_REPORT)

synth-clean:
	@rm -rf $(SYNTH_OUTPUT)

synth-check-compiler:
ifeq ($(shell command -v $(SYNTH_CC) 2> /dev/null),)
	@printf "$rError: $u$(SYNTH_CC)$n$r was not found in your PATH (DC is only "
	@printf "available on the AFS/class machines).$n\n"
	@exit 1
endif

synth-check-script:
ifeq ($(wildcard $(DC_SCRIPT)),)
	@printf "$rError: $u$(SYNTH_SCRIPT)$n$r does not resolve (it is an "
	@printf "AFS-hosted script; synthesis only works on CMU machines).$n\n"
	@exit 1
endif

################################################################################
# Help
################################################################################

.PHONY: help

help:
	@printf "$blightning Makefile Usage:$n\n"
	@printf "\tmake [$uvariable$n ...] $utarget$n\n"
	@printf "\n"
	@printf "$bTargets:$n\n"
	@printf "\t$bverify$n    Run $bTEST$n and diff its register dump against\n"
	@printf "\t          the committed <test>.reg oracle.\n"
	@printf "\t$bverify-trace$n  Compare full architectural register state per\n"
	@printf "\t          committed instruction against the reference sim\n"
	@printf "\t          (see README; needs a core that emits commit packets).\n"
	@printf "\t$breftrace$n  Generate the reference per-commit state trace only.\n"
	@printf "\t$bverify-mem$n  Compare every committed memory operation (address,\n"
	@printf "\t          byte lanes, data) against the reference sim, reporting\n"
	@printf "\t          missing / extra / out-of-order / wrong-value ops.\n"
	@printf "\t          Builds with $b+define+DEBUG$n (the core-side seam).\n"
	@printf "\t$brefmemtrace$n  Generate the reference memory-op trace only.\n"
	@printf "\t$bregress$n   Run verify on every test with a .reg oracle\n"
	@printf "\t          (or on $bTESTS$n if given).\n"
	@printf "\t$bsim$n       Run $bTEST$n without verification.\n"
	@printf "\t$bwaves$n     Run $bTEST$n with waveform capture and open the\n"
	@printf "\t          viewer (gtkwave for verilator, DVE for vcs).\n"
	@printf "\t$bbuild$n     Compile the RTL into a simulator executable.\n"
	@printf "\t$blint$n      verilator --lint-only -Wall over the full design.\n"
	@printf "\t$bassemble$n  Assemble $bTEST$n into section binaries + disassembly.\n"
	@printf "\t$btoolchain$n Show which RISC-V toolchain was detected.\n"
	@printf "\t$brefsim$n / $brefdump$n  Run the reference C simulator (in-repo tools/refsim;\n"
	@printf "\t          set REFSIM_EXECUTABLE for the AFS class binary).\n"
	@printf "\t$bsynth$n     Design Compiler synthesis (CMU only).\n"
	@printf "\t$bclean$n / $bveryclean$n  Remove outputs / also test artifacts.\n"
	@printf "\n"
	@printf "$bVariables:$n (persistent defaults live in $uconfig.mk$n)\n"
	@printf "\t$bTEST$n      Test program to run (.S or .c).\n"
	@printf "\t$bSIM$n       Simulator backend: verilator (default) or vcs.\n"
	@printf "\t$bOPT$n       C optimization level (-O3 also selects .O3.reg oracles).\n"
	@printf "\t$bPARAMS$n    Hardware overrides, e.g. '+define+LTG_DRIS_ENTRIES=32'\n"
	@printf "\t          (all knobs: $urtl/include/config.vh$n).\n"
	@printf "\t$bSEED$n      Verilator X-shakeout seed (--x-assign/--x-initial unique).\n"
	@printf "\t$bCORE$n      Core to wrap: lightning (default) or inorder.\n"
	@printf "\t$bPLUSARGS$n  Extra runtime plusargs, e.g. '+commit_trace'.\n"
	@printf "\t$bRISCV_PREFIX$n  Toolchain prefix (auto-detected when empty).\n"
	@printf "\n"
	@printf "$bExamples:$n\n"
	@printf "\tmake verify TEST=tests/asm/additest.S\n"
	@printf "\tmake verify TEST=tests/c/fibi.c OPT=-O3\n"
	@printf "\tmake verify TEST=tests/custom/wbevict.S SIM=vcs\n"
	@printf "\tmake regress\n"
	@printf "\tmake regress TESTS='tests/asm/*.S'\n"
	@printf "\tmake waves TEST=tests/asm/additest.S\n"
	@printf "\tmake verify-trace TEST=tests/asm/brtest0.S CORE=inorder\n"
	@printf "\tmake verify TEST=... PARAMS='+define+LTG_DCACHE_INDEX_BITS=6'\n"

FORCE:

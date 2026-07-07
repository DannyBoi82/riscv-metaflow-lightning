# tools/refsim — RV32I instruction-level reference simulator
#
# Vendored from the 18-447 lab1a simulator (CMU starter shell + the otters
# instruction-execution core, post bug-fix pass 2026-07-07: JAL imm[11],
# SLL operand order, SB/SH byte-lane masking, JALR rd==rs1; see the
# lab1a-otters repo history and ../../docs/porting-log.md).
#
# Produces register dumps in the exact .reg oracle format used by the
# class reference simulator, so `make refdump` output diffs cleanly
# against committed oracles and RTL simulation dumps.
#
# Normally built via the top-level Makefile ($(REFSIM_EXECUTABLE) rule);
# standalone: `make -C tools/refsim`.

CC = gcc
# -fcommon: shell/commands.h defines SIGINT_RECEIVED without extern; GCC 10+
# defaults to -fno-common and rejects the duplicate definitions.
CFLAGS = -Wall -Wextra -std=gnu11 -pedantic -g -O2 -fcommon \
		-Werror=implicit-function-declaration
INCLUDES = -I include -I shell -I .

# readline: prefer the system copy; fall back to a conda (miniforge)
# installation when the dev headers aren't installed system-wide.
ifneq ($(wildcard /usr/include/readline/readline.h),)
    READLINE_FLAGS = -l readline
else ifneq ($(wildcard $(HOME)/miniforge3/include/readline/readline.h),)
    INCLUDES += -I $(HOME)/miniforge3/include
    READLINE_FLAGS = -L $(HOME)/miniforge3/lib \
		-Wl,-rpath,$(HOME)/miniforge3/lib -l readline
else
    $(error readline headers not found (system or ~/miniforge3); \
		install libreadline-dev or set READLINE_FLAGS/INCLUDES manually)
endif

SRC = $(wildcard shell/*.c) sim.c
HDR = $(wildcard shell/*.h include/*.h)

riscv-refsim: $(SRC) $(HDR)
	$(CC) $(CFLAGS) $(INCLUDES) $(SRC) -o $@ $(READLINE_FLAGS)

.PHONY: clean
clean:
	rm -f riscv-refsim

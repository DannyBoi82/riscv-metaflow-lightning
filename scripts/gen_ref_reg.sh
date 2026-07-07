#!/bin/bash
# gen_ref_reg.sh — generate a reference .reg dump for a given test file
# Usage: scripts/gen_ref_reg.sh <path/to/test.S or path/to/test.c>
# Run from the repository root. Uses the in-repo C reference simulator
# (tools/refsim, built on demand); set REFSIM to point elsewhere (e.g. the
# AFS class binary), matching config.mk's REFSIM_EXECUTABLE.
#
# Build system notes:
#   - Test programs are compiled into an ELF executable (<test_name>.elf)
#     using the RISC-V GCC toolchain (auto-detected by the Makefile).
#   - The linker script at runtime/test_program.ld maps program memory into
#     4 sections:
#       .text  — user code and read-only globals
#       .ktext — kernel code and read-only globals
#       .data  — user writable globals (includes .bss)
#       .kdata — kernel writable globals (includes .kbss)
#   - The reference simulator operates on the assembled binary, so the
#     test must be compilable before this script produces a valid dump.
#
# NOTE: .reg oracles for C tests are coupled to the compiling toolchain's
# codegen (caller-saved register residue differs between compilers). Dumps
# generated here match binaries built by the same toolchain the Makefile
# picked — see docs/porting-log.md (2026-07-07).

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <path/to/test.S or path/to/test.c>"
    exit 1
fi

INPUT="$1"
BASENAME="${INPUT%.*}"
REFSIM="${REFSIM:-tools/refsim/riscv-refsim}"

# Build the in-repo reference simulator on demand
if [ "$REFSIM" = "tools/refsim/riscv-refsim" ] && [ ! -f "$REFSIM" ]; then
    make -C tools/refsim
fi

if [ ! -f "$INPUT" ]; then
    echo "Error: $INPUT does not exist"
    exit 1
fi

if [[ "$INPUT" != *.S && "$INPUT" != *.c ]]; then
    echo "Error: $INPUT does not have a .S or .c extension"
    exit 1
fi

if [ ! -f "$REFSIM" ]; then
    echo "Error: reference simulator not found at $REFSIM"
    echo "(set REFSIM=<path> to override, e.g. the AFS class binary)"
    exit 1
fi

# Build the test binaries the reference simulator consumes
make assemble TEST="$INPUT"

printf "go\nrdump %s.reg\n" "$BASENAME" | "$REFSIM" "$INPUT"
echo "Written to ${BASENAME}.reg"

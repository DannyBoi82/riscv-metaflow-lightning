#!/usr/bin/env python3
"""
view_commit_trace.py — human-friendly viewer for verify-trace files.

The compact trace format (one line per committed instruction: pc + x1..x31
in hex, optional '#' comment) is the single source of truth that gets
diffed; this script is only a pretty-printer over it. By default each commit
prints as one row showing the PC and the registers that *changed* at that
commit; --full instead dumps the complete 32-register state per commit
(only sensible for short tests).

Works on both the RTL trace (commit_trace.txt; cycle/time/insn read from its
comments) and refsim statetrace files.
"""

import argparse
import re
import sys

ABI_NAMES = [
    "zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
    "s0/fp", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
    "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
    "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6",
]

NUM_FIELDS = 32  # pc + x1..x31


def main():
    parser = argparse.ArgumentParser(
        description="Pretty-print a verify-trace commit trace.")
    parser.add_argument("trace", help="commit_trace.txt or refsim statetrace")
    parser.add_argument("--full", action="store_true",
                        help="dump full register state per commit instead of "
                             "just the changed registers")
    args = parser.parse_args()

    prev = None
    try:
        lines = open(args.trace).read().splitlines()
    except OSError as e:
        sys.exit(f"Error: cannot read trace: {e}")

    for k, line in enumerate(l for l in lines if l.strip()):
        body, _, comment = line.partition("#")
        fields = body.split()
        if len(fields) != NUM_FIELDS:
            sys.exit(f"Error: {args.trace}:{k + 1}: expected {NUM_FIELDS} "
                     f"fields, got {len(fields)}.")

        cycle = re.search(r"cycle=(\d+)", comment)
        time = re.search(r"time=(\d+)", comment)
        insn = re.search(r"insn=([0-9a-fA-F]+)", comment)
        meta = (f" cycle={cycle.group(1)}" if cycle else "") + \
               (f" time={time.group(1)}" if time else "") + \
               (f" insn={insn.group(1)}" if insn else "")

        header = ("anchor  " if k == 0 else f"#{k:<7}") \
            + f"pc={fields[0]}{meta}"

        if args.full:
            print(header)
            for i in range(1, NUM_FIELDS):
                print(f"    x{i:<3}({ABI_NAMES[i]:<6}) = {fields[i]}")
        else:
            changes = []
            for i in range(1, NUM_FIELDS):
                if prev is None or fields[i] != prev[i]:
                    changes.append(f"x{i}({ABI_NAMES[i]})={fields[i]}")
            print(header + ("   " + "  ".join(changes) if changes else ""))
        prev = fields

    return 0


if __name__ == "__main__":
    sys.exit(main())

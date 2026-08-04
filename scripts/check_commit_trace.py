#!/usr/bin/env python3
"""
check_commit_trace.py — the verify-trace comparator.

Compares the RTL per-commit architectural state trace (commit_trace.txt,
written by tb/commit_verifier.sv when simulating with +commit_trace) against
the reference simulator's state trace (written by the refsim 'statetrace'
command). Both files hold one line per committed instruction — the retiring
PC then x1..x31 in hex — plus an initial anchor line (state before the first
commit). '#' comments (the RTL side carries ' #cycle=N time=T insn=X') are
ignored for comparison and read back for the divergence report.

Because each line is a *full* architectural state keyed by "one committed
instruction", the diff self-anchors: the first divergent line is the exact
faulty instruction, and a single mismatch cannot slip the alignment of
everything after it (unlike the old write-event-indexed flow).

Exit status: 0 = traces match, 1 = divergence found, 2 = usage/IO error.
"""

import argparse
import re
import sys

# ABI names for x0..x31, for readable register reports
ABI_NAMES = [
    "zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
    "s0/fp", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
    "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
    "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6",
]

NUM_FIELDS = 32  # pc + x1..x31


def reg_name(i):
    """Name of the register held in field i (fields 1..31 are x1..x31)."""
    return f"x{i} ({ABI_NAMES[i]})"


def parse_trace(path):
    """Returns (fields, comments): per line, the list of hex fields with the
    '#' comment split off (comment is '' when absent, as on the ref side)."""
    fields, comments = [], []
    try:
        with open(path) as f:
            for lineno, line in enumerate(f, 1):
                line = line.rstrip("\n")
                if not line.strip():
                    continue
                body, _, comment = line.partition("#")
                parts = body.split()
                if len(parts) != NUM_FIELDS:
                    sys.exit(f"Error: {path}:{lineno}: expected {NUM_FIELDS} "
                             f"fields (pc + x1..x31), got {len(parts)}.")
                fields.append(parts)
                comments.append(comment.strip())
    except OSError as e:
        sys.exit(f"Error: cannot read trace: {e}")
    return fields, comments


def comment_info(comment):
    """Formats the RTL-side ' #cycle=N time=T insn=X' metadata. Every field is
    optional: the refsim side carries no comment at all, and traces written
    before `time=` existed still report their cycle."""
    cycle = re.search(r"cycle=(\d+)", comment)
    time = re.search(r"time=(\d+)", comment)
    insn = re.search(r"insn=([0-9a-fA-F]+)", comment)
    parts = []
    if insn:
        parts.append(f"insn 0x{insn.group(1)}")
    if cycle:
        parts.append(f"retired at RTL cycle {cycle.group(1)}"
                     + (f" (time {time.group(1)})" if time else ""))
    elif time:
        parts.append(f"retired at time {time.group(1)}")
    return ", ".join(parts)


def main():
    parser = argparse.ArgumentParser(
        description="Compare an RTL commit trace against a refsim state trace.")
    parser.add_argument("rtl_trace", help="commit_trace.txt from the RTL sim")
    parser.add_argument("ref_trace", help="statetrace file from the refsim")
    args = parser.parse_args()

    rtl, rtl_comments = parse_trace(args.rtl_trace)
    ref, _ = parse_trace(args.ref_trace)

    # Compare the common prefix line by line (line k = commit #k; line 0 is
    # the pre-commit anchor state).
    for k in range(min(len(rtl), len(ref))):
        if rtl[k] == ref[k]:
            continue

        print(f"Commit traces DIVERGE at commit #{k}"
              + (" (initial/reset state)" if k == 0 else "") + ":")
        info = comment_info(rtl_comments[k])
        print(f"  RTL {args.rtl_trace}:{k + 1}"
              + (f"  [{info}]" if info else ""))
        if rtl[k][0] != ref[k][0]:
            print(f"  pc:          rtl={rtl[k][0]}  ref={ref[k][0]}"
                  "  <- control flow diverged")
        else:
            print(f"  pc:          {rtl[k][0]} (same on both sides)")
        for i in range(1, NUM_FIELDS):
            if rtl[k][i] != ref[k][i]:
                print(f"  {reg_name(i)}:".ljust(15)
                      + f"rtl={rtl[k][i]}  ref={ref[k][i]}")
        if k > 0:
            prev_info = comment_info(rtl_comments[k - 1])
            print(f"  previous commit (#{k - 1}) matched: pc {rtl[k - 1][0]}"
                  + (f"  [{prev_info}]" if prev_info else ""))
        print("\nNote: the RTL retire cycle/time is an upper bound — the "
              "wrong value was computed at\nissue/execute, earlier. "
              "`make waves TEST=...`, jump to the time above, and work\n"
              "backwards from there.")
        return 1

    # Same prefix; complain if one side has more commits than the other
    if len(rtl) != len(ref):
        longer, shorter = ((args.rtl_trace, args.ref_trace)
                           if len(rtl) > len(ref)
                           else (args.ref_trace, args.rtl_trace))
        n_long, n_short = max(len(rtl), len(ref)), min(len(rtl), len(ref))
        print(f"Commit traces MATCH for {n_short} lines, but {longer} has "
              f"{n_long - n_short} more commit(s) than {shorter}.")
        if len(rtl) < len(ref):
            print("The RTL retired fewer instructions than the reference: "
                  "core hung/watchdog-killed,\nor the halting instruction "
                  "never committed.")
        else:
            print("The RTL retired more instructions than the reference: "
                  "extra/duplicated commits\n(bubbles or replays reported "
                  "as retirements?).")
        return 1

    n_commits = len(rtl) - 1  # minus the anchor line
    print(f"Commit traces match: {n_commits} commits + anchor state.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""
check_mem_trace.py — the verify-mem comparator.

Compares the RTL's committed memory operations (mem_trace.txt, written by
tb/commit_verifier.sv when simulating with +mem_trace) against the reference
simulator's memory operations (written by the refsim 'memtrace' command). Both
files hold one line per load/store, in program order:

    <pc> <L|S> <addr> <mask> <data>
    004000a4 S 10000000 f 0000002a

`mask` is the byte enables within the containing word (size + lane) and `data`
holds the transferred bytes *in their word lanes*, so both fields describe the
memory bus rather than the register file. '#' comments (the RTL side carries
' #cycle=N time=T insn=X') are ignored for comparison and read back for the
report.

Where check_commit_trace.py stops at the first divergent commit — full
architectural state per line means one mismatch cannot slip the alignment —
this trace is a *sequence* of ops, so the interesting failures are structural:
an op that never happened, one that happened twice, or two that happened in the
wrong order. So the two files are aligned with difflib and each divergent block
is classified:

    MISSING       ops the reference performed, the RTL never committed
    EXTRA         ops the RTL committed, the reference never performed
    OUT OF ORDER  same ops on both sides, different order
    WRONG ...     same op and address, different address/lanes/data

Exit status: 0 = traces match, 1 = divergence found, 2 = usage/IO error.
"""

import argparse
import collections
import difflib
import re
import sys

NUM_FIELDS = 5  # pc, L|S, addr, mask, data

# Divergent blocks reported before giving up; the first one is usually the
# whole story and the rest are its aftershocks.
DEFAULT_MAX_BLOCKS = 10


class Op:
    """One memory operation, plus where it came from."""

    __slots__ = ("pc", "kind", "addr", "mask", "data", "lineno", "comment")

    def __init__(self, fields, lineno, comment):
        self.pc, self.kind, self.addr, self.mask, self.data = fields
        self.lineno = lineno
        self.comment = comment

    def key(self):
        """What the diff compares: everything except provenance."""
        return (self.pc, self.kind, self.addr, self.mask, self.data)

    def __eq__(self, other):
        return self.key() == other.key()

    def __hash__(self):
        return hash(self.key())

    def __str__(self):
        name = "load " if self.kind == "L" else "store"
        return (f"{name} pc={self.pc} addr={self.addr} "
                f"mask={self.mask} data={self.data}")


def parse_trace(path):
    """Reads a memory trace into a list of Ops."""
    ops = []
    try:
        with open(path) as f:
            for lineno, line in enumerate(f, 1):
                body, _, comment = line.partition("#")
                parts = body.split()
                if not parts:
                    continue
                if len(parts) != NUM_FIELDS:
                    sys.exit(f"Error: {path}:{lineno}: expected {NUM_FIELDS} "
                             f"fields (pc op addr mask data), got {len(parts)}.")
                if parts[1] not in ("L", "S"):
                    sys.exit(f"Error: {path}:{lineno}: op must be 'L' or 'S', "
                             f"got {parts[1]!r}.")
                ops.append(Op(parts, lineno, comment.strip()))
    except OSError as e:
        sys.exit(f"Error: cannot read trace: {e}")
    return ops


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
        parts.append(f"committed at RTL cycle {cycle.group(1)}"
                     + (f" (time {time.group(1)})" if time else ""))
    elif time:
        parts.append(f"committed at time {time.group(1)}")
    return ", ".join(parts)


def show(op, path, side):
    """One report line for a single op, with its file position."""
    info = comment_info(op.comment)
    return (f"    {side} {path}:{op.lineno}: {op}"
            + (f"  [{info}]" if info else ""))


def field_deltas(ref_op, rtl_op):
    """Names the fields that differ between two ops, most telling first."""
    named = (("address", ref_op.addr, rtl_op.addr),
             ("op", ref_op.kind, rtl_op.kind),
             ("byte mask", ref_op.mask, rtl_op.mask),
             ("data", ref_op.data, rtl_op.data),
             ("pc", ref_op.pc, rtl_op.pc))
    return [(name, ref, rtl) for name, ref, rtl in named if ref != rtl]


class Finding:
    """One divergence to report, ordered by where it starts in the reference."""

    def __init__(self, tag, headline, detail, ref_ops, rtl_ops, deltas=None):
        self.tag = tag                  # short label for the summary line
        self.headline = headline
        self.detail = detail
        self.ref_ops = ref_ops
        self.rtl_ops = rtl_ops
        self.deltas = deltas or []
        # Sort key: program position, so the report reads in execution order.
        # An EXTRA op has no reference position; fall back to the RTL one.
        self.pos = (ref_ops[0].lineno if ref_ops
                    else (rtl_ops[0].lineno if rtl_ops else 0))

    def report(self, ref_path, rtl_path):
        print(f"{self.headline}{(': ' + self.detail) if self.detail else ''}")
        for op in self.ref_ops:
            print(show(op, ref_path, "ref"))
        for op in self.rtl_ops:
            print(show(op, rtl_path, "rtl"))
        for name, ref_val, rtl_val in self.deltas:
            print(f"      {name}: ref={ref_val}  rtl={rtl_val}")
        print()


def find_reorderings(blocks):
    """Splits the pure insert/delete blocks into reorderings and true
    missing/extra ops.

    An op that difflib reports as deleted *and* (elsewhere) as inserted was not
    dropped and re-invented — it was committed at the wrong point in the
    sequence, which is exactly the out-of-order case this tool exists to name.
    difflib can't see that itself: it anchors on the longest matching run, so a
    transposition always decomposes into an insert plus a distant delete.

    Returns (reorder_pairs, consumed), where consumed holds the ops accounted
    for as reorderings and must therefore not be reported as missing/extra.
    """
    deleted = [op for tag, ref_ops, _ in blocks if tag == "delete"
               for op in ref_ops]
    inserted = [op for tag, _, rtl_ops in blocks if tag == "insert"
                for op in rtl_ops]

    moved = (collections.Counter(op.key() for op in deleted)
             & collections.Counter(op.key() for op in inserted))
    if not moved:
        return [], set()

    by_key_ref, by_key_rtl = collections.defaultdict(list), \
        collections.defaultdict(list)
    for op in deleted:
        by_key_ref[op.key()].append(op)
    for op in inserted:
        by_key_rtl[op.key()].append(op)

    pairs, consumed = [], set()
    for key, count in moved.items():
        for ref_op, rtl_op in zip(by_key_ref[key][:count],
                                  by_key_rtl[key][:count]):
            pairs.append((ref_op, rtl_op))
            consumed.add(id(ref_op))
            consumed.add(id(rtl_op))
    return pairs, consumed


def pairwise_findings(ref_block, rtl_block):
    """Ops already matched one-for-one: report the fields that differ."""
    findings = []
    for ref_op, rtl_op in zip(ref_block, rtl_block):
        if ref_op == rtl_op:
            continue
        deltas = field_deltas(ref_op, rtl_op)
        headline = ("WRONG " + "/".join(n for n, _, _ in deltas)).upper()
        findings.append(Finding("wrong-value", headline, "",
                                [ref_op], [rtl_op], deltas))
    return findings


def classify(tag, ref_block, rtl_block, subalign=True):
    """Turns one divergent block into zero or more Findings."""
    if not rtl_block:
        return [Finding("missing", f"MISSING ({len(ref_block)} op(s))",
                        "the RTL never committed these", ref_block, [])]

    if not ref_block:
        return [Finding("extra", f"EXTRA ({len(rtl_block)} op(s))",
                        "the reference never performs these", [], rtl_block)]

    # A replace block holding the same ops on both sides is a local swap.
    if sorted(op.key() for op in ref_block) == sorted(op.key()
                                                      for op in rtl_block):
        return [Finding("out-of-order",
                        f"OUT OF ORDER ({len(ref_block)} op(s))",
                        "same operations, committed in a different order",
                        ref_block, rtl_block)]

    # Matched one for one: report the fields that actually differ.
    if len(ref_block) == len(rtl_block):
        return pairwise_findings(ref_block, rtl_block)

    # Different lengths: some ops are missing or extra *and* some differ in
    # value, tangled into one block. Re-align on the instruction that issued
    # each op (pc + direction), which survives a wrong address or wrong data,
    # so a dropped store is reported as a dropped store instead of smearing
    # into a wrong-value report for its neighbour. One level only — the
    # sub-blocks are already aligned as well as they are going to be.
    if subalign:
        findings = []
        sub = difflib.SequenceMatcher(
            a=[(op.pc, op.kind) for op in ref_block],
            b=[(op.pc, op.kind) for op in rtl_block], autojunk=False)
        for sub_tag, i1, i2, j1, j2 in sub.get_opcodes():
            if sub_tag == "equal":
                findings.extend(pairwise_findings(ref_block[i1:i2],
                                                  rtl_block[j1:j2]))
            else:
                findings.extend(classify(sub_tag, ref_block[i1:i2],
                                         rtl_block[j1:j2], subalign=False))
        if findings:
            return findings

    return [Finding("mismatch",
                    f"MISMATCH (ref {len(ref_block)} op(s), "
                    f"rtl {len(rtl_block)} op(s))", "",
                    ref_block, rtl_block)]


def counts(ops):
    loads = sum(1 for op in ops if op.kind == "L")
    return f"{len(ops)} ops ({loads} L / {len(ops) - loads} S)"


def main():
    parser = argparse.ArgumentParser(
        description="Compare an RTL memory-op trace against a refsim memtrace.")
    parser.add_argument("rtl_trace", help="mem_trace.txt from the RTL sim")
    parser.add_argument("ref_trace", help="memtrace file from the refsim")
    parser.add_argument("--max-blocks", type=int, default=DEFAULT_MAX_BLOCKS,
                        help="divergent blocks to report (default "
                             f"{DEFAULT_MAX_BLOCKS}; 0 = all)")
    args = parser.parse_args()

    rtl = parse_trace(args.rtl_trace)
    ref = parse_trace(args.ref_trace)

    matcher = difflib.SequenceMatcher(a=[op.key() for op in ref],
                                      b=[op.key() for op in rtl],
                                      autojunk=False)

    blocks, matched = [], 0
    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == "equal":
            matched += i2 - i1
        else:
            blocks.append((tag, ref[i1:i2], rtl[j1:j2]))

    if not blocks:
        print(f"Memory traces match: {counts(ref)}.")
        return 0

    # Ops that moved rather than vanished/appeared, pulled out first so they
    # are not double-reported as a missing/extra pair.
    reorderings, consumed = find_reorderings(blocks)
    findings = [Finding("out-of-order", "OUT OF ORDER",
                        f"committed {rtl_op.lineno - ref_op.lineno:+d} "
                        "position(s) from its place in program order",
                        [ref_op], [rtl_op])
                for ref_op, rtl_op in reorderings]

    for tag, ref_block, rtl_block in blocks:
        ref_block = [op for op in ref_block if id(op) not in consumed]
        rtl_block = [op for op in rtl_block if id(op) not in consumed]
        if ref_block or rtl_block:
            findings.extend(classify(tag, ref_block, rtl_block))

    findings.sort(key=lambda f: f.pos)

    print("Memory traces DIVERGE.\n")
    shown = findings if not args.max_blocks else findings[:args.max_blocks]
    for finding in shown:
        finding.report(args.ref_trace, args.rtl_trace)
    if len(shown) < len(findings):
        print(f"... and {len(findings) - len(shown)} more divergence(s) "
              "(raise --max-blocks to see them).\n")

    tags = sorted({f.tag for f in findings})
    print(f"Summary: {len(findings)} divergence(s) ({', '.join(tags)}), "
          f"{matched} op(s) matched.")
    print(f"  ref {args.ref_trace}: {counts(ref)}")
    print(f"  rtl {args.rtl_trace}: {counts(rtl)}")
    print("\nNote: ops are listed in commit (program) order, so the RTL cycle "
          "is an upper bound —\nthe address was computed, and the access "
          "issued, earlier. `make waves TEST=...`\nand work backwards from "
          "the first block above.")
    return 1


if __name__ == "__main__":
    sys.exit(main())

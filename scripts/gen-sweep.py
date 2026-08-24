#!/usr/bin/env python3
"""
gen-sweep.py — emit a GitHub Actions matrix (JSON) describing a parameter sweep.

Each emitted entry is ONE Verilator build. A build is the expensive part
(minutes); running a test against an existing build is cheap. So the unit of
parallelism is a config, and every config runs the full test list in-job.

Usage:
    scripts/gen-sweep.py --mode bisect-dris
    scripts/gen-sweep.py --mode perf-ofat --tests tests/perf/dhrystone.c

Modes:
    bisect-dris   correctness hunt: vary LTG_DRIS_ENTRIES only, find the
                  threshold where fibm flips from fail to pass.
    perf-ofat     one-factor-at-a-time around the baseline. Cheap, and enough
                  to rank which knobs actually move cycles.
    perf-2d       targeted 2D slices for knobs you expect to interact.

Why not a full cartesian product: GitHub caps a matrix at 256 jobs per run,
and free public repos get ~20 concurrent runners. A 6-knob cartesian is
thousands of builds and tells you less than OFAT does.
"""

import argparse
import json
import sys

# Baseline = rtl/include/config.vh defaults that the sweeps perturb.
BASELINE = {
    "LTG_DRIS_ENTRIES": 32,
    "LTG_SCHED_ENTRIES_CHECKED": 16,
    "LTG_BRANCH_SHELF_ENTRIES": 8,
    "LTG_FETCH_WAYS": 4,
    "LTG_EXECUTE_WAYS": 4,
    "LTG_MEMORY_READ_PORTS": 1,
    "LTG_MEMORY_WRITE_PORTS": 1,
    "LTG_DMEM_READ_DELAY": 8,
    "LTG_IMEM_READ_DELAY": 2,
    "LTG_MEM_READ_WIDTH": 4,
    "LTG_DCACHE_INDEX_BITS": 5,
    "LTG_ICACHE_INDEX_BITS": 5,
    "LTG_DCACHE_WAYS": 2,
    "LTG_ICACHE_WAYS": 2,
}

OFAT_AXES = {
    "LTG_DRIS_ENTRIES": [8, 16, 24, 32, 48, 64],
    "LTG_SCHED_ENTRIES_CHECKED": [4, 8, 16, 32],
    "LTG_BRANCH_SHELF_ENTRIES": [2, 4, 8, 16],
    "LTG_FETCH_WAYS": [1, 2, 4, 8],
    "LTG_EXECUTE_WAYS": [1, 2, 4, 8],
    "LTG_MEMORY_READ_PORTS": [1, 2],
    "LTG_DMEM_READ_DELAY": [2, 4, 8, 16],
    "LTG_DCACHE_INDEX_BITS": [3, 4, 5, 6],
    "LTG_MEM_READ_WIDTH": [2, 4, 8],
}

TWO_D = [
    ("LTG_DRIS_ENTRIES", "LTG_SCHED_ENTRIES_CHECKED"),
    ("LTG_EXECUTE_WAYS", "LTG_MEMORY_READ_PORTS"),
    ("LTG_DMEM_READ_DELAY", "LTG_DCACHE_INDEX_BITS"),
]


def legal(cfg):
    """Drop nonsense configs before they burn a runner."""
    if cfg["LTG_SCHED_ENTRIES_CHECKED"] > cfg["LTG_DRIS_ENTRIES"]:
        return False  # scheduler window can't exceed the shelf
    if cfg["LTG_BRANCH_SHELF_ENTRIES"] > cfg["LTG_DRIS_ENTRIES"]:
        return False
    if cfg["LTG_FETCH_WAYS"] > cfg["LTG_DRIS_ENTRIES"]:
        return False
    return True


def entry(deltas, tests):
    """One matrix entry: a name, a PARAMS string, and the tests to run."""
    cfg = dict(BASELINE)
    cfg.update(deltas)
    if not legal(cfg):
        return None
    # Only pass the knobs that differ from config.vh, so the log shows intent.
    params = " ".join(
        f"+define+{k}={v}" for k, v in sorted(deltas.items())
    ) or ""
    name = "baseline" if not deltas else "_".join(
        f"{k.replace('LTG_', '').lower()}{v}" for k, v in sorted(deltas.items())
    )
    return {"name": name, "params": params, "tests": " ".join(tests)}


def dedupe(entries):
    seen, out = set(), []
    for e in entries:
        if e and e["name"] not in seen:
            seen.add(e["name"])
            out.append(e)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", required=True,
                    choices=["bisect-dris", "perf-ofat", "perf-2d"])
    ap.add_argument("--tests", default="",
                    help="space-separated test paths; mode-specific default")
    ap.add_argument("--max-jobs", type=int, default=200,
                    help="hard cap; GitHub's matrix limit is 256")
    args = ap.parse_args()

    if args.mode == "bisect-dris":
        tests = (args.tests or "tests/c/fibm.c tests/c/fibi.c").split()
        entries = [entry({"LTG_DRIS_ENTRIES": n}, tests)
                   for n in range(8, 65, 2)]

    elif args.mode == "perf-ofat":
        tests = (args.tests or
                 "tests/perf/dhrystone.c tests/perf/fft.c "
                 "tests/perf/spmv.c tests/perf/kosarajus.c").split()
        entries = [entry({}, tests)]
        for knob, values in OFAT_AXES.items():
            for v in values:
                if v == BASELINE[knob]:
                    continue  # already covered by the baseline entry
                entries.append(entry({knob: v}, tests))

    else:  # perf-2d
        tests = (args.tests or "tests/perf/dhrystone.c tests/perf/spmv.c").split()
        entries = []
        for a, b in TWO_D:
            for va in OFAT_AXES[a]:
                for vb in OFAT_AXES[b]:
                    entries.append(entry({a: va, b: vb}, tests))

    entries = dedupe(entries)
    if len(entries) > args.max_jobs:
        print(f"error: {len(entries)} configs exceeds --max-jobs "
              f"{args.max_jobs}; narrow the sweep", file=sys.stderr)
        sys.exit(1)

    json.dump(entries, sys.stdout)


if __name__ == "__main__":
    main()

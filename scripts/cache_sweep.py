#!/usr/bin/env python3
"""
cache_sweep.py  —  18-447 cache parameter sweep
------------------------------------------------
Two independent modes:

  Simulation sweep (default):
    Sweeps I/D cache configs, runs tests/perf, collects perflogs. Cache
    geometry and +define+PERF are passed per-run via the Makefile PARAMS
    passthrough (LTG_* macros in rtl/include/config.vh) — no source file
    is rewritten, and the flag stamp rebuilds the sim automatically.

    python3 scripts/cache_sweep.py            # full I + D sweep
    python3 scripts/cache_sweep.py --only I   # I-cache sweep only
    python3 scripts/cache_sweep.py --only D   # D-cache sweep only
    python3 scripts/cache_sweep.py --dry-run  # print without executing

  Synthesis sweep (--synth):
    Separately sweeps configs through make synth (no simulation, no PERF
    define — the netlist stays clean). AFS hosts only.

    python3 scripts/cache_sweep.py --synth    # full synth sweep
    python3 scripts/cache_sweep.py --synth --only I
    python3 scripts/cache_sweep.py --synth --dry-run

  Run from the repository root.
"""

import argparse
import csv
import glob
import os
import re
import shutil
import subprocess
import sys
from itertools import product
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# ── Configuration ─────────────────────────────────────────────────────────────

TESTS_DIR     = "tests/perf"
RESULTS_DIR   = "sweep_results"
SYNTH_SRC_DIR = "output"        # where make synth drops reports
CLOCK_PERIOD  = 4.5

# Fixed cache config when sweeping the other side
I_FIXED = dict(ways=2, index_bits=4, policy=1)   # 2-way, 4 index bits, LRU
D_FIXED = dict(ways=2, index_bits=4, policy=1)

# Sweep dimensions
WAYS_OPTIONS   = [2, 4]
INDEX_OPTIONS  = [2, 4, 6]
POLICY_OPTIONS = [1, 2]          # 1 = LRU, 2 = MRU
POLICY_NAMES   = {0: "DIRECT", 1: "LRU", 2: "MRU"}

# ── PARAMS builder ────────────────────────────────────────────────────────────
#
# Cache geometry lives in rtl/include/config.vh as `ifndef-guarded LTG_*
# macros; per-run overrides go through the Makefile's PARAMS passthrough
# (the flag stamp rebuilds the sim automatically when PARAMS changes), so
# no source file is ever rewritten.

def ltg_params(i: dict, d: dict, extra: str = "") -> str:
    defines = [
        f"+define+LTG_ICACHE_WAYS={i['ways']}",
        f"+define+LTG_ICACHE_INDEX_BITS={i['index_bits']}",
        f"+define+LTG_ICACHE_POLICY={i['policy']}",
        f"+define+LTG_DCACHE_WAYS={d['ways']}",
        f"+define+LTG_DCACHE_INDEX_BITS={d['index_bits']}",
        f"+define+LTG_DCACHE_POLICY={d['policy']}",
    ]
    if extra:
        defines.append(extra)
    return " ".join(defines)


# ── Simulation ────────────────────────────────────────────────────────────────

def find_test_cases() -> List[str]:
    tests = sorted(glob.glob(f"{TESTS_DIR}/*.c"))
    if not tests:
        sys.exit(f"ERROR: No test cases found in {TESTS_DIR}/")
    return tests


def run_sim(test_path: str, params: str, log_path: str, dry_run: bool) -> int:
    # `make sim` (not verify): perf sweeps want the counters, and the class
    # .reg oracles are toolchain-coupled anyway (see docs/porting-log.md).
    cmd = ["make", "sim", f"TEST={test_path}", f"PARAMS={params}"]
    if dry_run:
        print(f"      [dry-run] {' '.join(cmd)}  >  {log_path}")
        return 0
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    with open(log_path, "w") as log:
        result = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT)
    return result.returncode


# ── Synthesis ─────────────────────────────────────────────────────────────────

def run_synth(dest_dir: str, tag: str, params: str, dry_run: bool):
    """veryclean → synth → move reports out of output/ before next veryclean."""
    os.makedirs(dest_dir, exist_ok=True)
    for cmd in [["make", "veryclean"],
                ["make", "synth", f"CLOCK_PERIOD={CLOCK_PERIOD}",
                 f"PARAMS={params}"]]:
        if dry_run:
            print(f"      [dry-run] {' '.join(cmd)}")
        else:
            subprocess.run(cmd, check=True)

    # Collect any .rpt / .log / .txt reports that aren't under output/simulation
    patterns = [f"{SYNTH_SRC_DIR}/**/*.rpt",
                f"{SYNTH_SRC_DIR}/**/*.log",
                f"{SYNTH_SRC_DIR}/**/*.txt"]
    moved = 0
    for pattern in patterns:
        for src in glob.glob(pattern, recursive=True):
            if "simulation" in src.replace("\\", "/"):
                continue
            stem, ext = os.path.splitext(os.path.basename(src))
            dst = os.path.join(dest_dir, f"{tag}__{stem}{ext}")
            if dry_run:
                print(f"      [dry-run] mv {src}  →  {dst}")
            else:
                shutil.move(src, dst)
            moved += 1
    if not dry_run:
        print(f"    Synth: moved {moved} report(s) to {dest_dir}")


# ── Perflog parser ────────────────────────────────────────────────────────────

# Patterns keyed to the $display strings in riscv_core.sv
PERF_PATTERNS = {
    "cycles":       r"total cycles:\s+(\d+)",
    "fetched":      r"total fetch cycles:\s+(\d+)",
    "stall_total":  r"total stall cycles:\s+(\d+)",
    "stall_FD":     r"stall for FD:\s+(\d+)",
    "stall_EMW":    r"stall for EMW:\s+(\d+)",
    "hits_i":       r"hits for instr:\s+(\d+)",
    "miss_i":       r"misses for instr:\s+(\d+)",
    "evict_i":      r"eviction for instr:\s+(\d+)",
    "hits_d":       r"hits for data:\s+(\d+)",
    "miss_d":       r"misses for data:\s+(\d+)",
    "evict_d":      r"eviction for data:\s+(\d+)",
    "num_i_acc":    r"num of instr calls:\s+(\d+)",
    "num_d_acc":    r"num of data calls:\s+(\d+)",
    "conflicts":    r"conflicts for i & d:\s+(\d+)",
    "alu_insts":    r"ALU inst num:\s+(\d+)",
    "load_insts":   r"Num loads:\s+(\d+)",
    "store_insts":  r"Num stores:\s+(\d+)",
}

def parse_perflog(log_path: str) -> dict:
    metrics = {k: None for k in PERF_PATTERNS}
    try:
        with open(log_path) as f:
            text = f.read()
    except FileNotFoundError:
        return metrics
    for key, pat in PERF_PATTERNS.items():
        m = re.search(pat, text)
        if m:
            metrics[key] = int(m.group(1))
    return metrics


def aggregate_metrics(per_test: List[dict]) -> dict:
    """Sum all integer fields across test cases; compute CPI at the end."""
    agg = {k: 0 for k in PERF_PATTERNS}
    for m in per_test:
        for k, v in m.items():
            if v is not None:
                agg[k] += v

    # CPI = cycles / retired_instructions
    # retired = alu + load + store (all non-control-flow) — adjust if you track branches too
    retired = agg["alu_insts"] + agg["load_insts"] + agg["store_insts"]
    agg["retired_insts"] = retired
    agg["cpi"] = round(agg["cycles"] / retired, 4) if retired > 0 else None

    # Hit rates (as percentages, rounded to 1 dp)
    total_i = agg["hits_i"] + agg["miss_i"]
    total_d = agg["hits_d"] + agg["miss_d"]
    agg["hit_rate_i"] = round(100 * agg["hits_i"] / total_i, 1) if total_i else None
    agg["hit_rate_d"] = round(100 * agg["hits_d"] / total_d, 1) if total_d else None

    return agg


# ── Config tag helper ─────────────────────────────────────────────────────────

def config_tag(which: str, cfg: dict) -> str:
    policy = POLICY_NAMES.get(cfg["policy"], str(cfg["policy"]))
    return f"{which}_W{cfg['ways']}_I{cfg['index_bits']}_{policy}"


# ── Main sweep logic ──────────────────────────────────────────────────────────

def sweep(which: str, tests: List[str], dry_run: bool) -> List[dict]:
    sweep_dir = os.path.join(RESULTS_DIR, f"{which}_sweep")
    os.makedirs(sweep_dir, exist_ok=True)

    results = []
    combos  = list(product(WAYS_OPTIONS, INDEX_OPTIONS, POLICY_OPTIONS))
    total   = len(combos)

    for n, (ways, index_bits, policy) in enumerate(combos, 1):
        cfg = dict(ways=ways, index_bits=index_bits, policy=policy)
        tag = config_tag(which, cfg)
        print(f"\n[{n}/{total}] {which}-cache: {tag}")

        # Build the PARAMS override for this configuration (+ perf counters)
        params = ltg_params(
            i=cfg if which == "I" else I_FIXED,
            d=cfg if which == "D" else D_FIXED,
            extra="+define+PERF",
        )

        # Simulate all test cases
        logs_dir  = os.path.join(sweep_dir, tag, "logs")
        per_test  = []
        for test in tests:
            test_name = Path(test).stem
            log_path  = os.path.join(logs_dir, f"{test_name}.perflog")
            print(f"  sim  {test_name}", end=" … ", flush=True)
            rc = run_sim(test, params, log_path, dry_run)
            print("ok" if rc == 0 else f"FAILED (rc={rc})")
            per_test.append(parse_perflog(log_path) if not dry_run else {})

        # Aggregate and record
        agg = aggregate_metrics(per_test)
        results.append({
            "tag":        tag,
            "ways":       ways,
            "index_bits": index_bits,
            "policy":     POLICY_NAMES[policy],
            **agg,
        })

    return results


# ── Output ────────────────────────────────────────────────────────────────────

TABLE_COLS = [
    ("tag",          "config",       30),
    ("ways",         "ways",          5),
    ("index_bits",   "idx_bits",      9),
    ("policy",       "policy",        7),
    ("cycles",       "cycles",       10),
    ("retired_insts","retired",      10),
    ("cpi",          "CPI",           8),
    ("hit_rate_i",   "hit%_I",        8),
    ("miss_i",       "miss_I",        8),
    ("evict_i",      "evict_I",       9),
    ("hit_rate_d",   "hit%_D",        8),
    ("miss_d",       "miss_D",        8),
    ("evict_d",      "evict_D",       9),
    ("stall_FD",     "stall_FD",      9),
    ("stall_EMW",    "stall_EMW",    10),
    ("conflicts",    "conflicts",    10),
]

def print_table(results: List[dict], which: str):
    print(f"\n{'─'*100}")
    print(f"  {which}-Cache Sweep Results")
    print(f"{'─'*100}")
    header = "  " + "  ".join(label.ljust(w) for _, label, w in TABLE_COLS)
    print(header)
    print("  " + "-" * (sum(w for _, _, w in TABLE_COLS) + 2 * len(TABLE_COLS)))
    for r in results:
        row = []
        for key, _, w in TABLE_COLS:
            val = r.get(key)
            if val is None:
                cell = "—"
            elif key == "cpi":
                cell = f"{val:.4f}"
            elif key in ("hit_rate_i", "hit_rate_d"):
                cell = f"{val:.1f}%"
            else:
                cell = str(val)
            row.append(cell.ljust(w))
        print("  " + "  ".join(row))


def save_csv(results: List[dict], which: str):
    if not results:
        return
    path = os.path.join(RESULTS_DIR, f"{which}_sweep_results.csv")
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=results[0].keys())
        writer.writeheader()
        writer.writerows(results)
    print(f"\n  CSV saved → {path}")


# ── Synth sweep ───────────────────────────────────────────────────────────────

def synth_sweep(which: str, dry_run: bool):
    """
    Sweep cache configs through make synth only — no simulation.
    Run this separately, without PERF defined, so the netlist is clean.
    """
    sweep_dir = os.path.join(RESULTS_DIR, f"{which}_synth_sweep")
    os.makedirs(sweep_dir, exist_ok=True)

    combos = list(product(WAYS_OPTIONS, INDEX_OPTIONS, POLICY_OPTIONS))
    total  = len(combos)

    for n, (ways, index_bits, policy) in enumerate(combos, 1):
        cfg = dict(ways=ways, index_bits=index_bits, policy=policy)
        tag = config_tag(which, cfg)
        print(f"\n[{n}/{total}] synth {which}-cache: {tag}")

        params = ltg_params(
            i=cfg if which == "I" else I_FIXED,
            d=cfg if which == "D" else D_FIXED,
        )

        dest = os.path.join(sweep_dir, tag)
        print(f"  synth …", end=" ", flush=True)
        try:
            run_synth(dest, tag, params, dry_run)
            print("ok")
        except subprocess.CalledProcessError as e:
            print(f"FAILED: {e}")

    print(f"\nSynth reports saved under {sweep_dir}/")


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="18-447 cache parameter sweep")
    parser.add_argument("--only",    choices=["I", "D"],
                        help="Sweep only I or D cache")
    parser.add_argument("--dry-run", action="store_true",
                        help="Print commands without executing")
    parser.add_argument("--synth",   action="store_true",
                        help="Run synthesis sweep only (no simulation). "
                             "(PERF is never defined for synth.)")
    args = parser.parse_args()

    os.makedirs(RESULTS_DIR, exist_ok=True)
    targets = ["I", "D"] if args.only is None else [args.only]

    if args.synth:
        print("=== Synthesis sweep ===")
        for which in targets:
            synth_sweep(which, dry_run=args.dry_run)
    else:
        tests = find_test_cases()
        print(f"Found {len(tests)} test case(s): {[Path(t).stem for t in tests]}")

        for which in targets:
            fixed = D_FIXED if which == "I" else I_FIXED
            fixed_tag = config_tag("I" if which == "D" else "D", fixed)
            print(f"\n{'='*60}")
            print(f"  Sweeping {which}-cache   (other fixed: {fixed_tag})")
            print(f"{'='*60}")

            results = sweep(which, tests, dry_run=args.dry_run)
            print_table(results, which)
            if not args.dry_run:
                save_csv(results, which)

    print("\nDone.")


if __name__ == "__main__":
    main()
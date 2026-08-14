# Performance counters — what exists, what to trust, where we stand

Status as of 2026-08-12. Companion to `docs/perf-counters-plan.md` (the plan,
now executed) and the `2026-08-11` entries in `docs/porting-log.md` (the
narrative). This file is the living reference: the counter inventory, their
trust status, and the current standing against the baseline.

**The in-order core is the baseline.** `CORE=inorder` (`rtl/core/riscv_core.sv`,
the 8-stage in-order pipeline that passes the class autograder suite) is the
number Lightning has to beat. Every Lightning result below is quoted as a ratio
against it. At default configuration Lightning currently beats it on **one of
four** perf benchmarks, plus `tests/c/fibi.c` (§1.1).

---

## 1. Standing vs the baseline

`tests/perf`, VCS, defaults (32-entry DRIS, 4 fetch / 4 exec ways, 8-entry
branch shelf, 1 KB I$ and 1 KB D$ both 2-way × 32 sets × 4-word blocks).

| benchmark | in-order (baseline) | Lightning | Lightning vs baseline |
|---|---:|---:|---|
| dhrystone | 12,184,845 | 9,828,242 | **1.24× faster** |
| fft | 7,527,873 | 7,566,159 | 0.995× — parity |
| spmv | 12,847,326 | 15,452,918 | **0.83× — 20% slower** |
| kosarajus | 15,291,881, `Correct` | 20,000,000 (watchdog) | **fails to complete** |

IPC, using the architectural retired count (identical on both cores for a
fixed binary — see §3):

| benchmark | retired | in-order IPC | Lightning IPC |
|---|---:|---:|---:|
| dhrystone | 4,889,053 | 0.401 | 0.497 |
| fft | 3,885,328 | 0.516 | 0.514 |
| spmv | 7,055,601 | 0.549 | 0.457 |
| kosarajus | — | — | 0.006 (112,300 retired in 20M cycles) |

I$ misses — the one cache figure that means the same thing on both cores
(a block fill from main memory):

| benchmark | in-order | Lightning | ratio |
|---|---:|---:|---:|
| dhrystone | 466,100 | 548,085 | 1.2× |
| fft | 306,182 | 926,409 | 3.0× |
| spmv | 112 | 244,900 | 2,187× |
| kosarajus | 198 | 2,199,096 | 11,107× |

Commit `a3859cd` ("32 entry dris => current lightning is 20% less cycles than
the inorder") is correct **on dhrystone** — 19.3% fewer cycles — but that
result does not generalize to the other three benchmarks.

### 1.1 fibi (2026-08-12)

`tests/c/fibi.c`, same flow, same defaults. Both cores produce identical
register dumps, matching the `fibi.reg` oracle.

| metric | in-order | Lightning | ratio |
|---|---:|---:|---|
| total cycles | 25,321 | 22,438 | **1.13× faster** |
| retired | 22,507 | 22,507 | identical by construction (§3) |
| IPC | 0.889 | 1.003 | 1.13× |
| I$ misses | 21 | 858 | 40.9× worse |

A second Lightning win, and for a different reason than dhrystone: the DRIS
never fills (avg 5.6 of 32, **zero** intake stall cycles) and integer slots run
at 29.9% of 4, so the gain is not occupancy — it is retiring in bursts across a
workload that is 75% ALU / 25% control transfer, with only 5 loads and 5 stores
in the whole program. The limiter is the front end: 9,736 cycles (43%) retire
nothing, mispredict rate is 13.8% (821 of 5,965 branches, 793 redirects), and
speculation tax is 1.259.

**The I$ miss count on fibi is the sharpest version of the front-end problem
anywhere in the suite.** fibi's text segment is **196 bytes** — 13 blocks of a
64-block cache, the whole program resident with 80% of the I$ to spare, so the
cold-miss floor is 13. The baseline takes 21. Lightning takes 858, i.e. the
same ~13 blocks refetched ~66× each. See §4.1: this is *not* wrong-path
fetching outside the program.

### What is and isn't understood

- **fft** has a clean explanation: 3× the I$ misses of the baseline, and
  Lightning's highest speculation tax (1.347 fetched/retired). The OoO gain
  and the extra fetch traffic cancel out.
- **spmv is not understood.** Two plausible causes were tested and both are
  disproven (§4). The intake-stall counters report DRIS-full for 54% of the
  run, but relieving that does not change the cycle count — the counters are
  reporting a symptom, not the cause.
- **kosarajus is a fetch-path livelock**, not slowness. Only **12** mispredict
  redirects across the whole run, against a 98% I$ miss rate (2,199,096 misses
  vs 40,160 hits), a 99%-empty DRIS, and integer slots at 0.1%. Speculation is
  not the mechanism here. The baseline completes the same program correctly in
  15.3M cycles, so the program is fine.

---

## 2. Counter inventory

### Lightning — `rtl/ooo/LightningCore.sv`, `` `ifdef LTG_PERF `` (on by default)

The switch is `` `LTG_PERF ``, **not** `` `PERF `` — `rtl/core` is compiled
before `rtl/ooo` in every build regardless of `CORE`, so `riscv_core.sv:36`'s
`` `define PERF `` is already in scope and sharing the name would silently make
this file's switch a no-op. See `docs/architecture.md`.

| counter | trust |
|---|---|
| total cycles | ✅ |
| instructions retired | ✅ verified == refsim commit count on 53/53 asm tests |
| instructions fetched (DRIS intakes, wrong path included) | ✅ |
| fetch groups accepted | ✅ |
| IPC / CPI / speculation tax (fetched÷retired) | ✅ derived in the print task |
| intake stall cycles, split DRIS-full / shelf-full | ✅ but see §4 — a symptom, not necessarily the limiter |
| flush cycles, mispredict redirects | ✅ |
| cycles with no retire | ✅ |
| instruction mix at retirement (ALU / loads / stores / control transfers) | ✅ properly retirement-gated |
| branches resolved / mispredicted / squashed, mispredict rate | ✅ invariant: mispredicted − squashed = redirects |
| retires per cycle, avg + histogram | ✅ |
| DRIS occupancy avg / max / cycles-at-capacity | ✅ but ≠ intake's occupancy definition (valid-entry popcount vs `fetch_ptr − retire_ptr`) |
| branch shelf occupancy avg / max / cycles-full | ✅ |
| integer slots used/cycle + histogram, memory issues/cycle | ✅ integer figure includes AGU passes |
| I$ hits / misses | ✅ comparable to the baseline |
| D$ hits / misses | ⚠️ counts **loads and stores** — the baseline counts loads only (§3) |
| I$/D$ evictions | ❌ do not use (§3) |
| I$/D$ accesses | ⚠️ main-memory port arbitration cycles, not cache probes |

### In-order baseline — `rtl/core/riscv_core.sv`, `` `ifdef PERF `` (`define`d unconditionally at line 36)

| counter | trust |
|---|---|
| total cycles | ✅ |
| total fetch cycles, total stall cycles, stall FD / EMW | ✅ cycle counts |
| I$ stall breakdown (3 cases), flush cycles | ✅ |
| stall run-length histogram | ✅ |
| `total_instructions` | ⚠️ **never printed**, and mis-gated (§3) |
| ALU / Loads / Stores | ❌ per-cycle W-stage occupancy, not instruction counts (§3) |
| branch / JAL / JALR histograms | ❌ same defect, plus a stage mismatch on the `rewind` bit (§3) |
| I$ hits / misses | ✅ comparable to Lightning |
| D$ hits / misses | ⚠️ counts **loads only** |
| I$/D$ evictions | ❌ do not use (§3) |
| I$/D$ accesses | ⚠️ arbitration cycles, not probes |

### Both cores — `tb/ifetch_bounds_check.sv` (sim only, on by default)

Not a PERF counter: a checker on the core→I$ request seam, instantiated in both
core interfaces, that range-checks every fetch address against the loaded
program image (`mem.text.bin` / `mem.ktext.bin` sizes — the extent the test's
disassembly covers). Prints bounds at time 0, up to 20 violations inline
(`IFETCH-OOB:`), an end-of-run summary, and the full per-address record to
`ifetch_oob.log`. Reporting only unless built `+define+IFETCH_BOUNDS_FATAL`.

| counter | trust |
|---|---|
| I$ read requests | ✅ requests at the seam, not cache probes — differs from cycles when the front end stalls |
| in-bounds fetch footprint (low..high) | ✅ |
| out-of-bounds requests + distinct addresses | ✅ |
| unknown-address requests | ⚠️ both cores report exactly 1, cycle 1 — the X fetch PC coming out of reset. Benign; anything above 1 is not |

Costs no cycles: both cores' totals are unchanged with the checker in.

Neither core's stall-breakdown counters are comparable to the other's: the
in-order core reports pipeline stalls (FD/EMW), Lightning reports front-end
intake blocking. There is no shared definition.

---

## 3. Known-bad counters, and how they were established

**In-order instruction-mix and branch counters are per-cycle, not
per-instruction.** They increment every cycle straight off W-stage control
signals with no validity gate (`riscv_core.sv:948-975`), so bubbles and flush
cycles are counted as instructions. On `beqtest` they sum to
`ALU 97 + branches 21 = 118` = exactly the total cycle count, against 21
actually-retired instructions. The `rewind` index bit on the branch/JAL/JALR
histograms is worse: it samples `correct_branch_prediction`, an **M1**-stage
signal, against a **W**-stage instruction.

Lightning's equivalents *are* retirement-gated and correct, so these rows
cannot be compared in either direction — only Lightning's are meaningful.

**The in-order core's one real retired counter is never printed.**
`total_instructions` (`riscv_core.sv:911-916`) excludes bubbles and wrong-path
work, but no `$display` emits it, and it carries the same M1-vs-W stage
mismatch, so it would undercount by roughly one per mispredict. This is why
in-order IPC in §1 is computed rather than read.

**Retired instruction counts are identical across cores by construction** — a
fixed binary retires a fixed number of instructions. Verified directly: the
in-order commit trace matches the reference sim on `beqtest` / `depend` /
`memtest2` (21 / 316 / 93), the same counts Lightning's counter reports. That
is what makes the IPC comparison in §1 sound without touching the baseline
core.

**`is_eviction` is unusable on both cores.** It is gated on
`(&way_valid) && (|current_set.metadata)` and only sampled during refill
(`cache3.sv:373-376`, `cache3.sv:280`), so it cannot be reconciled with the
miss counts: Lightning's spmv run reports 244,900 I$ misses against **8**
evictions in a 64-block cache, and the baseline's dhrystone run reports 42,011
D$ misses against **0** evictions. Both are arithmetically impossible. Ignore
the eviction rows until this is fixed.

**D$ hit/miss semantics differ between the cores.** Calibrated on `memtest2`
(34 loads, 26 stores retired): the baseline reports 33 hits + 1 miss = 34 =
loads only; Lightning reports 56 + 4 = 60 = loads and stores. The two cores
instantiate different controller FSMs (`cache_controller_ref` vs
`cache_controller2`) around the same `cache3`. Do not compare D$ figures
across cores without accounting for this.

---

## 4. Hypotheses tested

### 4.1 Out-of-bounds fetch — disproven (2026-08-12)

The suspicion: Lightning's I$ misses are wrong-path fetches wandering outside
the program, into the `0xdedede...` segment fill. `tb/ifetch_bounds_check.sv`
(§2) was written to measure it. On fibi:

| | in-order | Lightning |
|---|---:|---:|
| I$ read requests | 25,205 | 22,440 |
| in-bounds footprint | 0x00400000..0x004000c0 | 0x00400000..0x004000c0 |
| out-of-bounds requests | **0** | **5** (1 distinct address) |
| unknown-address requests | 1 | 1 |

Lightning's five violations are all `0x004000d0` on cycles 22428–22432 — the
last five cycles of the run, the front end running 12 bytes off the end while
the machine drains at halt. Tail noise, not a mechanism. Text runs to
`0x004000c4`, which agrees with `fibi.disassembly.s` (last instruction
`jalr` at `0x4000bc`, `unimp` at `0x4000c0`).

So **all 858 misses are requests for addresses inside a 196-byte program**,
which makes the number worse, not better: nothing is evicted by capacity or
conflict (13 resident blocks in a 64-block cache), so blocks are being
installed and then lost, or never installed at all.

The suggestive figure is **793 mispredict redirects** and 792 flush cycles
against 858 misses — roughly one extra miss per redirect, over a 13-block
floor. Prime suspect: the `core_req_cancel` path, a redirect killing an
in-flight refill so the line is never installed and the post-mispredict
re-fetch misses again. Consistent with the §4.2 sizing nulls — if lines are
being dropped rather than evicted, no `LTG_ICACHE_INDEX_BITS` value helps.
**Not yet confirmed**: needs cancels instrumented against refill completions in
`cache_controller2`. Open question 5.

### 4.2 Tuning knobs already tested — both null

Both were run against spmv, where Lightning trails the baseline by 20%.

| configuration | cycles | vs default |
|---|---:|---|
| default | 15,452,918 | — |
| `LTG_ICACHE_INDEX_BITS=8` (8× I$, 8 KB) | 15,452,903 | −15 cycles |
| `LTG_DRIS_ENTRIES=64` (2× DRIS) | 15,452,927 | +9 cycles, still `Correct` |

**The I$ result is a genuine null, not a build that didn't take.**
`INSTR_CACHE_INDEX_BITS` traces straight to the define via
`rtl/include/parameters.vh:18`, and the larger cache did change behaviour —
I$ evictions moved 8 → 0 — while misses stayed at 244,897 vs 244,900. So
Lightning's spmv I$ misses are **not capacity or conflict misses**, and no
amount of I$ sizing recovers that benchmark.

**The DRIS result is more informative than the cycle count suggests.** The
stall simply relocated: DRIS-full fell 8,299,935 → 2,373,424 while
branch-shelf-full rose 1,640,554 → 6,681,203, and the total moved by 9 cycles.
That is what disqualifies the intake-stall counters as a diagnosis — they
report whichever structure happens to be full, not what is actually limiting
throughput. It also retires `LTG_BRANCH_SHELF_ENTRIES` as a candidate, since
the shelf absorbed the pressure without helping.

Three very different configurations landing within 9 cycles of each other
means something serial dominates spmv that none of these knobs touch. It is
**not** memory latency — `tb/main_memory.sv` is combinational, with no delay
model at all.

---

## 5. Open questions

1. **What pins spmv at 15.45M cycles?** Unidentified. The I$, the DRIS and the
   branch shelf are all ruled out, as is memory latency. Execute width is not
   it either (integer slots at 15.1% of 4 ways). This is the blocker for
   Lightning beating the baseline on more than one benchmark.
2. **The kosarajus fetch livelock.** 12 mispredict redirects and a 98% I$ miss
   rate is not a speculation problem; given the spmv null result, a bigger I$
   is unlikely to help. Needs a waveform on the fetch/I$ request path. The
   bounds checker (§2) is worth running here first — it is cheap, and it
   separates "fetching garbage addresses" from "refetching good ones", which
   is exactly the fork §4.1 resolved on fibi.
3. **Fix or delete the in-order mix/branch counters**, and print
   `total_instructions` (after correcting its stage mismatch) so the baseline
   log is self-sufficient for IPC.
4. **Fix `is_eviction`** in `cache3.sv` so eviction counts are usable on both
   cores.
5. **Why does Lightning miss 858 times on a 13-block program?** (§4.1) The
   addresses are in bounds and the cache is 80% empty, so lines are being
   dropped rather than evicted. Test the `core_req_cancel`-kills-refill
   hypothesis by instrumenting cancels against refill completions in
   `cache_controller2`. This is the most tractable lead on the front end, and
   fibi is a 22K-cycle reproduction of it — far cheaper to iterate on than the
   multi-million-cycle perf benchmarks.

## 6. Reproducing

```sh
# baseline
make sim TEST=tests/perf/spmv.c SIM=vcs CORE=inorder
# lightning (LTG_PERF is on by default)
make sim TEST=tests/perf/spmv.c SIM=vcs CORE=lightning
# a knob sweep, into its own build tree so the two cores don't clobber each other
make sim TEST=tests/perf/spmv.c SIM=vcs CORE=lightning \
     OUTPUT_BASE_DIR=output-ltg-dris PARAMS="+define+LTG_DRIS_ENTRIES=64"
```

`SIM=vcs` is required on the lab machines — Verilator does not work in that
environment, which also means `make lint` cannot be run there.
`scripts/cache_sweep.py` parses both cores' PERF logs and sweeps PARAMS.

The I-fetch bounds checker runs by default; its summary is in the same log
(`grep IFETCH` the sim output, per-address record in `ifetch_oob.log` next to
`simulation.reg`). To stop on the first out-of-bounds fetch instead:

```sh
make sim TEST=tests/c/fibi.c SIM=vcs CORE=lightning \
     PARAMS='+define+IFETCH_BOUNDS_FATAL'
```

That aborts the run at the offending cycle and still writes both
`simulation.reg` and `ifetch_oob.log` (the `final` blocks run), but **`make`
still exits 0** — VCS's `$fatal` goes out through `$finish` and the status is
not propagated, same as the watchdog. Grep the log, don't test `$?`.

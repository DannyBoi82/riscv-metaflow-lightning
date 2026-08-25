# Performance counters — what exists, what to trust, where we stand

Standing as of 2026-08-24 (§1.0, the new IIU); counter inventory and analysis
as of 2026-08-15. Companion to `docs/perf-counters-plan.md` (the plan, now
executed) and the `2026-08-11` entries in `docs/porting-log.md` (the
narrative). This file is the living reference: the counter inventory, their
trust status, and the current standing against the baseline.

**The in-order core is the baseline.** `CORE=inorder` (`rtl/core/riscv_core.sv`,
the 8-stage in-order pipeline that passes the class autograder suite) is the
number Lightning has to beat. Every Lightning result below is quoted as a ratio
against it. At default configuration Lightning beats it on **three of four**
perf benchmarks, plus `tests/c/fibi.c` (§1.0).

---

## 1. Standing vs the baseline

`tests/perf`, VCS, defaults (32-entry DRIS, 4 fetch / 4 exec ways, 8-entry
branch shelf, 1 KB I$ and 1 KB D$ both 2-way × 32 sets × 4-word blocks).

### 1.0 New IIU (2026-08-24, `fcadc38`) — current standing

The numbers in §1.1 and below are the **old** IIU. This section is the first
perf measurement after the `InstructionIssueUnit` swap (four BTB predictions
per group, positional `pc → F1 → F2 → D` tracking; `docs/new-iiu-status.md`).
Flow: `make verify TEST=... SIM=vcs CORE=lightning PARAMS='+define+LTG_PERF'`.

The baseline column is unchanged — the IIU is Lightning-only — and re-running
`fibi` on `CORE=inorder` reproduced 25,321 cycles exactly, which is the
cross-check that the old baseline numbers still hold.

| benchmark | in-order | Lightning old IIU | Lightning **new IIU** | vs baseline (was) |
|---|---:|---:|---:|---|
| dhrystone | 12,184,845 | 9,828,242 | 10,074,367 | **1.21×** (was 1.24×) |
| fft | 7,527,873 | 7,566,159 | 6,989,414 | **1.08×** (was 0.995×) |
| spmv | 12,847,326 | 15,452,918 | 14,583,805 | **0.88×** (was 0.83×) |
| kosarajus | 15,291,881, `Correct` | watchdog | watchdog | still fails (but see below) |
| fibi | 25,321 | 22,438 | 18,215 | **1.39×** (was 1.13×) |

Three of four moved the right way. **dhrystone is the one regression**
(+2.5% cycles) and it is also the one benchmark whose I$ misses went up —
those two facts probably belong to each other. fibi is the largest win,
−18.8% cycles.

IPC (same retired counts as below — fixed binaries, §3):

| benchmark | in-order | old IIU | new IIU |
|---|---:|---:|---:|
| dhrystone | 0.401 | 0.497 | 0.485 |
| fft | 0.516 | 0.514 | 0.556 |
| spmv | 0.549 | 0.457 | 0.484 |
| fibi | 0.889 | 1.003 | **1.236** |

**The I$ miss pathology is substantially gone.** §4.1's 40.9×-on-fibi finding
does not survive the swap:

| benchmark | in-order | old IIU | new IIU |
|---|---:|---:|---:|
| fibi | 21 | 858 | **23** |
| fft | 306,182 | 926,409 | **357,203** |
| spmv | 112 | 244,900 | **142** |
| dhrystone | 466,100 | 548,085 | 498,092 |

fibi now sits at 23 against a 13-block cold-miss floor, and fft's 3.0× miss
ratio is down to 1.17×. dhrystone is worse than the **448,076** the §4.1b
cancel fix alone achieved on the old IIU — the only benchmark where the new
front end costs cache behaviour rather than buying it.

**Correctness recovered.** All four `tests/perf` benchmarks now verify
`Correct`. `docs/new-iiu-status.md` recorded fft and spmv as regressed as of
2026-08-19; they pass as of `fcadc38`.

fibi front end, against the same fields §1.1 reports for the old IIU:

| metric | old IIU | new IIU |
|---|---:|---:|
| total cycles | 22,438 | 18,215 |
| instructions fetched | 28,331 | 29,766 |
| speculation tax | 1.259 | 1.323 |
| branches resolved | 5,965 | 5,992 |
| mispredicted / redirects | 821 / 793 | 821 / 794 |
| mispredict rate | 0.138 | 0.137 |
| cycles with no retire | 9,736 (43%) | 9,348 (51%) |
| intake stall cycles | 0 | 3,881 (DRIS 950 / shelf 3,033) |
| DRIS occupancy avg | 5.6 of 32 | **13.99 of 32** (max 30) |
| integer slots used/cycle | 29.9% of 4 | 35.7% of 4 |

The win is occupancy, and it is exactly the mechanism the swap was for: four
real predictions per group instead of one keeps 14 entries in flight where the
old front end managed 5.6, and the machine drains them faster than it can now
refill — which is why intake stall cycles appear (3,881, mostly shelf) where
the old IIU had literally zero. The mispredict *rate* barely moved (0.138 →
0.137), so none of this came from better prediction accuracy; it came from
fetch bandwidth. Absolute no-retire cycles fell (9,736 → 9,348) even as their
share of a shorter run rose to 51% — the front end is still the limiter, just
a faster one.

#### The knob config matters more than the IIU did

`400a564` committed `config.vh` with debug-shrunk knobs — `LTG_DRIS_ENTRIES`
and `LTG_SCHED_ENTRIES_CHECKED` at 8, `LTG_BRANCH_SHELF_ENTRIES` at 4. At
those values Lightning loses to the baseline on **everything**:

| benchmark | Lightning @ 8/8/4 | vs baseline |
|---|---:|---|
| dhrystone | 14,157,471 | 0.86× |
| fft | 10,854,141 | 0.69× |
| spmv | 18,767,890 | 0.68× |
| kosarajus | 19,338,112, `Correct` | 0.79× |

The stall breakdown names the culprit: "branch shelf full" is 5.9–7.2M cycles
at shelf=4 against 80K–1.9M at shelf=8. **The 4-entry shelf is the binding
constraint, not the DRIS.** `config.vh` was restored to 32/32/8 on 2026-08-24;
quote no Lightning number without checking which knobs it was taken at.

#### kosarajus: the livelock is capacity-dependent

The most useful thing to fall out of the sweep. kosarajus **completes**
correctly at 8/8/4 in 19,338,112 cycles, but at 32/32/8 it still watchdogs
with 112,300 retired and IPC 0.006 — the *identical* retire count §1 records
for the old IIU. So the hang survived the IIU swap unchanged and is a function
of DRIS/shelf capacity, which is a much sharper lead than "fetch-path
livelock" was. Whatever it is, a smaller window steps around it.

### 1.x Old IIU (2026-08-15) — history

Everything from here to the end of §1 predates the IIU swap. Kept because the
analysis (the two regimes in §1.2, the occupancy-definition gap in §1.3, the
§4 hypotheses) is still the reasoning that applies; only the numbers moved.

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

> **[2026-08-15] This column is pre-§4.1b.** With the cancel fix Lightning's
> spmv I$ misses are **260** (not 244,900) and dhrystone's are **448,076**.
> Crucially the cycle counts in the table above did **not** move with them
> (spmv by 78 cycles), so do not read this column as a performance gap —
> see §4.1b. fft and kosarajus have not been re-measured.

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

Now that the baseline reports the same fields (§2), the front-end comparison
can be read straight off the two logs rather than inferred:

| metric | in-order | Lightning |
|---|---:|---:|
| instructions fetched | 23,587 | 28,331 |
| speculation tax | 1.048 | 1.259 |
| branches resolved | 5,547 | 5,965 |
| mispredicted / redirects | 542 / 542 | 821 / 793 |
| mispredict rate | 0.098 | 0.138 |
| cycles with no retire | 2,815 (11%) | 9,736 (43%) |
| I$ hits | 24,648 | 15,622 |
| instruction mix (ALU/L/S/CT) | 16,950 / 5 / 5 / 5,546 | 16,950 / 5 / 5 / 5,546 |

The identical mix is the cross-check that both cores' retirement gating is
right — a fixed binary retires a fixed set of instructions. The gap in
*resolved* branches (5,965 vs 5,547, against 5,546 control transfers actually
retired) is wrong-path work: the baseline's flush kills younger instructions
before they reach M1, so it resolves essentially only real branches, while
Lightning resolves 419 that never retire. Same binary, 13.8% mispredict rate
vs 9.8% — the two cores use different predictors, so this is a front-end
difference, not a workload one. 793 redirects against 858 I$ misses over a
13-block floor remains the §4.1 lead.

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
fetching outside the program. **Diagnosed 2026-08-14 (§4.1a):**
`core_req_cancel` discards a miss on the cycle it resolves, before a fill is
ever requested — Lightning issues **19** fill requests in the entire run — and
one block behind a predicted-taken backward branch is starved for the whole
run. 845 of the 858 misses were avoidable.

**[2026-08-15] "Avoidable" turned out not to mean "expensive."** Fixing this
takes fibi to 20 misses against the 13-block floor and leaves the cycle count
where it was (22,438 → 22,441); on dhrystone the same fix costs ~1%. A
cancelled miss never requested a fill, so it never paid the 8-cycle memory
latency — it was cheap and wasteful, not slow. §4.1b has the three-way
measurement. Read this section's miss counts as a cache-behaviour pathology,
not as the front-end's cycle cost.

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

### 1.2 Two regimes — do not generalize a limiter across them (2026-08-15)

The benchmarks are in **opposite** states, and a conclusion drawn from one
does not transfer. Same core, same commit, post-§4.1b fix:

| | DRIS avg (valid-entry) | cycles at capacity | intake stall | regime |
|---|---:|---:|---:|---|
| **fibi** | **5.6 / 32** | **0** | **0** | fetch-starved |
| dhrystone (default) | 16.5 / 32 | 378,058 | 3,487,156 | DRIS-bound |
| dhrystone (1-cycle mem) | 24.5 / 32 | 550,083 | 4,245,145 | DRIS-bound |
| dhrystone (8 KB I$) | 24.9 / 32 | 593,960 | 4,484,697 | DRIS-bound |
| spmv | 22.8 / 32 | 1,534,113 | 8,610,208 | DRIS-bound |

**fibi is starved and never stalls**: the DRIS holds 5.6 of 32 on average, hits
capacity zero times, and intake never blocks for any reason. Nothing downstream
is limiting it — the front end simply cannot deliver instructions fast enough,
which on a 75%-ALU / 25%-control-transfer workload means the redirect rate and
the one-group-per-cycle intake, not the cache (§4.1b). **This is the
compute-bound case and it is a fetch problem.**

**dhrystone and spmv are the opposite** and were so before the §4.1b fix. What
the fix changed is the *degree*: relieving the I$ raised dhrystone's average
occupancy 16.5 → 24.9 and pushed intake stalls 3.49M → 4.48M. Fetch got
faster, so the queue behind it filled — the stall relocated rather than
disappeared, exactly as §4.2 saw when the DRIS was doubled.

Any statement of the form "Lightning's limiter is X" needs to name a regime.

### 1.3 "DRIS full" is mostly not the DRIS being full (2026-08-15)

The two occupancy definitions (§2) disagree by 5.4× on spmv, and the gap is
the most concrete lead open question 1 has:

| spmv | cycles |
|---|---:|
| valid-entry count actually at capacity (32/32) | 1,534,113 |
| intake reporting **DRIS full** | **8,299,678** |

Intake computes `occupancy = fetch_ptr − retire_ptr`
(`InstructionIssueUnit.sv:367`); the PERF counter popcounts valid entries. So
for roughly **6.8M cycles — 44% of the run — intake refuses to accept a group
because the pointers say full, while only ~23 of 32 entries hold a valid
instruction.** Entries are allocated but not reclaimed: `retire_ptr` is not
advancing past work that is already finished.

That makes spmv's dominant stall a **retirement** stall wearing an intake
stall's label, which is consistent with §4.2 (doubling the DRIS relocated the
stall to the shelf and moved the cycle count by 9) and with 68% of spmv's
cycles retiring nothing while the shelf sits at 2.4 of 8. The branch fence
(`branch_fence_valid`, retirement held until the oldest shelved branch
resolves) is the first suspect. Unmeasured so far — see open question 1.

---

## 2. Counter inventory

### Lightning — `rtl/ooo/LightningCore.sv`, `` `ifdef LTG_PERF `` (off by default)

The switch is `` `LTG_PERF ``, **not** `` `PERF `` — `rtl/core` is compiled
before `rtl/ooo` in every build regardless of `CORE`, so `riscv_core.sv`'s
`` `define PERF `` is already in scope and sharing the name would silently make
this file's switch a no-op. See `docs/architecture.md`.

The switch lives in `rtl/ooo/1DRIS_defs.sv` and is **commented out**, so it
has to be asked for: `PARAMS='+define+LTG_PERF'` (or `PARAMS` in `config.mk`
to make it stick); `scripts/cache_sweep.py` passes it. Leaving it off by
default is also what keeps `make synth` working — `print_perf_metrics()` does
`real` arithmetic, which DC rejects (ELAB-922). If it ever gets a default,
guard it as `` `ifdef SIMULATION_18447 ``, the treatment `riscv_core.sv`'s
`` `PERF `` gets.

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
| DRIS occupancy avg / max / cycles-at-capacity | ✅ but ≠ intake's occupancy definition (valid-entry popcount vs `fetch_ptr − retire_ptr`) — **the two disagree by 5.4× on spmv; that gap is a finding, not noise (§1.3)** |
| branch shelf occupancy avg / max / cycles-full | ✅ |
| integer slots used/cycle + histogram, memory issues/cycle | ✅ integer figure includes AGU passes |
| I$ hits / misses | ✅ comparable to the baseline |
| D$ hits / misses | ⚠️ counts **loads and stores** — the baseline counts loads only (§3) |
| I$/D$ evictions | ❌ do not use (§3) |
| I$/D$ accesses | ⚠️ main-memory port arbitration cycles, not cache probes |

### In-order baseline — `rtl/core/riscv_core.sv`, `` `ifdef PERF `` (`define`d under `SIMULATION_18447`, so on in simulation and off for `make synth`)

**Rewritten 2026-08-14 to match Lightning's block field for field** — same
sections in the same order, the same `$display` strings, and the same
definition behind every metric both machines have, so the two logs diff line
by line and one set of `scripts/cache_sweep.py` patterns parses both. The
known-bad rows below (mix, branch histograms, unprinted retired count) are
fixed; §3 records what they used to be. Everything is now retirement- or
event-gated instead of sampled free-running off W-stage control signals.

| counter | trust |
|---|---|
| total cycles | ✅ |
| instructions retired | ✅ `commit_fire` — the commit-trace event; verified == refsim count on `beqtest` / `memtest2` / `depend` (21 / 93 / 316) and on `fibi` (22,507) |
| instructions fetched (F3→D intakes, wrong path included) | ✅ |
| fetch groups accepted | ✅ = instructions fetched (a group is one instruction here) |
| IPC / CPI / speculation tax | ✅ derived in the print task |
| intake stall cycles, split back-pressure / I$-not-ready | ✅ cycles no instruction entered decode for a reason other than a flush; **not** gated on an instruction waiting at the seam (back-pressure freezes the whole front half, I$ request included, so the blocked instruction is usually still upstream of F3) |
| flush cycles, mispredict redirects | ✅ |
| cycles with no retire | ✅ |
| instruction mix at retirement (ALU / loads / stores / control transfers) | ✅ retirement-gated; sums to retired − 1 (the halting instruction, same as Lightning) |
| branches resolved / mispredicted, mispredict rate | ✅ counted in M1 where they are decided; squashed is structurally 0 here, so mispredicted == redirects |
| retires per cycle, avg + histogram | ✅ two bins |
| integer slots used/cycle + histogram, memory issues/cycle | ✅ E-stage occupancy (includes address generation, as Lightning's AGU passes do) and M1 memory issues, both of 1 way |
| I$ hits / misses | ✅ comparable to Lightning |
| D$ hits / misses | ⚠️ counts **loads only** — Lightning counts loads and stores (§3) |
| I$/D$ evictions | ❌ do not use (§3) |
| I$/D$ accesses | ⚠️ arbitration cycles, not probes |
| *in-order only:* total fetch cycles, total stall cycles, stall FD / EMW | ✅ cycle counts, printed in their own section at the end |
| *in-order only:* I$ stall breakdown (3 cases), stall run-length histogram | ✅ |
| *in-order only:* branch / JAL / JALR histograms | ✅ retirement-gated, and `rewind` is now the instruction's own M1 resolution carried to W; on `fibi` the rewind bins sum to 542 = the redirect count |

Printing also changed: the report fires once per run on the halt edge (it used
to fire on every `ecall`), and a `final` block prints it for a run the watchdog
kills — same pattern as Lightning's, so timed-out runs are no longer silent.

Lightning's DRIS-occupancy and branch-shelf sections have no analogue here and
are omitted rather than faked; the two sub-lines under `intake stall cycles`
are per-core by necessity (which structure was full vs which stall held the
seam), though the total means the same thing on both.

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

### Both cores — `tb/icache_shadow.sv` (sim only, `+define+ICACHE_SHADOW`)

Also not a PERF counter: an idealized I$ residency model, instantiated in both
core interfaces next to the bounds checker. Same geometry and policy as the
real cache, but it never drops a fill, so classifying each real miss against it
separates the unavoidable cold/conflict floor from **phantom** misses — blocks
that were already fetched and should still have been resident. It consumes
`cache3`'s `read_addr` (the address currently being tag-compared), plumbed up
through both controllers as `probe_addr`; it drives nothing. The same define
turns on refill accounting inside `cache_controller2` / `cache_controller_ref`
(`CACHE FILLS`, tagged by `%m` so the I$ and D$ are distinguishable).

| counter | trust |
|---|---|
| distinct probes | ✅ held `read_miss` levels collapsed |
| real miss events | ✅ the honest miss count — compare against PERF's inflated one |
| real miss cycles | ✅ reproduces what PERF's "I$ misses" counts, for the comparison |
| ideal (shadow) misses | ✅ the floor, given this core's own probe stream |
| phantom misses | ✅ |
| pessimistic | ✅ self-check, must be 0 while nothing is evicted; once the cache evicts, the two LRU states legitimately diverge and a small count is expected |
| misses killed by a cancel | ✅ misses discarded before a fill was ever requested |
| fills started / completed / dropped / abandoned | ✅ |
| shadow LRU | ⚠️ true LRU vs `cache3`'s 1-bit-per-way metadata; identical for WAYS=2, an approximation above that |

Costs no cycles: register dumps are byte-identical with and without the define
on both cores (fibi). `PLUSARGS='+icache_trace'` adds a per-probe trace to
`icache_probe.log`; `scripts/icache_shadow_report.py` joins the per-block
record against the test disassembly and diffs two runs side by side.

The in-order core's own pipeline-stall breakdown (FD/EMW, the three I$ cases,
the run-length histogram) still has no Lightning analogue and is printed in a
separate section at the end of its report. The `intake stall cycles` total is
comparable; its two sub-lines are not.

---

## 3. Known-bad counters, and how they were established

**[FIXED 2026-08-14] In-order instruction-mix and branch counters were
per-cycle, not per-instruction.** They incremented every cycle straight off
W-stage control signals with no validity gate, so bubbles and flush cycles
counted as instructions. On `beqtest` they summed to `ALU 97 + branches 21 =
118` = exactly the total cycle count, against 21 actually-retired
instructions. The `rewind` index bit on the branch/JAL/JALR histograms was
worse: it sampled `correct_branch_prediction`, an **M1**-stage signal, against
a **W**-stage instruction. All of these are now gated on `commit_fire`, and
`rewind` is latched per instruction in M1 (with a sticky bit so a mispredict
that pulses under `EMW_stall` isn't lost) and carried to W. `beqtest` now
reports `ALU 5 + loads 0 + stores 0 + control transfers 15 = 20` = retired − 1,
and on `fibi` the histogram rewind bins sum to 542, exactly the redirect count.

**[FIXED 2026-08-14] The in-order core's retired counter is now printed.**
`total_instructions` was mis-gated and no `$display` emitted it, which is why
in-order IPC in §1 was computed by hand. It has been replaced by a counter on
`commit_fire` — the same event the commit trace and the register file see —
and `instructions retired` is printed in the same position as Lightning's.
Cross-checked against the reference sim: `beqtest` 21, `memtest2` 93,
`depend` 316, `fibi` 22,507, all exact. The §1 IPC figures still stand.

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
Confirmed as the right suspect but the **wrong mechanism** — see §4.1a.

### 4.1a `core_req_cancel` discards misses — confirmed (2026-08-14)

`tb/icache_shadow.sv` (§2) settles it. The model is a cache of the same
geometry that never drops a fill, fed the real probe stream, so every miss is
classified as either unavoidable (the model missed too) or **phantom** (the
model had the block resident). `+define+ICACHE_SHADOW` also turns on refill
accounting inside both cache controllers.

fibi, `scripts/icache_shadow_report.py output-io/... output-ltg/...`:

| | in-order | Lightning |
|---|---:|---:|
| distinct probes | 24,668 | 16,480 |
| **real miss events** | **19** | **858** |
| real miss cycles (what PERF prints) | 21 | 858 |
| ideal misses — the floor | 13 | 13 |
| **phantom misses** | 6 (32%) | **845 (98.5%)** |
| pessimistic (self-check) | 0 | 0 |
| cancel pulses | 542 | 5,826 |
| **misses killed by a cancel** | — | **839** |
| fills started / completed / lost | 19 / 12 / 5 | **19** / 12 / 7 |

Two things fall out, and the first one was not the standing hypothesis.

**1. The cancel does not kill in-flight refills; it kills misses before a
refill is ever asked for.** Lightning took 858 misses and issued **19** fill
requests to main memory. `cache_controller2`'s cancel override
(`cache_controller2.sv:363-370`) clears `mem_bus_request` in the same
combinational block that `READ_CACHE_RSP` sets it on a `read_miss`, and
`next_state` goes to `IDLE`. So a redirect landing on the cycle a miss
resolves throws the probe away with nothing in flight to lose. That path
accounts for **839 of the 858**; the in-flight-refill path the old §4.1 text
blamed accounts for **7**. 839 killed + 19 survived = 858, and the 19 equals
`fills started` exactly.

**2. One block is starved for the whole run.** `0x004000a0` is probed 841
times, misses 841 times, and is *never installed* — 12 completed fills for 13
blocks. It is `main+0x50`, the loop epilogue, sitting immediately after the
backward loop branch at `0x40009c` (`bne x9, x0, 400078`). The fetch unit runs
sequentially into it every iteration, and the branch's `ct_redirect` cancels
the probe every iteration. Note this fires on *correctly predicted* control
flow: `core_req_cancel = redirect` and `redirect` includes `ct_redirect`,
which `InstructionIssueUnit.sv:322-326` raises on every JAL and every
predicted-taken branch, hence 5,826 cancels against only 793 mispredicts.

The in-order core is the control group and behaves as designed: it cancels
only on a resolved M1 mispredict, so 19 misses against a 13-block floor.

Two corollaries worth carrying forward:

- The PERF "I$ misses" counter counts `read_miss` *cycles*, not events —
  `cache3.sv:317` freezes the request in the LOAD state while the other cache
  owns the bus, re-asserting `read_miss` each cycle. On the baseline that
  inflates 19 to 21. It happens to be exact on Lightning here
  (`miss cycles spent waiting for the bus: 0`), so the 858 is real, but the
  counter is not trustworthy in general. §3.
- This is why §4.2's cache-sizing sweeps were null, and it predicts the same
  for kosarajus (open question 2): the misses are not a capacity or a
  wrong-path problem, so no geometry knob touches them.

**It is not a fibi artifact.** dhrystone, Lightning, same instrument
(9,828,242 cycles — unchanged, so the model costs nothing at scale):

| | dhrystone |
|---|---:|
| real miss events | 548,085 |
| ideal misses (floor) | 396,042 |
| phantom misses | **158,045 (29%)** |
| misses killed by a cancel | 156,011 |
| cancel pulses | 714,102 |
| fills started / completed / lost | 392,074 / 350,032 / 42,042 |
| distinct blocks touched | 187 (cache holds 64) |
| pessimistic (self-check) | 6,002 |

dhrystone genuinely overflows the cache — 187 blocks into 64, 395,978 shadow
evictions — so unlike fibi its floor is dominated by capacity, and the
pessimistic count is non-zero as expected once the real and model LRU states
diverge (§2). Even so, **29% of its I$ misses are avoidable**, and again
almost all of them are misses killed by a cancel rather than lost refills.

`e59a386` on `main` ("the fetch stage is a 2 stage pipeline like the in order
core ... allows correctness without the use of the cancel signal, so now the
same line isn't refetched when the pc redirects") is the fix for exactly this.
Re-running the shadow across the two commits is the before/after measurement.

### 4.1b The fix works and costs cycles — measured (2026-08-15)

The before/after is in. **Dropping the cancel does what it was meant to do to
the cache and makes the program slower**, monotonically: the closer the I$
gets to its ideal miss floor, the more cycles dhrystone takes.

dhrystone, VCS, defaults, `+define+ICACHE_SHADOW`. All three retire an
identical 4,889,053, so these are the same program three ways:

| `core_req_cancel` driven by | cycles | I$ real misses | phantom | fills completed | lost fills |
|---|---:|---:|---:|---:|---:|
| `redirect` (original) | **9,828,242** | 548,085 | 158,045 | 350,032 | 42,042 |
| `mispredict_valid` | 9,924,185 | 448,076 | 50,035 | 386,023 | 48,049 |
| `1'b0` (e59a386) | 9,934,184 | **404,047** | **0** | 404,046 | 0 |

The `1'b0` row is as clean as this cache can get — real misses land exactly on
the shadow model's floor, zero phantom, zero lost fills — and it is the
slowest of the three.

**Why: a cancelled miss is nearly free and a completed fill is not.** The
cancel killed the miss before a fill was ever requested (§4.1a), so it cost a
probe and nothing else. Completing that fill costs the 8 cycles the corrected
§4.2 note describes, on a port the D$ also wants. `mispredict_valid` adds
~36K completed fills over the original — roughly 288K cycles of port
occupancy — against ~100K misses saved, and nets +96K cycles. The original
cancel was accidentally acting as a "don't fill on speculative fetches"
filter, and under this memory model that filter was winning.

So **the 858-misses-over-a-13-block-floor figure in §1.1 was a real pathology
in cache behaviour that was costing almost nothing in cycles** — a symptom,
not the limiter, the same verdict §4.2 reached for the sizing knobs and the
intake-stall counters. Three independent times now the front end has looked
like the culprit and has not been.

**spmv is the clinching case.** Same fix (`mispredict_valid`), same defaults:

| spmv | before | after |
|---|---:|---:|
| I$ misses | 244,900 | **260** |
| total cycles | 15,452,918 | **15,452,840** |

A **940× reduction in I$ misses moved the cycle count by 78 cycles**, 0.0005%.
This retires the §1 "2,187× worse than baseline" I$ row as a performance
finding: it was real, it is now fixed, and it was worth nothing. It also
explains §4.2's I$-sizing null from the other direction — sizing could not
help because misses were never the cost.

### 4.1c How much is the whole memory system worth? — bounded (2026-08-15)

Rather than reason about it, set the memory latency to 1 cycle
(`+define+LTG_DMEM_READ_DELAY=1`, the shared delay buffer of the corrected
§4.2 note) and read off what disappears. This upper-bounds *every* possible
memory-system improvement at once: non-blocking caches, MSHRs, hit-under-miss,
prefetch, larger caches, port de-contention.

dhrystone, Lightning, identical 4,889,053 retired:

| | latency 8 (default) | latency 1 |
|---|---:|---:|
| total cycles | 9,924,185 | **8,261,978 (−16.7%)** |
| IPC | 0.493 | 0.592 |
| cycles with no retire | 6,869,497 | 5,365,272 (65%) |
| **intake stall cycles** | 3,487,156 | **4,245,145 (51%)** |
| I$ misses | 448,076 | 478,100 |
| D$ misses | 36 | 36 |

**The entire memory system is worth at most 16.7% on dhrystone**, and about
half its latency is already being overlapped (7 cycles × 478K fills = 3.35M
removed, total fell 1.66M). Two further points kill the "OoO needs non-blocking
caches" hypothesis as an explanation of the current standing:

- **There is no D-side miss traffic to parallelize.** dhrystone takes **36**
  D$ misses in 9.9M cycles. Memory-level parallelism — the thing a lockup-free
  cache buys an OoO core — has nothing to work with. spmv, the memory-bound
  benchmark, has real D$ traffic (141,208 misses) but even making all of it
  free is 141,208 × 8 = 1.13M cycles, **7.3%** of its 15.45M, against a 20%
  deficit to the baseline. The memory pipe there runs at 0.154 of 1 issue per
  cycle.
- **Removing memory latency makes the actual bottleneck worse.** Intake stalls
  *rose* 3.49M → 4.25M cycles. Feed the machine faster and it chokes further
  upstream; 65% of cycles still retire nothing with memory nearly free.

`LTG_DMEM_READ_DELAY=0` is not a usable data point: the core retires **zero**
instructions and hits the watchdog. `delay_buffer`'s DELAY=0 path claims to be
combinational; something in the seam does not tolerate it. Latent bug, own
question (open question 8).

The consistent signal across §4.1b, §4.1c and §4.2 is the **intake/retire
path** — 51% of dhrystone's cycles and 56% of spmv's are intake stalls, and
they persist or grow as every other structure is relieved.

What is worth keeping from the fix: the miss counters now mean what they say
(phantom ≈ 0), which makes them usable as an instrument for the next
question rather than a distraction. The F-queue that makes any non-`redirect`
cancel *correct* — wrong-path responses are squashed on arrival instead of
being cancelled at the source — is a prerequisite for all three rows above,
not an optional part of the middle one.

A useful side-effect: the shadow's miss-event count and the controller's
bus-wait cycle count are independent measurements of the same discrepancy, and
they agree. In-order fibi reports 19 miss events + 2 bus-wait cycles = the 21
miss cycles PERF prints; Lightning reports 858 + 0 = 858. That is the
de-duplication rule (§2) validating itself.

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

> **[2026-08-15] Do not generalize this null past spmv.** It was only ever
> run on spmv, whose 187-block-free working set does not overflow a 64-block
> I$ — there was no capacity problem to fix. dhrystone genuinely overflows
> (187 distinct blocks into 64, §4.1a), and there the same knob is the
> largest single win measured on this core so far:
>
> | dhrystone | cycles | vs default | I$ misses | I$ evictions |
> |---|---:|---|---:|---:|
> | default (1 KB I$) | 9,924,185 | — | 448,076 | 387,960 |
> | `LTG_ICACHE_INDEX_BITS=8` (8 KB) | **8,240,847** | **−17.0%** | **255** | **0** |
>
> Identical 4,889,053 retired. That is 1.48× the in-order baseline's
> 12,184,845, up from 1.24×. Note it lands within 0.3% of the 1-cycle-memory
> bound in §4.1c (8,261,978): on dhrystone the *entire* memory-system cost is
> I$ capacity misses, and sizing the I$ collects essentially all of it. No
> non-blocking cache, MSHR or prefetcher is needed to get that 17% — and
> none of them could get much more.

**The DRIS result is more informative than the cycle count suggests.** The
stall simply relocated: DRIS-full fell 8,299,935 → 2,373,424 while
branch-shelf-full rose 1,640,554 → 6,681,203, and the total moved by 9 cycles.
That is what disqualifies the intake-stall counters as a diagnosis — they
report whichever structure happens to be full, not what is actually limiting
throughput. It also retires `LTG_BRANCH_SHELF_ENTRIES` as a candidate, since
the shelf absorbed the pressure without helping.

Three very different configurations landing within 9 cycles of each other
means something serial dominates spmv that none of these knobs touch.

> **[CORRECTED 2026-08-15] This paragraph used to end "It is not memory
> latency — `tb/main_memory.sv` is combinational, with no delay model at
> all." That is wrong and it misled the §4.1a fix.** `main_memory.sv` is
> combinational, but the testbench wraps it in a `delay_buffer` with
> `DELAY = 8` (`tb/testbench.sv:128-138`), and `riscv_core_interface`
> arbitrates *both* caches onto that single main-memory port
> (`riscv_core_interface.sv:97-108`). So every fill — I$ as well as D$ —
> pays 8 cycles, and the two caches contend for the port. The instance is
> named `DataDelayBuffer` and parameterized with `DMEMORY_READ_DELAY`,
> which is where the "D-side only" reading came from; it is the shared
> memory delay. Knobs: `LTG_DMEM_READ_DELAY` (default 8) sets it.
> `LTG_IMEM_READ_DELAY` / `IMEMORY_READ_DELAY` exists, is imported at
> `tb/testbench.sv:61`, and is **used nowhere** — a dead knob, not a
> second delay.
>
> The sizing nulls above still stand on their own evidence (evictions
> moved, misses did not). What does not stand is any inference that memory
> latency is free on this testbench: it is 8 cycles a fill, on a port the
> D$ is also trying to use.

---

## 5. Open questions

1. **What pins spmv at 15.45M cycles?** Unidentified, and now bounded on more
   sides. The I$, the DRIS and the branch shelf are all ruled out; execute
   width is not it (integer slots at 15.1% of 4 ways); the memory pipe runs
   at 0.154 of 1 issue/cycle. **2026-08-15:** I$ misses fell 244,900 → 260
   with the §4.1b fix and the cycle count moved 78 cycles, and the D$ ceiling
   is 7.3% (§4.1c) — so the memory hierarchy in total cannot explain a 20%
   deficit. What remains standing is **intake stall at 8,610,208 cycles, 56%
   of the run**, with 68% of cycles retiring nothing. The next measurement
   should target the intake/retire path directly. **§1.3 is the first hard
   evidence there:** intake reports DRIS-full for 8,299,678 cycles while the
   valid-entry count is actually at capacity for only 1,534,113 — a 6.8M-cycle
   gap (44% of the run) in which the DRIS is *not* full but
   `fetch_ptr − retire_ptr` says it is. Next measurement: count cycles where
   `branch_fence_valid` holds retirement, and histogram
   `(fetch_ptr − retire_ptr) − popcount(valid)` — the allocated-but-dead
   entries. If the fence dominates, the fix is in the shelf/retire path and
   nothing in the front end will move spmv.
2. **The kosarajus fetch livelock.** 12 mispredict redirects and a 98% I$ miss
   rate is not a speculation problem; given the spmv null result, a bigger I$
   is unlikely to help. Needs a waveform on the fetch/I$ request path. The
   bounds checker (§2) is worth running here first — it is cheap, and it
   separates "fetching garbage addresses" from "refetching good ones", which
   is exactly the fork §4.1 resolved on fibi.
3. ~~**Fix or delete the in-order mix/branch counters**, and print
   `total_instructions` so the baseline log is self-sufficient for IPC.~~
   **Done 2026-08-14** (§2, §3): the in-order block was rewritten to mirror
   Lightning's field for field, and the baseline log now carries retired
   count, IPC/CPI, speculation tax, mispredict rate and utilization directly.
4. **Fix `is_eviction`** in `cache3.sv` so eviction counts are usable on both
   cores.
5. ~~**Why does Lightning miss 858 times on a 13-block program?**~~
   **Answered 2026-08-14** (§4.1a): `core_req_cancel` discards a miss on the
   cycle it resolves, before any fill is requested — 839 of the 858. Only 19
   fill requests reach memory in the whole run, and one block (`main+0x50`,
   the loop epilogue behind a predicted-taken backward branch) is starved for
   the entire run. The cancel fires on correctly predicted control flow, not
   just mispredicts. ~~Remaining work is the fix, not the diagnosis.~~
   **Fixed and measured 2026-08-15 (§4.1b): the fix is not a speed-up.**
   fibi goes to 20 misses and stays at 22.4K cycles; dhrystone reaches its
   exact ideal miss floor and gets ~1% slower. Closed — but as a cache
   correctness/instrumentation win, not a performance one.
6. **Does the same mechanism explain kosarajus?** (open question 2) §4.1a
   predicts yes: run it under `+define+ICACHE_SHADOW` and check whether
   `misses killed by a cancel` dominates there too. Cheap now that the
   instrument exists. Note §4.1b changes what a "yes" would mean — it would
   explain the 2.2M miss count without implying the watchdog timeout is
   caused by it.

7. **Ship the 8 KB I$?** `LTG_ICACHE_INDEX_BITS=8` is −17.0% on dhrystone
   (§4.2 note) and null on spmv, and takes dhrystone to 1.48× the baseline.
   It costs 8× the I$ area, which is a real trade on a class-sized design but
   not obviously a bad one. Needs the other two benchmarks and a decision on
   whether the default moves.

8. **`LTG_DMEM_READ_DELAY=0` hangs the core.** Zero instructions retired,
   watchdog timeout (§4.1c). `delay_buffer` documents DELAY=0 as
   combinational, so either that path is broken or the core cannot accept a
   same-cycle memory response. Latent, but it blocks the cleanest version of
   the §4.1c experiment and may indicate a real handshake assumption.

9. **Is `IMEMORY_READ_DELAY` supposed to be wired up?** It is defined
   (`LTG_IMEM_READ_DELAY`, default 8), imported at `tb/testbench.sv:61`, and
   used nowhere — the I$ shares `DataDelayBuffer` with the D$. Either wire a
   second delay buffer on the I-side or delete the knob; right now it reads
   as an independently tunable I-side latency and is not one.

## 6. Reproducing

```sh
# baseline
make sim TEST=tests/perf/spmv.c SIM=vcs CORE=inorder
# lightning (LTG_PERF must be asked for)
make sim TEST=tests/perf/spmv.c SIM=vcs CORE=lightning PARAMS='+define+LTG_PERF'
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

The I$ shadow model (§2, §4.1a) is off by default. To reproduce §4.1a:

```sh
make sim TEST=tests/c/fibi.c CORE=inorder   SIM=vcs \
     PARAMS='+define+ICACHE_SHADOW' OUTPUT_BASE_DIR=output-io
make sim TEST=tests/c/fibi.c CORE=lightning SIM=vcs \
     PARAMS='+define+ICACHE_SHADOW' OUTPUT_BASE_DIR=output-ltg
scripts/icache_shadow_report.py output-io/vcs/icache_shadow.log \
     output-ltg/vcs/icache_shadow.log --disas tests/c/fibi.disassembly.s
```

`grep 'I\$ SHADOW'` / `grep -A7 'CACHE FILLS'` for the raw summaries. Add
`PLUSARGS='+icache_trace'` for the per-probe trace (`icache_probe.log`, one
line per probe with its verdict and whether a cancel was live that cycle) —
that is what shows a single block missing on every one of its 841 probes.

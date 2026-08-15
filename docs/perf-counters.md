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
   just mispredicts. Remaining work is the fix, not the diagnosis; `e59a386`
   on `main` claims it.
6. **Does the same mechanism explain kosarajus?** (open question 2) §4.1a
   predicts yes: run it under `+define+ICACHE_SHADOW` and check whether
   `misses killed by a cancel` dominates there too. Cheap now that the
   instrument exists.

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

# Plan: performance counters for Lightning

> **EXECUTED** 2026-08-11, commit `a09bb2e`. Kept for the rationale; it is no
> longer the current state of things. For what exists now, which counters are
> trustworthy, and where Lightning stands against the in-order baseline, see
> **`docs/perf-counters.md`**. Two corrections to what follows: the switch
> shipped as `` `LTG_PERF ``, not `` `PERF `` (the in-order core's `PERF`
> leaks into every build), and sanity checks 3 and 4 below are **false** on
> both cores — see the `2026-08-11` entries in `docs/porting-log.md`.

Implementation plan for adding an `ifdef PERF` counter block to the
Lightning OoO core, mirroring (and extending) the one the in-order core
already has. Written for an implementing agent; all file/line anchors
verified against the tree as of 2026-08-11.

## Background / prior art

The in-order core has a complete, working PERF block:
`rtl/core/riscv_core.sv`, `PERFORMANCE COUNTERS` section (~line 788–992).
Study it before writing anything — it establishes the conventions to keep:

- Counters are `int`s in an `always_ff` block, reset with the core,
  frozen when `halted`.
- A `print_perf_metrics()` task pretty-prints everything, fired on the
  syscall-halt edge (`ctrl_signals_W.syscall` there).
- `` `define PERF `` sits at the top of the core file (line 36), gated
  comment says to comment it out for synthesis. Per-stage tracking
  signals it needs are declared under `ifdef PERF`.
- Cache-event signals come **into the core as always-present ports**
  (`is_eviction_i, read_hit_i, read_miss_i`, same `_d`, `choose_d_cache`,
  `i_d_conflict` — lines 59–63), driven by the wrapper; the counters that
  consume them are the only ifdef'd part. Follow the same pattern for
  Lightning (ports always exist, PERF logic optional) so the port list
  doesn't change shape between builds.

Lightning currently has **no** PERF anything (grep confirms). The
counters live in `rtl/ooo/LightningCore.sv`; the cache-side events must
be plumbed in from `rtl/mem/riscv_core_interface.sv` (the lightning
wrapper), which already has every needed signal as a local wire.

## Part 1 — architecture-independent counters (port from in-order)

These carry over almost verbatim; only the "where do I sample it"
answer changes.

| Counter | In-order source | Lightning source |
|---|---|---|
| Total cycles | `elapsed_cycles` | Same: `+1` per cycle while `~halted`. |
| Instructions fetched | `~stall_F2` per cycle | Count DRIS intakes: sum of `dris_intake_pkts[w]` slots accepted per cycle (see `InstructionIssueUnit.sv` output, `LightningCore.sv` ~line 136 area). Includes wrong-path instructions by definition — that's the point of the metric. Also worth a separate `fetch_groups` counter (I$ responses accepted) since one group = up to `FETCH_WORDS` instrs. |
| Instructions retired | W-stage valid/NOP filter | `$countones(retire_vector)` per cycle (`LightningCore.sv` line 143, entry-indexed vector from the SSC). See "edge cases" for the halting ecall. |
| Correct/incorrect branches | `branch_cnt[b][t][h][r]` indexed at W | Count at BranchShelf resolution. The shelf verifies each branch/JALR and raises `mispredict_valid` on a wrong one (`InstructionIssueUnit.sv`, BranchShelf module line 509+, mispredict output ~line 719). Increment `branches_resolved` per shelf-entry resolution, `branches_mispredicted` when that resolution mispredicts. If the taken/backward/BTB-hit breakdown from the in-order core is wanted, the shelf entry has (or can carry) the needed bits — treat that as a stretch goal, not the baseline. |
| I$/D$ hits, misses, evictions | Core ports from wrapper | Identical mechanism. `riscv_core_interface.sv` already has `is_eviction_i/read_hit_i/read_miss_i` (lines 68–70), the `_d` triple (93–95), `choose_d_cache` (98), `i_d_conflict` (117–120) as local wires feeding nothing but the cache instances. Add the same 8 input ports to `LightningCore` that `riscv_core` has (its lines 59–63), wire them in the wrapper. |
| Cache access counts / I-D conflicts | `num_i_cache/num_d_cache/num_conflicts` | Same, from `choose_d_cache` / `i_d_conflict`. |

Stall-cycle counters (FD/EMW breakdown, run-length histogram) do **not**
port — they're artifacts of the in-order pipeline. Their OoO analogues
are the utilization counters in Part 2 (a "stalled" OoO core shows up as
low scheduler/retire utilization) plus optionally: cycles with
`fetch` blocked (IIU not issuing a request — e.g. `shelf_room` false or
DRIS full), cycles where `retire_vector == 0`, and flush-recovery
cycles (count cycles where `mispredict_valid` or a flush mask is live).

## Part 2 — OoO-specific counters (the important new ones)

All are "accumulate per cycle, divide by elapsed_cycles at print time".
Do the division in the print task with `real` casts — no division in
counter logic.

### 2a. Average retires per cycle
- Accumulator: `retired_total += $countones(retire_vector)` each cycle.
- Also keep a small histogram `retire_hist[RETIRES_PER_CYCLE+1]` indexed
  by that popcount — "avg 1.3" hides whether that's steady 1–2 or bursts
  of 4 between droughts, and the histogram is nearly free.
- `RETIRES_PER_CYCLE` comes from `SaneStateController.sv` /
  `DRIS_defs` (= REG_RETIRES + MEMORY_RETIRES).
- Print: `retired_total`, IPC (`retired_total / elapsed_cycles`), and
  the histogram.

### 2b. Average DRIS utilization
- `dris_entries` is visible in `LightningCore.sv` (line 128).
- Per cycle: `dris_occ = $countones` over
  `dris_entries[i].entry_state.valid` (build a packed vector in an
  `always_comb` first; `$countones` needs a vector, not an unpacked
  array). Accumulate `dris_occ_total`; also track `dris_occ_max` and
  count of cycles at full (`== DRIS_NUM_ENTRIES`) — "how often are we
  intake-blocked because the shelf is full" is the actionable number.
- Print avg (`/elapsed_cycles`), max, cycles-full.

### 2c. Average branch shelf utilization
- `shelf_free_count` exists (`InstructionIssueUnit.sv` line 120, width
  `$clog2(BRANCH_SHELF_ENTRIES+1)`). Occupancy =
  `BRANCH_SHELF_ENTRIES - shelf_free_count`.
- It's internal to the IIU. Export it as an IIU output port
  (always-present, like the other perf plumbing) up to `LightningCore`.
  Do not use cross-module hierarchical references — they behave
  differently across Verilator/VCS and this repo requires both.
- Accumulate avg + max + cycles-full, same treatment as the DRIS
  (cycles-full is exactly the `shelf_room` fetch-blocking condition,
  `InstructionIssueUnit.sv` line 343).

### 2d. Average scheduler utilization (execute-slot usage)
- Integer side: `issue_pkts[e].ready_I` (the Scheduler's per-way "this
  slot carries a real issue" bit — `issue_pkt_t` in `1DRIS_defs.sv`
  line ~150). Sample either `issue_pkts` (issue decision) or
  `issue_pkts_reg` (what the exec ways actually chew on,
  `LightningCore.sv` line 359) — pick **`issue_pkts_reg`** so a flushed
  cycle's still-executing older ops count as busy, and say so in a
  comment. Accumulate `int_slots_used += $countones({ready bits})` per
  cycle; denominator per cycle is `EXEC_UNITS`.
- Memory side: `mem_issue_pkts[w].core_req_re | core_req_we` per way
  (`LightningCore.sv` line 153/337). Separate accumulator,
  denominator `MEM_ISSUE_WAYS`.
- Print: avg integer slots used/cycle (and as % of EXEC_UNITS), avg
  memory issues/cycle, plus a `int_issue_hist[EXEC_UNITS+1]` histogram
  (same rationale as retires).

## Implementation order

1. **Ports first**: add the 8 cache-event inputs to `LightningCore`,
   drive them in `riscv_core_interface.sv`; add the shelf-occupancy
   output through IIU. Build both cores (`CORE=lightning`,
   `CORE=inorder`) — no behavior change, `make lint` stays at zero.
2. **PERF skeleton** in `LightningCore.sv`: `` `define PERF `` +
   guard block near the top (copy the in-order file's TRACE/PERF
   define dance, lines 34–47, minus the DEBUG_PIPELINE part unless
   needed), counter declarations, reset, `elapsed_cycles`, and an
   empty `print_perf_metrics()` fired on halt (see edge cases for the
   trigger).
3. **Part 1 counters**, then **Part 2 counters**. Small commits; run
   `make verify TEST=tests/asm/additest.S SIM=vcs` after each.
4. **Sanity pass** (below), then run the tests/perf suite and record
   baseline numbers in this doc or `porting-log.md`.

## Edge cases & repo-specific gotchas

- **Halt trigger for the print**: Lightning's halting ecall never
  retires — `halted = trap_valid && (trap at retire head)`
  (`LightningCore.sv` line 453), and the commit seam force-emits one
  final packet for it. Fire `print_perf_metrics()` on the `halted`
  edge (e.g. `always_ff @(posedge clk) if (halted && ~printed)`), and
  decide explicitly whether the halting ecall counts as retired
  (recommendation: yes, `+1` at print time — matches the commit trace
  and refsim instruction counts).
- **Don't count while halted / in reset**: gate the whole update block
  with `else if (~halted)` exactly like the in-order block, or the
  post-halt cycles before `$finish` pollute averages.
- **Watchdog-killed runs**: tests/perf is where these counters matter
  and `fibm.c` already demonstrates hangs. Add a testbench-safe
  fallback: a `final`-block print guarded by a "not already printed"
  flag (mirror `commit_verifier.sv`'s `dumped` flag pattern). Works in
  both simulators.
- **Flushed-entry retires**: `retire_vector` is retirement only;
  `flush_vector` entries are *not* retired instructions. Never count
  `clear_valid` (`retire_vector | flush_vector`, line 190) as retires.
- **Two-phase memory double-count**: a load/store dispatches through
  the integer Scheduler **twice-ish** — phase 1 (address) via
  `issue_pkts`, phase 2 via `mem_issue_pkts`. The integer-slot
  utilization counter will therefore include AGU passes; that is
  correct (the slot really was occupied) but note it in the printout
  ("int slots include AGU passes") so numbers aren't misread. If a
  pure instruction-mix count (ALU/load/store, like the in-order
  `ALU_inst_num` etc.) is wanted, count it at **retirement** from
  `dris_entries[idx].ctrl_signals` (memRead/memWrite/pc_source), not at
  issue.
- **Simulator portability**: `int` counters, `$countones`, `foreach`
  resets, tasks — all fine in both VCS and Verilator (the in-order
  block already uses them). Keep everything inside `ifdef PERF` except
  the ports. No `real` arithmetic outside the print task.
- **SIM=vcs only on this AFS host; a sim that runs >60s is a hang**
  (see CLAUDE.md / memory). Use `tests/asm` for iteration, tests/perf
  only for the final numbers.
- **`scripts/cache_sweep.py` `PERF_PATTERNS` (line 137)** parses the
  perf printout with regexes that are *already stale* vs the in-order
  core's current strings (e.g. it expects `hits for instr:` but the
  core prints `I$ evictions: ... | hits: ...`). When picking Lightning's
  print format, either match the in-order task's current strings and
  fix `PERF_PATTERNS` once for both, or at minimum add
  lightning-format patterns. Don't silently leave the sweep script
  parsing nothing.
- **Lint**: `make lint` must stay at zero. Unused-signal warnings from
  the always-present ports in non-PERF builds are the likely offender;
  prefer consuming them in the PERF block plus a `lint_off UNUSED`
  metacomment scoped tightly if needed (see porting-log for waiver
  conventions — rtl/core needs inline metacomments, rtl/ooo may work
  from `lint.vlt`).

## Sanity checks (do these before trusting any number)

1. `retired_total` (+1 for the halting ecall, if so decided) equals the
   refsim's instruction count and the commit-trace line count for a few
   `tests/asm` cases (`make verify-trace` output gives commit counts).
2. IPC ≤ RETIRES_PER_CYCLE always; IPC ≤ 1 for a serial-dependency test
   like `dependAdd` family; IPC near `FETCH_WAYS`-bounded ceiling for
   embarrassingly parallel asm.
3. `hits + misses == accesses` per cache (matches `num_i_cache` /
   `num_d_cache` up to in-flight requests at halt).
4. `branches_resolved == ` static count × trip counts for a simple loop
   test; `branches_mispredicted` equals number of `mispredict_valid`
   pulses (count both, assert equal — they're sampled at different
   places).
5. DRIS avg utilization ≤ DRIS_NUM_ENTRIES; shelf avg ≤
   BRANCH_SHELF_ENTRIES; both strictly > 0 on any real test.
6. `make regress` (CORE=lightning and inorder) unchanged: 53/56 asm on
   lightning, mul-only failures — PERF must be observation-only. Also
   build once with PERF commented out to prove the non-PERF build still
   compiles (that's the synthesis configuration).

## Deliverables

- `rtl/ooo/LightningCore.sv`: PERF define + counter block + print task.
- `rtl/ooo/InstructionIssueUnit.sv`: shelf-occupancy output (+ any
  branch-resolution event export).
- `rtl/mem/riscv_core_interface.sv`: cache-event port wiring.
- `scripts/cache_sweep.py`: PERF_PATTERNS updated to the real strings.
- `docs/architecture.md`: one paragraph on the Lightning PERF block
  (keep-updated rule); baseline tests/perf numbers recorded somewhere
  durable (porting-log entry works).
